use Test::More tests => 7;

BEGIN { use_ok('POE::Component::IRC') };

use POE qw(Wheel::SocketFactory);
use Socket;
use Data::Dumper;

my $dns = POE::Component::Client::DNS->spawn( Alias => 'foo' );
my $irc = POE::Component::IRC->spawn( options => { trace => 0 }, NoDNS => 1 );

my $server = 'irc.freenode.net';
my $nick = "PoCoIRC" . $$;

isa_ok ( $irc, 'POE::Component::IRC' );

POE::Session->create(
	package_states => [
	   'main' => [qw(_start
			 _got_dns_response
			 _shutdown 
			 _success
			 _failure
			 _do_connect
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
	options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub _start {
  my $response = $dns->resolve( event => "_got_dns_response", host =>  $server, context => { } );
  $poe_kernel->yield( '_got_dns_response' => $response ) if $response;
  undef;
}

sub _got_dns_response {
  my $net_dns_packet = $_[ARG0]->{response};
  my $net_dns_errorstring = $_[ARG0]->{error};

  unless(defined $net_dns_packet) {
    $poe_kernel->yield('_shutdown' => $net_dns_errorstring );
    return;
  }

  my @net_dns_answers = $net_dns_packet->answer;

  unless (@net_dns_answers) {
    $poe_kernel->yield('_shutdown' => "Unable to resolve $server" );
    return;
  }

  foreach my $net_dns_answer (@net_dns_answers) {
    next unless $net_dns_answer->type eq "A";
    $poe_kernel->yield('_do_connect' => $net_dns_answer->rdatastr );
    return;
  }

  $poe_kernel->yield('_shutdown' => "Unable to resolve $server" );
  undef;
}

sub _do_connect {
  my ($kernel,$heap,$address) = @_[KERNEL,HEAP,ARG0];
  $heap->{address} = $address;
  $heap->{sockfactory} = 
  POE::Wheel::SocketFactory->new(   SocketDomain   => AF_INET,
				    SocketType     => SOCK_STREAM,
				    SocketProtocol => 'tcp',
				    RemoteAddress  => $address,
				    RemotePort     => 6667,
				    SuccessEvent   => '_success',
				    FailureEvent   => '_failure',
				  );
  $kernel->delay( '_time_out' => 40 );
  undef;
}

sub _success {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $kernel->delay( '_time_out' );
  delete $heap->{sockfactory};
  $kernel->delay( '_irc_connect' => 5 );
  undef;
}

sub _failure {
  my ($kernel,$heap,$operation,$errnum,$errstr) = @_[KERNEL,HEAP,ARG0..ARG2];
  delete $heap->{sockfactory};
  $kernel->yield('_shutdown' => "$operation $errnum $errstr" );
  undef;
}

sub _time_out {
  delete $_[HEAP]->{sockfactory};
  $poe_kernel->yield( '_shutdown' => 'Connection timed out' );
  undef;
}

sub _irc_connect {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $irc->yield( 'register' => 'all' );
  $irc->yield( 'connect' => { server => $heap->{address}, nick => $nick } );
  undef;
}

sub _shutdown {
  my $skip = $_[ARG0];
  SKIP: {
    skip "$skip", 5 if $skip;
  }
  $poe_kernel->alarm_remove_all();
  $irc->yield( 'unregister' => 'all' );
  $irc->yield( 'shutdown' );
  $dns->shutdown();
  undef;
}

sub irc_registered {
  my ($kernel,$object) = @_[KERNEL,ARG0];
  isa_ok( $object, 'POE::Component::IRC' );
  undef;
}

sub irc_connected {
  pass( "Connected" );
  undef;
}

sub irc_socketerr {
  $poe_kernel->yield( '_shutdown' => $_[ARG0] );
  undef;
}

sub irc_001 {
  my ($kernel,$sender,$text) = @_[KERNEL,SENDER,ARG1];
  my $ircobj = $sender->get_heap();
  pass( 'connect' );
  warn "# Connected to ", $ircobj->server_name(), "\n";
  $ircobj->yield( 'quit' );
  undef;
}

sub irc_error {
  pass( "irc_error" );
  undef;
}

sub irc_disconnected {
  pass( "irc_disconnected" );
  $poe_kernel->yield( '_shutdown' );
  undef;
}
