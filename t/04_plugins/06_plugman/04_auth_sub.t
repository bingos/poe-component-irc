use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::PlugMan;
use POE::Component::Server::IRC;
use Test::More tests => 14;

my $bot1 = POE::Component::IRC::State->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $bot2 = POE::Component::IRC::State->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $bot3 = POE::Component::IRC::State->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

$bot1->plugin_add(PlugMan => POE::Component::IRC::Plugin::PlugMan->new(
    auth_sub => sub { return 1 if $_[1] =~ /^TestBot2!\S+@\S+$/; return },
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd
            _shutdown
            irc_001
            irc_chan_sync
            irc_public
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

    $bot3->yield(register => 'all');
    $bot3->yield(connect => {
        nick    => 'TestBot3',
        server  => '127.0.0.1',
        port    => $port,
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
    $irc->yield(join => '#testchannel');
}

sub irc_chan_sync {
    my ($heap, $where) = @_[HEAP, ARG0];
    is($where, '#testchannel', 'Joined Channel Test');

    $heap->{joined}++;
    if ($heap->{joined} == 3) {
        # these should succeed
        $bot2->yield(privmsg => $where, $bot1->nick_name() . ': plugin_add CTCP POE::Component::IRC::Plugin::CTCP');
        $bot2->yield(privmsg => $where, $bot1->nick_name() . ': plugin_reload CTCP');
    }
}

sub irc_public {
    my $irc = $_[SENDER]->get_heap();
    my $nick = (split /!/, $_[ARG0])[0];
    my $where = $_[ARG1]->[0];
    my $what = $_[ARG2];

    return if $irc == $bot3;

    if ($irc == $bot1) {
        pass($irc->nick_name() . ' got command');

        $_[HEAP]->{commands}++;
        if ($_[HEAP]->{commands} == 2) {
            # should fail and not generate a response
            $bot3->yield(privmsg => $where, $bot1->nick_name() . ': plugin_reload CTCP');
        }
        elsif ($_[HEAP]->{commands} == 3) {
            # this should be the last message on the channel
            $bot1->yield(privmsg => $where, 'LAST MESSAGE');
        }
    }
    elsif ($nick eq $bot1->nick_name()) {
        if ($what eq 'LAST MESSAGE') {
            $bot1->yield('quit');
            $bot2->yield('quit');
            $bot3->yield('quit');
            return;
        }

        pass($irc->nick_name() . ' got response');

        $_[HEAP]->{responses}++;
        if ($_[HEAP]->{responses} > 2) {
            fail "Superfluous message: $what\n";
            return;
        }
    }
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $kernel->yield('_shutdown') if $heap->{count} == 3;
}

sub _shutdown {
    my ($kernel, $error) = @_[KERNEL, ARG0];
    fail($error) if defined $error;

    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
    $bot3->yield('shutdown');
}

