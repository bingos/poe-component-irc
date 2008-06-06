use strict;
use warnings;
use POE;
use POE::Component::IRC;
use Test::More;

BEGIN {
    my $GOT_DNS;
    eval { 
        require POE::Component::Client::DNS;
        $GOT_DNS = 1 if $POE::Component::Client::DNS::VERSION >= 0.99;
    };
    if (!$GOT_DNS) {
        plan skip_all => 'POE::Component::Client::DNS 0.99 not installed';
    }
}

plan tests => 4;

my $dns = POE::Component::Client::DNS->spawn();
my $irc = POE::Component::IRC->spawn( Resolver => $dns );

isa_ok($irc, 'POE::Component::IRC');
isa_ok($dns, 'POE::Component::Client::DNS');

POE::Session->create(
    package_states => [ main => [qw(_start)] ],
);

$poe_kernel->run();

sub _start {
    isa_ok($irc->resolver(), 'POE::Component::Client::DNS');
    is($irc->resolver(), $dns, 'DNS objects match');
    $irc->yield('shutdown');
    $dns->shutdown();
}
