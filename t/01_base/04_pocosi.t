use strict;
use warnings;
use lib 't/inc';
use POE;
use POE::Component::Server::IRC;
use Test::More tests => 2;

my $ircd = POE::Component::Server::IRC->spawn( Alias => 'ircd' );
isa_ok($ircd, 'POE::Component::Server::IRC');

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
