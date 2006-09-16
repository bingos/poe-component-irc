use Test::More tests => 3;
BEGIN { use_ok('POE::Component::IRC') };
use POE;

my $irc = POE::Component::IRC->spawn();

POE::Session->create(
	inline_states => { _start => \&test_start, irc_registered => \&registered },
	options => { trace => 0 },
	heap => { irc => $irc },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $heap->{irc}->yield( register => 'all' );
  undef;
}

sub registered {
  my ($kernel,$heap,$sender,$poco) = @_[KERNEL,HEAP,SENDER,ARG0];
  pass('Child registered us');
  isa_ok( $poco, 'POE::Component::IRC' );
  #$kernel->post( $sender, 'shutdown' );
  $kernel->post( $sender => unregister => 'mode' );
  warn "Waiting 5 seconds for 'unregister'\n";
  $heap->{irc}->delay( [ 'shutdown' ], 5 );
  undef;
}
