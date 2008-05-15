use strict;
use warnings;
use Test::More;

my @classes = qw(
    POE::Component::IRC
    POE::Component::IRC::State
    POE::Component::IRC::Qnet
    POE::Component::IRC::Qnet::State
);

plan tests => scalar @classes;

for my $class (@classes) {
    eval "require $class";
    
    my $self = $class->spawn();
    isa_ok($self, $class);
}

