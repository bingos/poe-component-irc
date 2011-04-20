use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket qw(unpack_sockaddr_in);
use POE::Component::IRC;
use POE::Component::IRC::Plugin::CTCP;
use POE::Component::Server::IRC;
use Test::More tests => 8;

my $bot = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

$bot->plugin_add(CTCP => POE::Component::IRC::Plugin::CTCP->new(
    version    => 'Test version',
    userinfo   => 'Test userinfo',
    clientinfo => 'Test clientinfo',
    source     => 'Test source',
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd
            _shutdown
            irc_001
            irc_disconnected
            irc_ctcpreply_version
            irc_ctcpreply_userinfo
            irc_ctcpreply_clientinfo
            irc_ctcpreply_source
            irc_ctcpreply_ping
            irc_ctcpreply_time
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

    $bot->yield(register => 'all');
    $bot->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
    $irc->yield(ctcp => $irc->nick_name(), 'VERSION');
    $irc->yield(ctcp => $irc->nick_name(), 'USERINFO');
    $irc->yield(ctcp => $irc->nick_name(), 'CLIENTINFO');
    $irc->yield(ctcp => $irc->nick_name(), 'SOURCE');
    $irc->yield(ctcp => $irc->nick_name(), 'PING test');
    $irc->yield(ctcp => $irc->nick_name(), 'TIME');
}

sub irc_ctcpreply_version {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    $heap->{replies}++;
    is($msg, 'Test version', 'CTCP VERSION reply');
    $sender->get_heap()->yield('quit') if $heap->{replies} == 6;
}

sub irc_ctcpreply_userinfo {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    $heap->{replies}++;
    is($msg, 'Test userinfo', 'CTCP USERINFO reply');
    $sender->get_heap()->yield('quit') if $heap->{replies} == 6;
}

sub irc_ctcpreply_clientinfo {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    $heap->{replies}++;
    is($msg, 'Test clientinfo', 'CTCP CLIENTINFO reply');
    $sender->get_heap()->yield('quit') if $heap->{replies} == 6;
}

sub irc_ctcpreply_source {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    $heap->{replies}++;
    is($msg, 'Test source', 'CTCP SOURCE reply');
    $sender->get_heap()->yield('quit') if $heap->{replies} == 6;
}

sub irc_ctcpreply_ping {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    $heap->{replies}++;
    is($msg, 'test', 'CTCP PING reply');
    $sender->get_heap()->yield('quit') if $heap->{replies} == 6;
}

sub irc_ctcpreply_time {
    my ($sender, $heap, $msg) = @_[SENDER, HEAP, ARG2];
    $heap->{replies}++;
    ok(length $msg, 'CTCP TIME reply');
    $sender->get_heap()->yield('quit') if $heap->{replies} == 6;
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel, $error) = @_[KERNEL, ARG0];
    fail($error) if defined $error;

    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot->yield('shutdown');
}

