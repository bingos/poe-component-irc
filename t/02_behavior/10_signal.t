use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 7;

my $bot = POE::Component::IRC->spawn();
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_registered 
            irc_connected 
            irc_001 
            irc_error
            irc_disconnected
            irc_shutdown
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
    my ($kernel, $heap, $session, $port) = @_[KERNEL, HEAP, SESSION, ARG0];
    $ircd->yield('add_i_line');
    $ircd->yield(add_listener => Port => $port);
    $kernel->signal($kernel, 'POCOIRC_REGISTER', $session, 'all');
    $heap->{port} = $port;
}

sub irc_registered {
    my ($heap, $irc) = @_[HEAP, ARG0];
    pass('Registered');
    isa_ok($irc, 'POE::Component::IRC');
    
    $irc->yield(connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => $heap->{port},
        ircname => 'Test test bot',
    });
}

sub irc_connected {
    pass('Connected');
}

sub irc_001 {
    my ($kernel, $sender, $text) = @_[KERNEL, SENDER, ARG1];
    my $irc = $sender->get_heap();
    pass('Logged in');
    $irc->yield('quit');
}

sub irc_error {
    pass('irc_error');
}

sub irc_disconnected {
    pass('irc_disconnected');
    $poe_kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $kernel->signal($kernel, 'POCOIRC_SHUTDOWN');
}

sub irc_shutdown {
    pass('irc_shutdown');
}
