use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use File::Spec::Functions qw(catfile);
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::Logger;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 12;

my $bot1 = POE::Component::IRC::State->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

my $got = 0;
$bot1->plugin_add(Logger => POE::Component::IRC::Plugin::Logger->new(
    Log_sub => sub {
        $got++;
        if ($got == 1) {
            is($_[0], '#testchannel', 'Got context');
            is($_[1], 'join', 'Got type');
            is($_[2], 'TestBot1', 'Got arguments');
        }
        elsif ($got == 2) {
            is($_[0], '#testchannel', 'Got context');
            is($_[1], '+n', 'Got type');
            is($_[2], 'poco.server.irc', 'Got arguments');
        }
        elsif ($got == 3) {
            is($_[0], '#testchannel', 'Got context');
            is($_[1], '+t', 'Got type');
            is($_[2], 'poco.server.irc', 'Got arguments');
        }
        elsif ($got == 4) {
            is($_[0], '#testchannel', 'Got context');
            is($_[1], 'quit', 'Got type');
            is($_[2], 'TestBot1', 'Got arguments');
        }
    }
));

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd
            _shutdown
            irc_001
            irc_join
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
}

sub irc_001 {
    my ($heap, $server) = @_[HEAP, ARG0];
    my $irc = $_[SENDER]->get_heap();
    pass($irc->nick_name() . ' logged in');
    $irc->yield(join => '#testchannel');
}

sub irc_join {
    my ($sender, $heap, $who, $where) = @_[SENDER, HEAP, ARG0, ARG1];
    my $nick = (split /!/, $who)[0];
    my $irc = $sender->get_heap();

    return if $nick ne $irc->nick_name();
    pass("$nick joined channel");
    $bot1->yield('quit');
}

sub irc_disconnected {
    my ($kernel, $sender) = @_[KERNEL, SENDER];
    my $irc = $sender->get_heap();
    pass('irc_disconnected');
    $kernel->yield('_shutdown');
}
