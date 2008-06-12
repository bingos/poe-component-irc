use strict;
use warnings;
use POE;
use POE::Component::IRC::Qnet;
use Test::More tests => 1;

my $irc = POE::Component::IRC::Qnet->spawn();
isa_ok($irc, 'POE::Component::IRC::Qnet');
$irc->yield('shutdown');

$poe_kernel->run();

POE::Session->create(
    package_states => [ main => [qw(_start)] ],
);

sub _start {
    $irc->yield('shutdown');
}
