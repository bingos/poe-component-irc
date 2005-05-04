# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

warn "\n***************************\nThese next tests will hang if you are firewalling localhost interfaces\n";

use Test::More tests => 7;
BEGIN { use_ok('POE::Component::IRC') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Filter::Line);

my ($self) = POE::Component::IRC->spawn( dccports => '1024,1048-1098,abc' );

isa_ok ( $self, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start,
			   accept_client => \&accept_client,
			   oops => \&factory_failed,
			   client_input => \&client_input,
			   client_error => \&client_error,
			   irc_connected => \&irc_connected,
			   irc_socketerr => \&irc_socketerr,
			   irc_001 => \&irc_001,
			 },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  pass('blah');
  $heap->{sockfactory} = POE::Wheel::SocketFactory->new(
	BindAddress => '127.0.0.1',
	BindPort => 0,
	SuccessEvent => 'accept_client',
	FailureEvent => 'oops',
  );

  ($heap->{bindport}, undef) = unpack_sockaddr_in( $heap->{sockfactory}->getsockname );

  $heap->{filter} = POE::Filter::IRC->new();

  $self->yield( 'register' => 'all' );
  $self->yield( 'connect' => { Nick => 'testbot',
			       Server => '127.0.0.1',
			       Port => $heap->{bindport},
			       Username => 'testbot',
			       Ircname => 'testbot 1.1', } );
}

sub accept_client {
  my ($kernel,$heap, $socket) = @_[KERNEL,HEAP,ARG0];

  my $wheel = POE::Wheel::ReadWrite->new
      ( Handle => $socket,
        InputEvent => "client_input",
        ErrorEvent => "client_error",
        Filter => POE::Filter::Line->new( Literal => "\x0D\x0A" ),
   );
   $heap->{client}->{ $wheel->ID() } = $wheel;
}

sub factory_failed {
  delete ( $_[HEAP]->{sockfactory} );
}

sub client_input {
  my ( $heap, $input, $wheel_id ) = @_[ HEAP, ARG0, ARG1 ];

  SWITCH: {
    if ( $input =~ /^NICK / ) {
	pass('nick');
	$heap->{got_nick} = 1;
	last SWITCH;
    }
    if ( $input =~ /^USER / ) {
	pass('user');
	$heap->{got_user} = 1;
	last SWITCH;
    }
  }
  if ( $heap->{got_nick} and $heap->{got_user} ) {
	# Send back irc_001
	$heap->{client}->{ $wheel_id }->put(':test.script 001 testbot :Welcome to poconet Internet Relay Chat Network testbot!testbot@127.0.0.1');
  }
}

sub client_error {
    my ( $heap, $wheel_id ) = @_[ HEAP, ARG3 ];
    delete ( $heap->{client}->{$wheel_id} ); 
    delete ( $heap->{sockfactory} );
}

sub irc_connected {
  pass('connected');
}

sub irc_socketerr {
  fail('connected');
  $self->yield( 'shutdown' );
}

sub irc_001 {
  my ($heap) = $_[HEAP];

  pass('irc_001');

  $self->yield( 'unregister' => 'all' );
  $self->yield( 'shutdown');
}
