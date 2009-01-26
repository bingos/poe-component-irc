use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::CycleEmpty;
use POE::Component::Server::IRC;
use Test::More tests => 10;

my $bot1 = POE::Component::IRC::State->spawn( plugin_debug => 1 );
my $bot2 = POE::Component::IRC::State->spawn( plugin_debug => 1 );
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

my $plugin = POE::Component::IRC::Plugin::CycleEmpty->new();
$bot2->plugin_add(CycleEmpty => $plugin);

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001
            irc_join
            irc_part
            irc_disconnected
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress  => '127.0.0.1',
        BindPort     => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port);
        $heap->{count} = 0;
        $wheel = undef;
        $kernel->delay(_shutdown => 60 );
        return;
    }

    $kernel->yield('_shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];

    $ircd->yield('add_i_line');
    $ircd->yield(add_listener => Port => $port);
    
    $bot1->yield(register => 'all');
    $bot1->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
    
    $bot2->yield(register => 'all');
    $bot2->yield(connect => {
        nick    => 'TestBot2',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass($irc->nick_name . ' logged in');
    $irc->yield(join => '#testchannel') if $irc == $bot1;
}

sub irc_join {
    my ($sender, $heap, $who, $where) = @_[SENDER, HEAP, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    
    if (!$heap->{joined} || $heap->{joined} != 2) {
        $heap->{joined}++;
        pass("$nick joined channel");
        $bot2->yield(join => $where) if $irc == $bot1;
    }

    if ($irc == $bot2) {
        $bot1->yield(part => $where);

        if ($heap->{cycling}) {
            pass("$nick rejoined channel");
            $bot1->yield('quit');
            $bot2->yield('quit');
        }
    }
}

sub irc_part {
    my ($sender, $heap, $who, $where) = @_[SENDER, HEAP, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    pass("$nick parted channel");

    if ($irc == $bot2) {
        ok($plugin->is_cycling($where), "$nick is cycling");
        $heap->{cycling} = 1;
    }
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $kernel->yield('_shutdown') if $heap->{count} == 2;
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
}

