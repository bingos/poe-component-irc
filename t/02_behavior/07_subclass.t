use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 17;

{
    package SubclassIRC;
    use base qw(POE::Component::IRC);
    use Test::More;
    my $VERSION = 1;

    sub S_001 {
        my ($irc1, $irc2) = splice @_, 0, 2;
        pass('PoCo-IRC as subclass');
        isa_ok($irc1, 'POE::Component::IRC');
        isa_ok($irc2, 'POE::Component::IRC');
        is($irc1->server_name(), 'poco.server.irc', 'Server Name Test');
        is($irc2->nick_name(), 'TestBot', 'Nick Name Test');
    }
}

my $bot = SubclassIRC->spawn(Flood => 1);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

isa_ok($bot, 'POE::Component::IRC');
isa_ok($ircd, 'POE::Component::Server::IRC');

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_registered 
            irc_connected 
            irc_001 
            irc_whois 
            irc_join
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
        $kernel->delay(_shutdown => 60, 'Timed out');
        return;
    }
    
    $kernel->yield('_shutdown', "Couldn't bind to an unused port on localhost");
}

sub _shutdown {
    my ($kernel, $reason) = @_[KERNEL, ARG0];
    fail($reason) if defined $reason;
    
    $kernel->alarm_remove_all();
    $bot->yield('shutdown');
    $ircd->yield('shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];

    $ircd->yield(add_listener => Port => $port);

    $bot->yield(register => 'all');
    $bot->yield( connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_registered {
    my ($irc) = $_[ARG0];
    isa_ok($irc, 'POE::Component::IRC');
}

sub irc_connected {
    pass('Connected');
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('connect');
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
    $irc->yield('quit');
}

sub irc_error {
    pass('irc_error');
}

sub irc_disconnected {
    my ($kernel) = $_[KERNEL];
    pass('irc_disconnected');
    $kernel->yield('_shutdown');
}
