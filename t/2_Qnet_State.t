# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('POE::Component::IRC::Qnet::State') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

#warn "\nThese next tests will hang if you are firewalling localhost interfaces";

#use POE qw(Wheel::SocketFactory Wheel::ReadWrite Filter::Line);
use POE;

my ($self) = POE::Component::IRC::Qnet::State->new('irc-client');

isa_ok ( $self, 'POE::Component::IRC::Qnet::State' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  pass('blah');
  $kernel->post( $self->session_id() => 'shutdown' );
}
