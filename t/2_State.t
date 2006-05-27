use Test::More tests => 4;
BEGIN { use_ok('POE::Component::IRC::State') };

my $GOT_DNS;

BEGIN: {
  $GOT_DNS = 0;
  eval {
	use POE::Component::Client::DNS 0.99;
	$GOT_DNS = 1;
  };
}

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
  SKIP: {
    skip "POE::Component::Client::DNS not installed", 1 unless $GOT_DNS;
    isa_ok( $self->resolver(), 'POE::Component::Client::DNS' );
  }
  $self->yield( 'shutdown' );
  undef;
}
