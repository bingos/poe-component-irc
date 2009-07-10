use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC::Common qw(parse_user);
use POE::Component::IRC::State;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 48;

my $bot = POE::Component::IRC::State->spawn(Flood => 1);
my $ircd1 = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
    Config    => { servername => 'ircd1.poco.server.irc', },
);

my $ircd2 = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
    Config    => { servername => 'ircd2.poco.server.irc', },
);

my $pass = 'letmein';

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
            irc_305
            irc_306
            irc_whois
            irc_join
            irc_topic
            irc_chan_sync
            irc_user_mode
            irc_chan_mode
            irc_mode
            irc_error
            irc_quit
            irc_disconnected
            ircd_daemon_nick
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
    $ircd1->yield('shutdown');
    $ircd2->yield('shutdown');
    $bot->yield('shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];
    
    $ircd1->yield(add_listener => Port => $port);
    $ircd1->add_peer( name => 'ircd2.poco.server.irc', pass => $pass, rpass => $pass, type => 'c' );
    $ircd2->add_peer( name => 'ircd1.poco.server.irc', pass => $pass, rpass => $pass, type => 'r', auto => 'r', 
                      raddress => '127.0.0.1', rport => $port );
    $ircd2->yield( 'register' );
    $ircd2->yield( 'add_spoofed_nick', nick => 'oper', umode => 'o', );

    $bot->yield(register => 'all');
    $bot->delay([connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    }], 5);
}

sub irc_registered {
    my ($irc) = $_[ARG0];
    isa_ok($irc, 'POE::Component::IRC::State');
}

sub irc_connected {
    pass('Connected');
}

sub irc_001 {
    my ($heap, $server) = @_[HEAP, ARG0];
    my $irc = $_[SENDER]->get_heap();
    $heap->{server} = $server;
    
    pass('Logged in');
    is($irc->server_name(), 'ircd1.poco.server.irc', 'Server Name Test');
    is($irc->nick_name(), 'TestBot', 'Nick Name Test');

    ok(!$irc->is_operator($irc->nick_name()), 'We are not an IRC op');
    ok(!$irc->is_away($irc->nick_name()), 'We are not away');
    #return;
    $irc->yield(away => 'Gone for now');

    $irc->yield(whois => 'TestBot');
}

sub irc_305 {
    my $irc = $_[SENDER]->get_heap();
    ok(!$irc->is_away($irc->nick_name()), 'We are back');
}

sub irc_306 {
    my $irc = $_[SENDER]->get_heap();
    ok($irc->is_away($irc->nick_name()), 'We are away now');
    $irc->yield('away');
}

sub irc_whois {
    my ($sender, $whois) = @_[SENDER, ARG0];
    is($whois->{nick}, 'TestBot', 'Whois hash test');
    $sender->get_heap()->yield(join => '#testchannel');
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = parse_user($who);
    my $irc = $sender->get_heap();

    is($nick, $irc->nick_name(), 'JOINER Test');
    is($where, '#testchannel', 'Joined Channel Test');
    is($who, $irc->nick_long_form($nick), 'nick_long_form()');

    my $chans = $irc->channels();
    is(keys %$chans, 1, 'Correct number of channels');
    is((keys %$chans)[0], $where, 'Correct channel name');

    my @nicks = $irc->nicks();
    is(@nicks, 1, 'Only one nick known');
    is($nicks[0], $nick, 'Nickname correct');
}

sub join_after_split {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = parse_user($who);
    my $irc = $sender->get_heap();

    is($nick, 'oper', 'oper joined');
    ok(!defined $bot->{NETSPLIT}->{Users}->{'OPER!oper@ircd2.poco.server.irc'}, 'OPER!oper@ircd2.poco.server.irc' );
    ok($irc->is_channel_member($where, $nick), 'Is Channel Member');
    ok(!$irc->is_channel_operator($where, $nick), 'Is Not Channel Operator');
}

sub irc_topic {
    my ($sender, $chan, $topic) = @_[SENDER, ARG1, ARG2];
    my $irc = $sender->get_heap();
    is($topic, $irc->channel_topic($chan)->{Value}, 'Channel topic set');
}

