use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Test::Harness;
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

my $irc = SubclassIRC->spawn();
my $ircd = POE::Component::IRC::Test::Harness->spawn(
    Alias => 'ircd',
    Auth => 0,
    AntiFlood => 0,
);

isa_ok($irc, 'POE::Component::IRC');
isa_ok($ircd, 'POE::Component::IRC::Test::Harness');

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
        $wheel = undef;
        $kernel->delay(_shutdown => 60);
        return;
    }
    
    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $kernel->post(ircd => 'shutdown');
    $irc->yield('shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];
    $kernel->post(ircd => 'add_i_line');
    $kernel->post(ircd => add_listener => { Port => $port });
    $irc->yield(register => 'all');
    $irc->yield( connect => {
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
