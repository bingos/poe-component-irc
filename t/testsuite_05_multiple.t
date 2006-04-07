use Test::More tests => 20;

BEGIN { use_ok('POE::Component::IRC::Test::Harness') };
BEGIN { use_ok('POE::Component::IRC') };

use POE qw(Wheel::SocketFactory);
use Socket;

my $ircd = POE::Component::IRC::Test::Harness->spawn( Alias => 'ircd', Auth => 0, AntiFlood => 0, Debug => 0 );
my $irc = POE::Component::IRC->spawn( options => { trace => 0 } );
my $irc2 = POE::Component::IRC->spawn( options => { trace => 0 } );

isa_ok ( $ircd, 'POE::Component::IRC::Test::Harness' );
isa_ok ( $irc, 'POE::Component::IRC' );
isa_ok ( $irc2, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	   'main' => [qw(_config_ircd 
			 _shutdown 
			 irc_registered 
			 irc_connected 
			 irc_001 
			 irc_join
			 irc_public
			 irc_error
			 irc_disconnected
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
	$heap->{count} = 0;
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
  $kernel->post( 'ircd' => 'shutdown' );
  $irc->yield( 'unregister' => 'all' );
  $irc->yield( 'shutdown' );
  $irc2->yield( 'unregister' => 'all' );
  $irc2->yield( 'shutdown' );
  undef;
}

sub _config_ircd {
  my ($kernel,$heap,$port) = @_[KERNEL,HEAP,ARG0];
  $kernel->post ( 'ircd' => 'add_i_line' );
  $kernel->post ( 'ircd' => 'add_listener' => { Port => $port } );
  $irc->yield( 'register' => 'all' );
  $irc->yield( connect => { nick => 'TestBot1',
        server => '127.0.0.1',
        port => $port,
        ircname => 'Test test bot',
  } );
  $irc2->yield( 'register' => 'all' );
  $irc2->yield( connect => { nick => 'TestBot2',
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

sub irc_connected {
  pass( "Connected" );
  undef;
}

sub irc_001 {
  my ($kernel,$sender,$text) = @_[KERNEL,SENDER,ARG1];
  my $ircobj = $sender->get_heap();
  pass( 'connect' );
  ok( $ircobj->server_name() eq 'poco.server.irc', "Server Name Test" );
  $ircobj->yield( 'join' => '#testchannel' );
  undef;
}

sub irc_join {
  my ($kernel,$sender,$who,$where) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $nick = ( split /!/, $who )[0];
  my $object = $sender->get_heap();
  if ( $nick eq $object->nick_name() ) {
     ok( $where eq '#testchannel', "Joined Channel Test" );
  } else {
     $object->yield( 'privmsg' => $where => 'HELLO' );
     $object->yield( 'quit' );
  }
  undef;
}

sub irc_public {
  my ($kernel,$sender,$who,$where,$what) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
  my $nick = ( split /!/, $who )[0];
  my $object = $sender->get_heap();
  ok( $what eq 'HELLO', "irc_public test" );
  $object->yield( 'quit' );
  undef;
}

sub irc_error {
  pass( "irc_error" );
  undef;
}

sub irc_disconnected {
  my $heap = $_[HEAP];
  pass( "irc_disconnected" );
  $heap->{count}++;
  $poe_kernel->yield( '_shutdown' ) unless $heap->{count} < 2;
  undef;
}
