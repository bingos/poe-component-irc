use Test::More tests => 7;
BEGIN { use_ok('POE::Component::IRC') };
BEGIN { use_ok('POE::Component::Client::DNS') };

use POE;

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
