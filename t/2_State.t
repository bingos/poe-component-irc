use Test::More tests => 4;

BEGIN { use_ok('POE::Component::IRC::State') };

use POE;

my $self = POE::Component::IRC::State->spawn();

isa_ok ( $self, 'POE::Component::IRC::State' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  pass('blah');
  isa_ok( $self->resolver(), 'POE::Component::Client::DNS' );
  $kernel->post( $self->session_id() => 'shutdown' );
  undef;
}
