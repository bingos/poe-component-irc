use Test::More tests => 5;
BEGIN { use_ok('POE::Component::IRC') };
use POE;

POE::Session->create(
	inline_states => { _start => \&test_start, irc_registered => \&registered },
	options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $heap->{irc} = POE::Component::IRC->spawn();
  undef;
}

sub registered {
  my ($kernel,$heap,$sender,$poco) = @_[KERNEL,HEAP,SENDER,ARG0];
  pass('Child registered us');
  isa_ok( $poco, 'POE::Component::IRC' );
  $kernel->state( 'irc_registered', \&registered_again );
  $kernel->post( $sender, 'register', 'all' );
  undef;
}

sub registered_again {
  my ($kernel,$heap,$sender,$poco) = @_[KERNEL,HEAP,SENDER,ARG0];
  pass('Child registered us');
  isa_ok( $poco, 'POE::Component::IRC' );
  $kernel->post( $sender, 'shutdown' );
  undef;
}
