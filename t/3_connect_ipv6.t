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

eval {
	require Socket6;
	import Socket6;
};

if ( length($@) or not exists($INC{"Socket6.pm"}) ) {
    plan skip_all => "Socket6 is needed for IPv6 tests";
}

my $addr = Socket6::inet_pton(&Socket6::AF_INET6, "::1");
unless (defined $addr) {
    plan skip_all => "IPv6 tests require a configured localhost address ('::1')";
}

plan tests => 14;

my $debug;

$debug = 1 if $^O eq 'solaris'; # switch on debugging for Solaris

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
	options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  diag("Starting tests: Socket6 appears to be $Socket6::VERSION\n") if $debug;
  pass('blah');
  $heap->{tests} = 11;
  $heap->{sockfactory} = POE::Wheel::SocketFactory->new(
	SocketDomain => AF_INET6,
	BindAddress => '::1',
	BindPort => 0,
	SuccessEvent => 'accept_client',
	FailureEvent => 'oops',
  );

  my $packed_socket = $heap->{sockfactory}->getsockname;
  diag("Couldn't get the packed socket\n") if $debug and !$packed_socket;
  return unless $packed_socket;
  eval {
    ($heap->{bindport}, undef) = unpack_sockaddr_in6( $packed_socket );
  };
  diag("ERROR: $@\n") if $debug and $@;
  return if $@;

  if ( $heap->{bindport} == 0 ) {
    diag('$heap->{bindport} == ' . $heap->{bindport} . "\n");
    SKIP: {
      skip 'AF_INET6 probably not supported $heap->{bindport} == 0', $heap->{tests};
    }
    $heap->{tests} = 0;
    delete $heap->{sockfactory};
    $self->yield( 'shutdown' );
    return;
  }

  diag("Okay connecting to port " . $heap->{bindport} . "\n") if $debug;

  $self->yield( 'register' => 'all' );
  $self->yield( 'connect' => { Nick => 'testbot',
			       Server => '::1',
			       useipv6 => 1,
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
  my ($heap,$syscall, $errno, $error) = @_[HEAP,ARG0..ARG2];
  diag("Tests left: " . $heap->{tests} . "\n") if $debug;
  diag("Factory failed: $syscall error $errno: $error\n") if $debug;
  delete $_[HEAP]->{sockfactory};
  return unless $heap->{tests};
  SKIP: {
    skip "AF_INET6 probably not supported ($syscall error $errno: $error)", $heap->{tests};
  }
  $heap->{tests} = 0;
  $self->yield( 'shutdown' );
  undef;
}

sub client_input {
  my ( $heap, $input, $wheel_id ) = @_[ HEAP, ARG0, ARG1 ];

  SWITCH: {
    if ( $input =~ /^NICK / ) {
	pass('nick');
	$heap->{tests}--;
	$heap->{got_nick} = 1;
	last SWITCH;
    }
    if ( $input =~ /^USER / ) {
	pass('user');
	$heap->{tests}--;
	$heap->{got_user} = 1;
	last SWITCH;
    }
    if ( $input =~ /^QUIT/ ) {
	delete $heap->{client}->{ $wheel_id };
    	delete $heap->{sockfactory};
	return;
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
    diag("Client Error\n") if $debug;
  undef;
}

sub irc_connected {
  $_[HEAP]->{tests}--;
  pass('connected');
  undef;
}

sub irc_socketerr {
  diag("irc_socketerr $_[ARG0]\n") if $debug;
  diag("Tests left: " . $_[HEAP]->{tests} . "\n") if $debug;
  return unless $_[HEAP]->{tests};
  SKIP: {
    skip "AF_INET6 probably not supported ($_[ARG0])", $_[HEAP]->{tests};
  }
  $self->yield( 'shutdown' );
  undef;
}

sub irc_registered {
  $_[HEAP]->{tests}--;
  isa_ok( $_[ARG0], 'POE::Component::IRC' );
  undef;
}

sub irc_001 {
  my ($heap,$sender) = @_[HEAP,SENDER];

  $heap->{tests}--;
  pass('irc_001');

  my $poco_object = $sender->get_heap();

  isa_ok( $poco_object, 'POE::Component::IRC' );

  ok( $poco_object->session_id() eq $sender->ID(), "Session ID" );
  $heap->{tests}--;
  ok( $poco_object->session_alias() eq 'blahblah', "Alias name" );
  $heap->{tests}--;
  ok( $poco_object->connected(), "Connected test" );
  $heap->{tests}--;
  ok( $poco_object->server_name() eq 'test.script', "Server Name" );
  $heap->{tests}--;
  ok( $poco_object->nick_name() eq 'testbot', "Nick Name" );
  $heap->{tests}--;

  #$self->yield( 'unregister' => 'all' );
  $self->yield( 'shutdown');
  undef;
}
