use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::NickReclaim;
use POE::Component::Server::IRC;
use Test::More tests => 9;

my $bot1 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
    alias        => 'bot1',
);
my $bot2 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
    alias        => 'bot2',
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

$bot2->plugin_add(NickReclaim => POE::Component::IRC::Plugin::NickReclaim->new(
    poll => 65,     # longer than the test timeout
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd
            _shutdown
            irc_001
            irc_433
            irc_join
            irc_nick
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
    my ($kernel, $heap, $port) = @_[KERNEL, HEAP, ARG0];
    $heap->{port} = $port;

    $ircd->yield(add_listener => Port => $port);

    $bot1->yield(register => 'all');
    $bot1->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass($irc->session_alias() . ' (nick=' . $irc->nick_name() .') logged in');
    $irc->yield(join => '#testchannel');
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = ( split /!/, $who )[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    pass($irc->session_alias().' (nick='.$irc->nick_name().") joined $where");

    if ($irc == $bot1) {
        $bot2->yield(register => 'all');
        $bot2->yield(connect => {
            nick    => 'TestBot1',
            server  => '127.0.0.1',
            port    => $_[HEAP]->{port},
        });
    }
    else {
        $bot1->yield(nick => 'TestBot2');
    }
}

sub irc_433 {
    my $irc = $_[SENDER]->get_heap();
    pass($irc->session_alias . ' (nick=' . $irc->nick_name() .') nick collision');
}

sub irc_nick {
    my ($sender, $new_nick) = @_[SENDER, ARG1];
    my $irc = $sender->get_heap();

    if ($irc == $bot1 && $new_nick eq 'TestBot2') {
        pass($irc->session_alias().' (nick='.$irc->nick_name().') changed nicks');
    }
    elsif ($irc == $bot2 && $new_nick eq 'TestBot1') {
        pass($irc->session_alias().' (nick='.$irc->nick_name().') reclaimed nick');
        $bot1->yield('quit');
        $bot2->yield('quit');
    }
}

sub irc_disconnected {
    my ($kernel, $sender, $heap) = @_[KERNEL, SENDER, HEAP];
    my $irc = $sender->get_heap();

    pass($irc->session_alias . ' (nick=' . $irc->nick_name() .') disconnected');
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

