use strict;
use warnings FATAL => 'all';
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use Socket;
use POE::Component::IRC;
use POE::Component::Server::IRC;
use Test::More tests => 13;
use Data::Dumper;

my $bot1 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $bot2 = POE::Component::IRC->spawn(
    Flood        => 1,
    plugin_debug => 1,
);
my $ircd = POE::Component::Server::IRC->spawn(
    Auth      => 0,
    AntiFlood => 0,
);

my $space_file = 'dcc with spaces';
open my $handle, '>', $space_file, or die "Couldn't open '$space_file': $!";
syswrite $handle, "One\nTwo\nThree\n";

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001 
            irc_join
            irc_disconnected
            irc_dcc_request
            irc_dcc_done
            irc_dcc_start
            irc_dcc_error
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
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
    $irc->yield(join => '#testchannel');
}

sub irc_join {
    my ($heap, $sender, $who, $where) = @_[HEAP, SENDER, ARG0, ARG1];
    my $nick = ( split /!/, $who )[0];
    my $irc = $sender->get_heap();
    
    return if $nick ne $irc->nick_name();
    is($where, '#testchannel', 'Joined Channel Test');

    $heap->{joined}++;
    return if $heap->{joined} != 2;
    $bot1->yield(dcc => $bot2->nick_name() => SEND => $space_file => 1024 => 5);
}

sub irc_dcc_request {
    my ($sender, $cookie) = @_[SENDER, ARG3];
    pass("Got dcc request");
    $sender->get_heap()->yield(dcc_accept => $cookie => "$space_file.send");
}

sub irc_dcc_start {
    pass('DCC started');
}

sub irc_dcc_done {
    my ($sender, $size1, $size2) = @_[SENDER, ARG5, ARG6];
    pass('Got dcc close');
    is($size1, $size2, 'Send test results');
    $sender->get_heap()->yield('quit');
}

sub irc_dcc_error {
    my ($sender, $error) = @_[SENDER, ARG1];
    my $irc = $sender->get_heap();
    fail('('. $irc->nick_name() .") DCC failed: $error");
    $irc->yield('quit');
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;

    if ($heap->{count} == 2) {
        $kernel->yield('_shutdown');
        unlink $space_file, "$space_file.send";
    }
}

sub _shutdown {
    my ($kernel, $error) = @_[KERNEL, ARG0];
    fail($error) if defined $error;
    
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $bot1->yield('shutdown');
    $bot2->yield('shutdown');
}