sub irc_chan_sync {
    my ($sender, $heap, $chan) = @_[SENDER, HEAP, ARG0];
    my $irc = $sender->get_heap();
    my ($nick, $user, $host) = parse_user($irc->nick_long_form($irc->nick_name()));
    my ($occupant) = $irc->channel_list($chan);
    
    is($occupant, 'TestBot', 'Channel Occupancy Test');
    ok($irc->channel_creation_time($chan), 'Got channel creation time');
    ok(!$irc->channel_limit($chan), 'There is no channel limit');
    ok(!$irc->is_channel_mode_set($chan, 'i'), 'Channel mode i not set yet');
    ok($irc->is_channel_member($chan, $nick), 'Is Channel Member');
    ok(!$irc->is_channel_operator($chan, $nick), 'Is Not Channel Operator');
    ok(!$irc->is_channel_halfop($chan, $nick), 'Is not channel halfop');
    ok(!$irc->has_channel_voice($chan, $nick), 'Does not have channel voice');
    ok($irc->ban_mask($chan, $nick), 'Ban Mask Test');

    my @channels = $irc->nick_channels($nick);
    is(@channels, 1, 'Only present in one channel');
    is($channels[0], $chan, 'The channel name matches');

    my $info = $irc->nick_info($nick);
    is($info->{Nick}, $nick, 'nick_info() - Nick');
    is($info->{User}, $user, 'nick_info() - User');
    is($info->{Host}, $host, 'nick_info() - Host');
    is($info->{Userhost}, "$user\@$host", 'nick_info() - Userhost');
    is($info->{Hops}, 0, 'nick_info() - Hops');
    is($info->{Real}, 'Test test bot', 'nick_info() - Realname');
    is($info->{Server}, $heap->{server}, 'nick_info() - Server');
    ok(!$info->{IRCop}, 'nick_info() - IRCop');
    
    $ircd2->_daemon_cmd_squit( 'oper', 'ircd1.poco.server.irc' );
}

sub irc_chan_mode {
    my ($sender, $heap, $who, $chan, $mode, $what) = @_[SENDER, HEAP, ARG0..ARG3];
    my $irc = $sender->get_heap();
    return if !$heap->{netjoin};

    ok($irc->is_channel_operator($chan, $what), 'Is Channel Operator');
    $irc->yield('quit');
}

sub irc_user_mode {
    my ($sender, $who, $mode) = @_[SENDER, ARG0, ARG2];
    my $irc = $sender->get_heap();
    
    $mode =~ s/\+//g;
    ok($irc->is_user_mode_set($mode), "User Mode Set: $mode");
    is($irc->umode(), $mode, 'Correct user mode in state');
}

sub irc_mode {
    my $irc = $_[SENDER]->get_heap();
    return if $_[ARG1] !~ /^\#/;
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

 # We registered for all events, this will produce some debug info.
 sub _default {
     my ($event, $args) = @_[ARG0 .. $#_];
     my @output = ( "$event: " );

     for my $arg (@$args) {
         if ( ref $arg eq 'ARRAY' ) {
             push( @output, '[' . join(', ', @$arg ) . ']' );
         }
         else {
             push ( @output, "'$arg'" );
         }
     }
     print join ' ', @output, "\n";
     return 0;
 }

sub ircd_daemon_nick {
  my $nickname = $_[ARG0];
  return unless $nickname eq 'oper';
  $ircd2->yield( daemon_cmd_join => $nickname => '#testchannel' );
  return;
}

sub irc_quit {
  ok(defined $bot->{NETSPLIT}->{Users}->{'OPER!oper@ircd2.poco.server.irc'}, 'OPER!oper@ircd2.poco.server.irc' );
  $poe_kernel->state( 'irc_join', 'main', 'join_after_split' );
  $ircd2->_daemon_cmd_connect( 'oper', 'ircd1.poco.server.irc' );
  $_[HEAP]->{netjoin}=1;
  return;
}
