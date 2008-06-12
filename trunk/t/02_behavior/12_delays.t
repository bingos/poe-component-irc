use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use Socket;
use Test::More tests => 4;

my $irc = POE::Component::IRC->spawn();

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            irc_registered 
            irc_socketerr
            irc_delay_set
            irc_delay_removed
        )],
    ],
);

$poe_kernel->run();

sub _start {
    $irc->yield(register => 'all');
}

sub irc_registered {
  my ($heap, $irc) = @_[HEAP, ARG0];
  
  $heap->{alarm_id} =
    $irc->delay( [ connect => {
        nick    => 'TestBot',
        server  => '127.0.0.1',
        port    => 6667,
        ircname => 'Test test bot',
    } ], 25 );

    ok($heap->{alarm_id}, 'Set alarm');
}

sub irc_delay_set {
    my ($heap, $event, $alarm_id) = @_[HEAP, STATE, ARG0];
    
    is($alarm_id, $heap->{alarm_id}, $_[STATE]);
    my $opts = $irc->delay_remove($alarm_id);
    ok($opts, 'Delay Removed');
}

sub irc_delay_removed {
    my ($heap, $alarm_id) = @_[HEAP, ARG0];
    
    is($alarm_id, $heap->{alarm_id}, $_[STATE] );
    $irc->yield( @_[ARG1..$#_] );
}

sub irc_socketerr {
    $irc->yield('shutdown');
}
