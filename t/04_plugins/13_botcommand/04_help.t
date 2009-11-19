use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 14;

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
            irc_join
            irc_notice
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

sub _shutdown {
    my ($kernel, $error) = @_[KERNEL, ARG0];
    fail($error) if defined $error;
    
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
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
    my $irc = $_[SENDER]->get_heap();

    pass('Logged in');
    $irc->yield(join => '#testchannel');
    return if $irc != $bot1;

    my $plugin = POE::Component::IRC::Plugin::BotCommand->new();
    ok($irc->plugin_add(BotCommand => $plugin), 'Add plugin with no commands');
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    pass('Joined channel');
    return if $irc != $bot2;

    $irc->yield(privmsg => $where, "TestBot1: help");
    $irc->yield(privmsg => $where, "TestBot1: help foo");
}

sub irc_notice {
    my ($sender, $heap, $who, $where, $what) = @_[SENDER, HEAP, ARG0..ARG2];
    my $irc = $sender->get_heap();
    my $nick = (split /!/, $who)[0];

    return if $irc != $bot2;

    $heap->{replies}++;
    ## no critic (ControlStructures::ProhibitCascadingIfElse)
    if ($heap->{replies} == 1) {
        is($nick, $bot1->nick_name(), 'Bot nickname');
        like($what, qr/^No commands/, 'Bot reply');
    }
    elsif ($heap->{replies} == 2) {
        is($nick, $bot1->nick_name(), 'Bot nickname');
        like($what, qr/^Unknown command:/, 'Bot reply');
        my ($p) = grep { $_->isa('POE::Component::IRC::Plugin::BotCommand') } values %{ $bot1->plugin_list() };
        ok($p->add(foo => 'Test command'), 'Add command foo');
        $irc->yield(privmsg => $where, "TestBot1: help");
    }
    elsif ($heap->{replies} == 4) {
        is($nick, $bot1->nick_name(), 'Bot nickname');
        like($what, qr/^Commands: foo/, 'Bot reply');
    }
    elsif ($heap->{replies} == 5) {
        $bot1->yield('quit');
        $bot2->yield('quit');
    }
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $poe_kernel->yield('_shutdown') if $heap->{count} == 2;
}
