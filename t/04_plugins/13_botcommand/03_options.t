use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::Server::IRC;
use Socket;
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

{
    package TestPlugin;
    use POE::Component::IRC::Plugin 'PCI_EAT_NONE';
    use Test::More;
    use strict;
    use warnings;

    sub new { bless {}, shift }
    sub PCI_register { $_[1]->plugin_register($_[0], 'SERVER', 'public'); 1 }
    sub PCI_unregister { 1 }
    sub S_public { fail("Shouldn't get irc_public event"); PCI_EAT_NONE; }
}

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

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress  => '127.0.0.1',
        BindPort     => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port);
        $kernel->delay(_shutdown => 60, 'Timed out');
        return;
    }
    
    $kernel->yield('_shutdown', "Couldn't bind to an unused port on localhost");
}

sub _shutdown {
    my ($kernel, $reason) = @_[KERNEL, ARG0];
    fail($reason) if defined $reason;
    
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

    pass('Logged in');
    $irc->yield(join => '#testchannel');
    return if $irc != $bot1;

    my $plugin = POE::Component::IRC::Plugin::BotCommand->new(
        Commands  => {
            cmd1 => 'First test command',
            foo  => 'This will get removed',
        },
        Addressed => 0,
        Prefix    => ',',
        Eat       => 1,
    );

    ok($irc->plugin_add(BotCommand => $plugin), 'Add plugin with two commands');
    $irc->plugin_add(TestPlugin => TestPlugin->new());
    
    ok($plugin->add(cmd2 => 'Second test command'), 'Add another command');
    ok($plugin->remove('foo'), 'Remove one command');

    my %cmds = $plugin->list();
    is(keys %cmds, 2, 'Correct number of commands');
    ok($cmds{cmd1}, 'First command is present');
    ok($cmds{cmd2}, 'Second command is present');
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    pass('Joined channel');
    return if $irc != $bot2;

    $irc->yield(privmsg => $where, ",cmd1 foo bar");
    $irc->yield(privmsg => $where, ",cmd2");
}

sub irc_botcmd_cmd1 {
    my ($sender, $user, $where, $args) = @_[SENDER, ARG0..ARG2];
    my $nick = (split /!/, $user)[0];
    my $chan = $where->[0];
    my $irc = $sender->get_heap();

    is($nick, $bot2->nick_name(), 'cmd1 user');
    is($chan, '#testchannel', 'cmd1 channel');
    is($args, 'foo bar', 'cmd1 arguments');
}

sub irc_botcmd_cmd2 {
    my ($sender, $user, $where, $args) = @_[SENDER, ARG0..ARG2];
    my $nick = (split /!/, $user)[0];
    my $chan = $where->[0];
    my $irc = $sender->get_heap();

    is($nick, $bot2->nick_name(), 'cmd2 user');
    is($chan, '#testchannel', 'cmd2 channel');
    ok(!defined $args, 'cmd1 arguments');

    $bot1->yield('quit');
    $bot2->yield('quit');
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $poe_kernel->yield('_shutdown') if $heap->{count} == 2;
}
