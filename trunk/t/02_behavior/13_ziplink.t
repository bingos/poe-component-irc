use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Test::Harness;
use Socket;
use Test::More;

my $GOT_ZLIB;
eval {
    require POE::Filter::Zlib::Stream;
    $GOT_ZLIB = 1 if $POE::Filter::Zlib::Stream::VERSION >= 1.96;
};

if (!$GOT_ZLIB) {
    plan skip_all => 'POE::Filter::Zlib::Stream >=1.96 not installed';
}

plan tests => 3;

my $ircd = POE::Component::IRC::Test::Harness->spawn(
    Alias     => 'ircd',
    Auth      => 0,
    AntiFlood => 0,
);

my $irc = POE::Component::IRC->spawn(
    compress => 1,
);

isa_ok($ircd, 'POE::Component::IRC::Test::Harness');
isa_ok($irc, 'POE::Component::IRC');

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001 
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel) = $_[KERNEL];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress => '127.0.0.1',
        BindPort => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port);
        $wheel = undef;
        $kernel->delay(_shutdown => 60);
        return;
    }
    
    $kernel->yield('_shutdown');
}

sub _config_ircd {
    my ($kernel, $heap, $port) = @_[KERNEL, HEAP, ARG0];
    $kernel->post(ircd => 'add_i_line');
    $kernel->post(ircd => 'add_listener' => {
            Port     => $port,
            Compress => 1,
    });

    $irc->yield(register => 'all');
    $irc->yield( connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_001 {
    my ($kernel) = $_[KERNEL];
    pass('Logged in');
    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $kernel->post(ircd => 'shutdown');
    $irc->yield('shutdown');
}

