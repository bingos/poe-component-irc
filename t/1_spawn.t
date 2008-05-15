use strict;
use warnings;
use Test::More;
use POE;

my @classes = qw(
    POE::Component::IRC
    POE::Component::IRC::State
    POE::Component::IRC::Qnet
    POE::Component::IRC::Qnet::State
);

my @sessions;

plan tests => scalar @classes;

for my $class (@classes) {
    eval "require $class";
    
    my $self = $class->spawn();
    isa_ok($self, $class);
    push @sessions, $self;
}

POE::Session->create(
  inline_states => {
	_start => sub { $poe_kernel->post( $_->session_id, 'shutdown' ) for @{ $_[HEAP]->{sessions} }; return },
  },
  heap => { sessions => \@sessions, },
);

$poe_kernel->run();
exit 0;
