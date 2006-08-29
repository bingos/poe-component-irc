use Test::More tests => 3;
use POE;
BEGIN { use_ok('POE::Component::IRC') };
diag( "Testing POE::Component::IRC $POE::Component::IRC::VERSION $POE::Component::IRC::REVISION, POE $POE::VERSION, Perl $], $^X" );

my $self = POE::Component::IRC->new('irc-client');

isa_ok ( $self, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  pass('blah');
  $kernel->post( 'irc-client'  => 'shutdown' );
  undef;
}
