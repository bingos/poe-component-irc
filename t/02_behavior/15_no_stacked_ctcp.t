use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket;
use POE::Component::IRC;
use POE::Component::Server::IRC;
use Test::More tests => 6;

my $bot1 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $bot2 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
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
            irc_001
            irc_ctcp_version
            irc_msg
            irc_disconnected
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel) = $_[KERNEL];

    my $ircd_port = get_port() or $kernel->yield(_shutdown => 'No free port');
    $kernel->yield(_config_ircd => $ircd_port);
    $kernel->delay(_shutdown => 60, 'Timed out');
}

sub get_port {
    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress  => '127.0.0.1',
        BindPort     => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    return if !$wheel;
    return unpack_sockaddr_in($wheel->getsockname()) if wantarray;
    return (unpack_sockaddr_in($wheel->getsockname))[0];
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];

    $ircd->yield(add_listener => Port => $port);

    $bot1->yield(register => 'all');
    $bot1->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
    });

    $bot2->yield(register => 'all');
    $bot2->yield(connect => {
        nick    => 'TestBot2',
        server  => '127.0.0.1',
        port    => $port,
    });
}

sub irc_001 {
    my $heap = $_[HEAP];
    my $irc = $_[SENDER]->get_heap();

    pass('Logged in');
    $heap->{connected}++;
    return if $heap->{connected} != 2;

    $bot1->yield(privmsg => $bot2->nick_name(), "\001VERSION\001\001VERSION\001");
    $bot1->yield(privmsg => $bot2->nick_name(), "goodbye");
    $irc->yield(join => '#testchannel');
}

sub irc_ctcp_version {
    my ($sender, $heap) = @_[SENDER, HEAP];
    my $irc = $sender->get_heap();

    $heap->{got_ctcp}++;
    if ($heap->{got_ctcp} == 1) {
        pass('Got first CTCP VERSION');
    }
    elsif ($heap->{got_ctcp} == 2) {
        fail('Got second CTCP VERSION');
    }
}

sub irc_msg {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    my $irc = $sender->get_heap();

    is($msg, 'goodbye', 'Got private message');
    $bot1->yield('quit');
    $bot2->yield('quit');
}
sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $kernel->yield('_shutdown') if $heap->{count} == 2;
}

sub _shutdown {
    my ($kernel, $error) = @_[KERNEL, ARG0];
    fail($error) if defined $error;

    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
}

