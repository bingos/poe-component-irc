# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;
use Test::More; 

if ($^O eq "cygwin") {
  plan skip_all => "Cygwin seems to thwart this test.";
}

plan tests => 14;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Filter::Line);
use_ok('POE::Component::IRC');

my $self = POE::Component::IRC->spawn( alias => 'blahblah' );

isa_ok ( $self, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start,
			   accept_client => \&accept_client,
			   oops => \&factory_failed,
			   client_input => \&client_input,
			   client_error => \&client_error,
			   irc_connected => \&irc_connected,
			   irc_socketerr => \&irc_socketerr,
			   irc_registered => \&irc_registered,
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
  undef;
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
  undef;
}

sub factory_failed {
  delete $_[HEAP]->{sockfactory};
  undef;
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
  undef;
}

sub client_error {
    my ( $heap, $wheel_id ) = @_[ HEAP, ARG3 ];
    delete $heap->{client}->{$wheel_id}; 
    delete $heap->{sockfactory};
  undef;
}

sub irc_connected {
  pass('connected');
  undef;
}

sub irc_socketerr {
  fail('connected');
  $self->yield( 'shutdown' );
  undef;
}

sub irc_registered {
  isa_ok( $_[ARG0], 'POE::Component::IRC' );
  undef;
}

sub irc_001 {
  my ($heap,$sender) = @_[HEAP,SENDER];

  pass('irc_001');

  my $poco_object = $sender->get_heap();

  isa_ok( $poco_object, 'POE::Component::IRC' );

  ok( $poco_object->session_id() eq $sender->ID(), "Session ID" );
  ok( $poco_object->session_alias() eq 'blahblah', "Alias name" );
  ok( $poco_object->connected(), "Connected test" );
  ok( $poco_object->server_name() eq 'test.script', "Server Name" );
  ok( $poco_object->nick_name() eq 'testbot', "Nick Name" );

  #$self->yield( 'unregister' => 'all' );
  $self->yield( 'shutdown');
  undef;
}
