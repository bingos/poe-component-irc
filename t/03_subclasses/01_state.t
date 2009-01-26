use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC::State;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 19;

my $bot = POE::Component::IRC::State->spawn();
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

isa_ok($bot, 'POE::Component::IRC::State');

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_registered 
            irc_connected 
            irc_001 
            irc_221
            irc_whois 
            irc_join
            irc_chan_sync
            irc_user_mode
            irc_chan_mode
            irc_mode
            irc_error
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
        $wheel = undef;
        $kernel->delay(_shutdown => 60);
        return;
    }
    
    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot->yield('shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];
    
    $ircd->yield('add_i_line');
    $ircd->yield(add_listener => Port => $port);
    
    $bot->yield(register => 'all');
    $bot->yield(connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_registered {
    my ($irc) = $_[ARG0];
    isa_ok($irc, 'POE::Component::IRC::State');
}

sub irc_connected {
    pass('Connected');
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
    is($irc->server_name(), 'poco.server.irc', 'Server Name Test');
    is($irc->nick_name(), 'TestBot', 'Nick Name Test');
    $irc->yield(whois => 'TestBot');
}

sub irc_whois {
    my ($sender, $whois) = @_[SENDER, ARG0];
    is($whois->{nick}, 'TestBot', 'Whois hash test');
    $sender->get_heap()->yield(join => '#testchannel');
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();
    is($nick, $irc->nick_name(), 'JOINER Test');
    is($where, '#testchannel', 'Joined Channel Test');
}

sub irc_chan_sync {
    my ($sender, $heap, $channel) = @_[SENDER, HEAP, ARG0];
    my $irc = $sender->get_heap();
    my $mynick = $irc->nick_name();
    my ($occupant) = $irc->channel_list($channel);
    
    is($occupant, 'TestBot', 'Channel Occupancy Test');
    ok(!$irc->is_channel_mode_set( $channel, 'i'), 'Channel mode i not set yet');
    ok($irc->is_channel_member($channel, $mynick), 'Is Channel Member');
    ok($irc->is_channel_operator($channel, $mynick ), 'Is Channel Operator');
    ok($irc->ban_mask( $channel, $mynick), 'Ban Mask Test');
    
    $irc->yield(mode => $channel, '+i');
    $heap->{mode_changed} = 1;
}

sub irc_chan_mode {
    my ($sender, $heap, $who, $channel, $mode) = @_[SENDER, HEAP, ARG0..ARG2];
    my $irc = $sender->get_heap();
    return if !$heap->{mode_changed};

    $mode =~ s/\+//g;
    ok($irc->is_channel_mode_set($channel, $mode), "Channel Mode Set: $mode");
}

sub irc_user_mode {
    my ($sender, $who, $channel, $mode) = @_[SENDER, ARG0..ARG2];
    my $irc = $sender->get_heap();
    
    $mode =~ s/\+//g;
    ok($irc->is_user_mode_set($mode), "User Mode Set: $mode");
}

sub irc_mode {
    my $irc = $_[SENDER]->get_heap();
    return if $_[ARG1] !~ /^\#/;
    $irc->delay([ 'quit' ], 3);
}

sub irc_221 {
    my $irc = $_[SENDER]->get_heap();
    pass('State did a MODE query');
    $irc->yield(mode => $irc->nick_name(), '+iw');
}

sub irc_error {
    pass('irc_error');
}

sub irc_disconnected {
    pass('irc_disconnected');
    $poe_kernel->yield('_shutdown');
}
