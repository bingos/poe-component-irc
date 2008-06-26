use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use Socket;
use Test::More tests => 5;

my $irc = POE::Component::IRC->spawn();
my $server = 'irc.freenode.net';
my $nick = "PoCoIRC" . $$;

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _shutdown 
            _success
            _failure
            _irc_connect
            _time_out
            irc_registered 
            irc_connected 
            irc_001 
            irc_error
            irc_socketerr
            irc_disconnected
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    
    # Connect manually first to see if our internets are working.
    # If not, we can pass the error info to Test::More's skip()
    $heap->{sockfactory} = POE::Wheel::SocketFactory->new(
        SocketDomain   => AF_INET,
        SocketType     => SOCK_STREAM,
        SocketProtocol => 'tcp',
        RemoteAddress  => $server,
        RemotePort     => 6667,
        SuccessEvent   => '_success',
        FailureEvent   => '_failure',
    );
    
    $kernel->delay(_time_out => 40);
}

sub _success {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    $heap->{address} = inet_ntoa($_[ARG1]);

    $kernel->delay('_time_out');
    delete $heap->{sockfactory};
    $kernel->yield(_irc_connect => 5);
}

sub _failure {
    my ($kernel, $heap, $operation, $errnum, $errstr)
        = @_[KERNEL, HEAP, ARG0..ARG2];
    
    delete $heap->{sockfactory};
    $kernel->yield(_shutdown => "$operation $errnum $errstr");
}

sub _time_out {
    delete $_[HEAP]->{sockfactory};
    $poe_kernel->yield(_shutdown => 'Connection timed out');
}

sub _shutdown {
    my $skip = $_[ARG0];
    SKIP: {
        skip $skip, 5 if $skip;
    }
    $poe_kernel->alarm_remove_all();
    $irc->yield('shutdown');
}

sub _irc_connect {
    my ($heap) = $_[HEAP];
    $irc->yield(register => 'all');
    $irc->yield(connect => {
        server => $heap->{address},
        nick => $nick,
    });
}

sub irc_registered {
    my ($irc) = $_[ARG0];
    isa_ok($irc, 'POE::Component::IRC');
}

sub irc_connected {
    pass('Connected');
}

sub irc_socketerr {
    my ($kernel) = $_[KERNEL];
    $kernel->yield(_shutdown => $_[ARG0] );
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
    $irc->yield('quit');
}

sub irc_error {
    pass('irc_error');
}

sub irc_disconnected {
    my ($kernel) = $_[KERNEL];
    pass('Disconnected');
    $kernel->yield('_shutdown');
}
