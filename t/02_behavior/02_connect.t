use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 38;

my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

my $bot = POE::Component::IRC->spawn();

isa_ok($ircd, 'POE::Component::Server::IRC');
isa_ok($bot, 'POE::Component::IRC');

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            _default
            irc_connected 
            irc_001 
            irc_391
            irc_whois 
            irc_join
            irc_isupport
            irc_error
            irc_disconnected
            irc_shutdown
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel) = $_[KERNEL];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress => '127.0.0.1',
        BindPort => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port );
        $wheel = undef;
        $kernel->delay(_shutdown => 60 );
        return;
    }
    
    $kernel->yield('_shutdown');
}

sub _config_ircd {
    my ($kernel, $heap, $port) = @_[KERNEL, HEAP, ARG0];
    $ircd->yield('add_i_line');
    $ircd->yield(add_listener => Port => $port);

    $bot->yield(register => 'all');
    $bot->yield( connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_connected {
    pass('Connected');
}

sub irc_001 {
    my ($sender) = $_[SENDER];
    my $irc = $sender->get_heap();
    pass('Logged in');
    
    is($irc->server_name(), 'poco.server.irc', 'Server Name Test');
    is($irc->nick_name(), 'TestBot', 'Nick Name Test');
    is($irc->session_alias(), $irc, 'Alias Test');
    
    $irc->yield('time');
    $irc->yield(whois => 'TestBot');
}

sub irc_isupport {
    my $isupport = $_[ARG0];
    isa_ok($isupport, 'POE::Component::IRC::Plugin::ISupport');
    
    is($isupport->isupport('NETWORK'), 'poconet', 'ISupport Network');
    is($isupport->isupport('CASEMAPPING'), 'rfc1459', 'ISupport Casemapping');
    
    for my $isupp ( qw(MAXCHANNELS MAXBANS MAXTARGETS NICKLEN
        TOPICLEN KICKLEN CHANTYPES PREFIX CHANMODES) ) {
        ok($isupport->isupport($isupp), "Testing $isupp");
    }
}

# RPL_TIME
sub irc_391 {
    my ($time) = $_[ARG1];
    pass('Got the time, baby');
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
    pass('Got irc_error');
}

sub irc_shutdown {
    pass('Got irc_shutdown');
}

sub irc_disconnected {
    pass('Got irc_disconnected');
    $poe_kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot->yield('shutdown');
}

sub _default {
    my ($event) = $_[ARG0];
    return 0 if $event !~ /^irc_(002|003|004|422|251|255|311|312|317|318|353|366)$/;
    pass("Got $event");
    return 0;
}
