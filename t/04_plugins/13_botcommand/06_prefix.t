use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::Server::IRC;
use Socket qw(unpack_sockaddr_in);
use Test::More tests => 18;

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
            irc_botcmd_cmd1
            irc_botcmd_cmd2
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

    my $plugin = POE::Component::IRC::Plugin::BotCommand->new(
        Addressed => 0,
        Prefix => '(', # regex metacharacter should not cause issues
        Commands => {
            cmd1 => 'First test command',
            foo  => 'This will get removed',
        },
    );

    ok($irc->plugin_add(BotCommand => $plugin), 'Add plugin with two commands');
    ok($plugin->add(cmd2 => 'Second test command'), 'Add another command');
    ok($plugin->remove('foo'), 'Remove command');

    my %cmds = $plugin->list();
    is(keys %cmds, 2, 'Correct number of commands');
    ok($cmds{cmd1}, 'First command is present');
    ok($cmds{cmd2}, 'Second command is present');
}

sub irc_join {
    my ($heap, $sender, $who, $where) = @_[HEAP, SENDER, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    pass('Joined channel');
    $heap->{joined}++;
    return if $heap->{joined} != 2;

    # try command
    $bot2->yield(privmsg => $where, "(cmd1 foo bar");

    # and one with color
    $bot2->yield(privmsg => $where, "\x02(cmd2\x0f");
}

sub irc_botcmd_cmd1 {
    my ($sender, $user, $where, $args) = @_[SENDER, ARG0..ARG2];
    my $nick = (split /!/, $user)[0];
    my $irc = $sender->get_heap();

    is($nick, $bot2->nick_name(), 'Normal command (user)');
    is($where, '#testchannel', 'Normal command (channel)');
    is($args, 'foo bar', 'Normal command (arguments)');
}

sub irc_botcmd_cmd2 {
    my ($sender, $user, $where, $args) = @_[SENDER, ARG0..ARG2];
    my $nick = (split /!/, $user)[0];
    my $irc = $sender->get_heap();

    is($nick, $bot2->nick_name(), 'Colored command (user)');
    is($where, '#testchannel', 'Colored command (channel)');
    ok(!defined $args, 'Colored command (arguments)');

    $bot1->yield('quit');
    $bot2->yield('quit');
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $poe_kernel->yield('_shutdown') if $heap->{count} == 2;
}
