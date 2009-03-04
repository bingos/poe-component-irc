use strict;
use warnings;
use lib 't/inc';
use POE::Component::IRC;
use POE::Component::Server::IRC;
use POE qw(Wheel::SocketFactory);
use Socket;
use Test::More tests => 15;

my $bot1 = POE::Component::IRC->spawn(Flood => 1);
my $bot2 = POE::Component::IRC->spawn(Flood => 1);
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
            irc_invite
            irc_mode
            irc_public
            irc_notice
            irc_ctcp_action
            irc_nick
            irc_topic
            irc_kick
            irc_msg
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
        $kernel->delay(_shutdown => 60);
        return;
    }

    $kernel->yield('_shutdown');
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
    $bot2->delay([connect => {
        nick    => 'TestBot2',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    }], 2 );
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');

    $_[HEAP]->{logged_in}++;
    if ($_[HEAP]->{logged_in} == 2) {
        $bot1->yield(join => '#testchannel');
    }
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = ( split /!/, $who )[0];
    my $irc = $sender->get_heap();
    
    if ($nick eq $irc->nick_name()) {
        is($where, '#testchannel', 'Joined Channel Test');

        if ($irc == $bot1) {
            $irc->yield(invite => $bot2->nick_name(), $where);
        }
    }
}

sub irc_invite {
    pass('irc_invite');
    $_[SENDER]->get_heap()->yield(join => $_[ARG1]);
}

sub irc_mode {
    my ($sender, $where, $mode) = @_[SENDER, ARG1, ARG2];
    my $irc = $sender->get_heap();
    return if $where !~ /^[#&!]/;
    return if $irc != $bot1;

    if ($mode =~ /\+[nt]/) {
        $bot1->yield(mode => $where, '+m');
    }
    else {
        is($mode, '+m', 'irc_mode');
        $bot1->yield(privmsg => $where, 'Test message 1');
    }
}

sub irc_public {
    my ($sender, $where, $msg) = @_[SENDER, ARG1, ARG2];
    my $irc = $sender->get_heap();
    return if $irc != $bot2;

    is($msg, 'Test message 1', 'irc_public');
    $bot1->yield(notice => $where->[0], 'Test message 2');
}

sub irc_notice {
    my ($sender, $where, $msg) = @_[SENDER, ARG1, ARG2];
    my $irc = $sender->get_heap();
    return if $irc != $bot2;

    is($msg, 'Test message 2', 'irc_notice');
    $bot1->yield(ctcp => $where->[0], 'ACTION Test message 3');
}

sub irc_ctcp_action {
    my ($sender, $where, $msg) = @_[SENDER, ARG1, ARG2];
    my $irc = $sender->get_heap();
    return if $irc != $bot2;

    is($msg, 'Test message 3', 'irc_ctcp_action');
    $bot1->yield(topic => $where->[0], 'Test topic');
}

sub irc_topic {
    my ($sender, $chan, $msg) = @_[SENDER, ARG1, ARG2];
    my $irc = $sender->get_heap();
    return if $irc != $bot2;

    is($msg, 'Test topic', 'irc_topic');
    $bot1->yield(nick => 'NewNick');
}

sub irc_nick {
    my $irc = $_[SENDER]->get_heap();
    return if $irc != $bot2;
    pass('irc_nick');
    $bot1->yield(kick => '#testchannel', $bot2->nick_name(), 'Good bye');
}

sub irc_kick {
    my ($sender, $reason) = @_[SENDER, ARG3];
    my $irc = $sender->get_heap();
    return if $irc != $bot2;

    is($reason, 'Good bye', 'irc_kick');
    $bot1->yield(privmsg => $bot2->nick_name(), 'Test message 3');
}

sub irc_msg {
    my ($sender, $msg) = @_[SENDER, ARG2];
    my $irc = $sender->get_heap();
    return if $irc != $bot2;

    is($msg, 'Test message 3', 'irc_msg');
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

