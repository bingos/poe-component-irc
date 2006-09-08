use Test::More tests => 3;
BEGIN { use_ok('POE::Component::IRC::Test::Harness') };
use POE;

my $self = POE::Component::IRC::Test::Harness->spawn( Alias => 'ircd', Auth => 1 );

isa_ok ( $self, 'POE::Component::IRC::Test::Harness' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  pass('blah');
  $kernel->post( 'ircd'  => 'shutdown' );
}
