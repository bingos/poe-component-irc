use POE;
use Test::More;

my $GOT_DNS;

BEGIN: {
  $GOT_DNS = 0;
  eval { 
	require POE::Component::Client::DNS;
	$GOT_DNS = 1;
  };
}

unless ( $GOT_DNS ) {
  plan skip_all => "POE::Component::Client::DNS not installed";
}

plan tests => 6;

require_ok('POE::Component::IRC');

my $dns = POE::Component::Client::DNS->spawn();
my $self = POE::Component::IRC->spawn( Resolver => $dns );

isa_ok ( $self, 'POE::Component::IRC' );
isa_ok ( $dns, 'POE::Component::Client::DNS' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  pass('blah');
  isa_ok( $self->resolver(), 'POE::Component::Client::DNS' );
  ok( $self->resolver() eq $dns, "DNS objects match" );
  $self->yield( 'shutdown' );
  $dns->shutdown();
  undef;
}
