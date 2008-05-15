use strict;
use warnings;
use Test::More tests => 4;
use POE;

BEGIN { use_ok('POE::Component::IRC') };
diag( "Testing POE::Component::IRC $POE::Component::IRC::VERSION $POE::Component::IRC::REVISION, POE $POE::VERSION, Perl $], $^X" );

my $GOT_DNS;
BEGIN {
    $GOT_DNS = 0;
    eval {
        require POE::Component::Client::DNS;
        $GOT_DNS = 1 if $POE::Component::Client::DNS::VERSION >= 0.99;
        };
}

my $self = POE::Component::IRC->spawn();
isa_ok ( $self, 'POE::Component::IRC' );

POE::Session->create(
    inline_states => { _start => \&test_start, },
);

$poe_kernel->run();
exit;

sub test_start {
    my ($kernel, $heap) = @_[KERNEL,HEAP];
    pass('blah');
    
    SKIP: {
        skip 'POE::Component::Client::DNS 0.99 not installed', 1 if !$GOT_DNS;
        isa_ok($self->resolver(), 'POE::Component::Client::DNS');
    }
    
    $self->yield('shutdown');
}
