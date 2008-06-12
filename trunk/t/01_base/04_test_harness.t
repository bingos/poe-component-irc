use strict;
use warnings;
use POE;
use POE::Component::IRC::Test::Harness;
use Test::More tests => 2;

my $ircd = POE::Component::IRC::Test::Harness->spawn( Alias => 'ircd' );
isa_ok($ircd, 'POE::Component::IRC::Test::Harness');

POE::Session->create(
    package_states => [
        main => [ qw(_start) ]
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel) = $_[KERNEL];
    pass('Session started');
    $kernel->post(ircd => 'shutdown');
}
