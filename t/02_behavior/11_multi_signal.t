use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 14;

my $bot1 = POE::Component::IRC->spawn(),
my $bot2 = POE::Component::IRC->spawn();
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
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress => '127.0.0.1',
        BindPort => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port);
        $heap->{count} = 0;
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
    $heap->{nickcounter} = 0;
    $heap->{port} = $port;
}

sub irc_registered {
    my ($heap, $irc) = @_[HEAP, ARG0];
    
    $heap->{nickcounter}++;
    pass('Registered ' . $heap->{nickcounter});
    isa_ok($irc, 'POE::Component::IRC');

    $irc->yield(connect => {
        nick    => 'TestBot' . $heap->{nickcounter},
        server  => '127.0.0.1',
        port    => $heap->{port},
        ircname => 'Test test bot',
    });
}

sub irc_connected {
    pass('Connected');
}

sub irc_001 {
    my ($sender,$text) = @_[SENDER, ARG1];
    my $irc = $sender->get_heap();
    pass('Logged in');
    $irc->yield('quit');
}

sub irc_error {
    pass('irc_error');
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $kernel->yield('_shutdown') if $heap->{count} == 2;
}

sub _shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    $kernel->alarm_remove_all();
    $kernel->signal($kernel, 'POCOIRC_SHUTDOWN');
    $ircd->yield('shutdown');
}

sub irc_shutdown {
    pass('irc_shutdown');
}
