use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile);
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::Logger;
use POE::Component::Server::IRC;
use Socket;
use Test::More;

my $log_dir = tempdir(CLEANUP => 1);

my $bot1 = POE::Component::IRC::State->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $bot2 = POE::Component::IRC::State->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

$bot2->plugin_add(Logger => POE::Component::IRC::Plugin::Logger->new(
    Path => $log_dir,
));

my $file = catfile($log_dir, '=testbot1.log');
unlink $file if -e $file;

my @correct = (
    qr/^--> Opened DCC chat connection with TestBot1 \(\S+:\d+\)$/,
    '<TestBot1> Oh hi',
    '* TestBot1 does something',
    '<TestBot2> Hi yourself',
    '* TestBot2 does something as well',
    qr/^<-- Closed DCC chat connection with TestBot1 \(\S+:\d+\)$/,
);

plan tests => 7 + @correct;

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd
            _shutdown
            irc_001
            irc_dcc_request
            irc_dcc_start
            irc_dcc_chat
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
    my ($heap, $server) = @_[HEAP, ARG0];
    my $irc = $_[SENDER]->get_heap();

    pass($irc->nick_name() . ' logged in');
    $heap->{logged_in}++;
    return if $heap->{logged_in} != 2;
    $bot2->yield(dcc => $bot1->nick_name() => CHAT => undef, undef, 5);
}

sub irc_dcc_request {
    my ($sender, $cookie) = @_[SENDER, ARG3];
    my $irc = $sender->get_heap();
    pass($irc->nick_name() . ' got dcc request');
    $irc->yield(dcc_accept => $cookie);
}

sub irc_dcc_start {
    my ($sender, $heap, $id) = @_[SENDER, HEAP, ARG0];
    my $irc = $sender->get_heap();
    pass($irc->nick_name() . ' got irc_dcc_started');

    $heap->{started}++;
    if ($heap->{started} == 2) {
        $irc->yield(dcc_chat => $id, 'Oh hi');
        $irc->yield(dcc_chat => $id, "\001ACTION does something\001");
    }
}

sub irc_dcc_chat {
    my ($heap, $sender, $id, $msg) = @_[HEAP, SENDER, ARG0, ARG3];
    my $irc = $sender->get_heap();

    $heap->{msgs}++;
    if ($heap->{msgs} == 2) {
        $irc->yield(dcc_chat => $id, 'Hi yourself');
        $irc->yield(dcc_chat => $id, "\001ACTION does something as well\001");
    }
    elsif ($heap->{msgs} == 4) {
        $irc->yield(dcc_close => $id);
        $bot1->yield('quit');
        $bot2->yield('quit');
    }
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;

    if ($heap->{count} == 2) {
        verify_log();
        $kernel->yield('_shutdown');
    }
}

sub verify_log {
    open my $log, '<', $file or die "Can't open log file '$file': $!";
    my @lines = <$log>;
    close $log;

    my $check = 0;
    for my $line (@lines) {
        next if $line =~ /^\*{3}/;
        chomp $line;
        $line = substr($line, 20);
        last if !defined $correct[$check];

        if (ref $correct[$check] eq 'Regexp') {
            like($line, $correct[$check], 'Line ' . ($check+1));
        }
        else {
            is($line, $correct[$check], 'Line ' . ($check+1));
        }
        $check++;
    }
    fail('Log too short') if $check > @correct;
}
