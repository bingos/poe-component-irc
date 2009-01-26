use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use Socket;
use Test::More tests => 1;

my $bot = POE::Component::IRC->spawn();

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _try_connect
            _shutdown
            irc_socketerr
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel) = $_[KERNEL];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress  => '127.0.0.1',
        BindPort     => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_try_connect => $port);
        $wheel = undef;
        $kernel->delay(_shutdown => 60);
        return;
    }

    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $bot->yield(unregister => 'socketerr');
    $bot->yield('shutdown');
}

sub _try_connect {
    my ($port) = $_[ARG0];
    
    $bot->yield(register => 'socketerr');
    $bot->yield( connect => {
        nick => 'TestBot',
        server => '127.0.0.1',
        port => $port,
        ircname => 'Test test bot',
    });
}

sub irc_socketerr {
    my ($kernel) = $_[KERNEL];
    pass('Socket Error');
    $kernel->yield('_shutdown');
}
