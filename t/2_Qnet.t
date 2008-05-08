use Test::More tests => 4;
BEGIN { use_ok('POE::Component::IRC::Qnet') };

my $GOT_DNS;

BEGIN {
  $GOT_DNS = 0;
  eval {
	require POE::Component::Client::DNS;
	$GOT_DNS = 1 if $POE::Component::Client::DNS::VERSION >= 0.99;
  };
}

use POE;

my $self = POE::Component::IRC::Qnet->spawn();

isa_ok ( $self, 'POE::Component::IRC::Qnet' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  pass('blah');
  SKIP: {
    skip "POE::Component::Client::DNS 0.99 not installed", 1 unless $GOT_DNS;
    isa_ok( $self->resolver(), 'POE::Component::Client::DNS' );
  }
  $self->yield( 'shutdown' );
}
