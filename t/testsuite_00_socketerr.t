use Test::More tests => 4;

BEGIN { use_ok('POE::Component::IRC') };

use POE qw(Wheel::SocketFactory);
use Socket;

my $irc = POE::Component::IRC->spawn( options => { trace => 0 } );

isa_ok ( $irc, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	   'main' => [qw(_config_ircd 
			 _shutdown 
			 irc_registered 
			 irc_socketerr
	   )],
	],
	options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  my $wheel = POE::Wheel::SocketFactory->new(
	BindAddress => '127.0.0.1',
	BindPort => 0,
	SuccessEvent => '_fake_success',
	FailureEvent => '_fake_failure',
  );

  if ( $wheel ) {
	my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
	$kernel->yield( '_config_ircd' => $port );
	$wheel = undef;
	$kernel->delay( '_shutdown' => 60 );
	return;
  }
  $kernel->yield('_shutdown');
  undef;
}

sub _shutdown {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $kernel->alarm_remove_all();
  $irc->yield( 'unregister' => 'all' );
  $irc->yield( 'shutdown' );
  undef;
}

sub _config_ircd {
  my ($kernel,$heap,$port) = @_[KERNEL,HEAP,ARG0];
  $irc->yield( 'register' => 'all' );
  $irc->yield( connect => { nick => 'TestBot',
        server => '127.0.0.1',
        port => $port,
        ircname => 'Test test bot',
  } );
  undef;
}

sub irc_registered {
  my ($kernel,$object) = @_[KERNEL,ARG0];
  isa_ok( $object, 'POE::Component::IRC' );
  undef;
}

sub irc_socketerr {
  pass( "Socket Error" );
  $poe_kernel->yield( '_shutdown' );
  undef;
}
