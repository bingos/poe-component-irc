use strict;
use warnings;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Filter::Line);
use POE::Component::IRC;
use Socket;
use Test::More;

my $tests = 4;

eval {
    require Socket6;
    import Socket6;
};

if ($@ or not exists($INC{'Socket6.pm'}) ) {
    plan skip_all => 'Socket6 is needed for IPv6 tests';
}

my $addr = Socket6::inet_pton(&Socket6::AF_INET6, "::1");
if (!defined $addr) {
    plan skip_all => "IPv6 tests require a configured localhost address ('::1')";
}

plan tests => $tests;

my $irc = POE::Component::IRC->spawn();

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            accept_client
            factory_failed
            client_input
            client_error
            irc_connected
            irc_socketerr
            irc_001
        )]
    ]
);

$poe_kernel->run();

sub _start {
    my ($heap) = $_[HEAP];

    $heap->{sockfactory} = POE::Wheel::SocketFactory->new(
        SocketDomain => AF_INET6,
        BindAddress  => '::1',
        BindPort     => 0,
        SuccessEvent => 'accept_client',
        FailureEvent => 'factory_failed',
    );

    my $packed_socket = $heap->{sockfactory}->getsockname;
    if (!$packed_socket) {
        diag("ERROR: Couldn't get the packed socket");
        return;
    }

    eval { ($heap->{bindport}) = unpack_sockaddr_in6($packed_socket) };
    
    if ($@) {
        diag("ERROR: $@");
        return;
    }

    if ($heap->{bindport} == 0) {
        delete $heap->{sockfactory};
        _skip_rest('$heap->{bindport} == 0');
        return;
    }


    $irc->yield(register => 'all');
    $irc->yield(connect => {
        Nick     => 'testbot',
        Server   => '::1',
        useipv6  => 1,
        Port     => $heap->{bindport},
        Username => 'testbot',
        Ircname  => 'testbot 1.1',
    });
}

sub accept_client {
    my ($heap, $socket) = @_[HEAP, ARG0];

    my $wheel = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        InputEvent => 'client_input',
        ErrorEvent => 'client_error',
        Filter     => POE::Filter::Line->new( Literal => "\x0D\x0A" ),
    );
    
    $heap->{client} = $wheel;
}

sub factory_failed {
    my ($heap, $syscall, $errno, $error) = @_[HEAP, ARG0..ARG2];
    delete $_[HEAP]->{sockfactory};
    _skip_rest("syscall error $errno: $error") if $tests;
}

sub client_input {
    my ($heap, $input) = @_[HEAP, ARG0];

    SWITCH: {
        if ($input =~ /^NICK /) {
            pass('Server got NICK');
            $tests--;
            $heap->{got_nick} = 1;
            last SWITCH;
        }
        if ($input =~ /^USER /) {
            pass('Server got USER');
            $tests--;
            $heap->{got_user} = 1;
            last SWITCH;
        }
        if ($input =~ /^QUIT/ ) {
            delete $heap->{client};
            delete $heap->{sockfactory};
            return;
        }
    }

    if ($heap->{got_nick} && $heap->{got_user}) {
        # Send back irc_001
        $heap->{client}->put(':test.script 001 testbot :Welcome to poconet Internet Relay Chat Network testbot!testbot@127.0.0.1');
    }
}

sub client_error {
    my ($heap) = $_[HEAP];
    delete $heap->{client}; 
    delete $heap->{sockfactory};
}

sub irc_connected {
    pass('Connected');
    $tests--;
}

sub irc_socketerr {
    _skip_rest($_[ARG0]) if $tests;
}

sub irc_001 {
    pass('Logged in');
    $irc->yield('shutdown');
}

sub _skip_rest {
    my ($error) = @_;
    
    SKIP: {
        skip "AF_INET6 probably not supported ($error)", $tests;
    }
    $irc->yield('shutdown');
}
