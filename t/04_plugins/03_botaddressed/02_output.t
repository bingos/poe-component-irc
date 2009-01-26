use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotAddressed;
use POE::Component::Server::IRC;
use Test::More tests => 9;

my $bot1 = POE::Component::IRC->spawn( plugin_debug => 1 );
my $bot2 = POE::Component::IRC->spawn( plugin_debug => 1 );
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

$bot1->plugin_add(BotAddressed => POE::Component::IRC::Plugin::BotAddressed->new());

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001
            irc_disconnected
            irc_join
            irc_bot_addressed
            irc_bot_mentioned
            irc_bot_mentioned_action
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
    pass($irc->nick_name() . ' logged in');
    $irc->yield(join => '#testchannel');
}

sub irc_join {
    my ($sender, $heap, $who, $where) = @_[SENDER, HEAP, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    $heap->{joined}++;
    pass($irc->nick_name() . ' joined channel');
    return if $heap->{joined} != 2;
    
    my $target = $irc->nick_name() eq 'TestBot1' ? 'TestBot2' : 'TestBot1';
    $irc->yield(privmsg => $where, "$target: y halo thar");
    $irc->yield(privmsg => $where, "y halo thar, $target");
    $irc->yield(ctcp => $where, "ACTION greets $target");
}

sub irc_bot_addressed {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    my $irc = $sender->get_heap();

    is($msg, 'y halo thar', 'irc_bot_addressed');
}

sub irc_bot_mentioned {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    my $irc = $sender->get_heap();

    is($msg, 'y halo thar, ' . $irc->nick_name(), 'irc_bot_mentioned');
}

sub irc_bot_mentioned_action {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    my $irc = $sender->get_heap();

    is($msg, 'greets ' . $irc->nick_name(), 'irc_bot_mentioned_action');

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
    my ($kernel) = $_[KERNEL];
    
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
}

