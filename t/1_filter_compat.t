use strict;
use warnings;
use Test::More tests => 26;
BEGIN: { use_ok("POE::Filter::IRC::Compat") };
BEGIN: { use_ok("POE::Filter::IRC") };

use POE::Filter::Stackable;
use POE::Filter::IRCD;

my %tests = (
'part' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo',
                      'Goodbye'
                    ],
          'line' => ':joe!joe@example.com PART #foo :Goodbye',
        }, # 6
'join' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo'
                    ],
          'line' => ':joe!joe@example.com JOIN #foo',
        }, # 5
);

my $stack = POE::Filter::Stackable->new(
		Filters => [ POE::Filter::IRCD->new(), POE::Filter::IRC::Compat->new() ],
);

my $irc_filter = POE::Filter::IRC->new();

foreach my $filter ( $stack, $irc_filter ) {
  isa_ok( $filter, 'POE::Filter::Stackable');
  foreach my $event ( @{ $filter->get([map { $_->{line} } values %tests]) } ) {
	next unless defined $tests{ $event->{name} };
	my $test = $tests{ $event->{name} };
	pass($event->{name});
	ok( $event->{raw_line} = $test->{line}, "Raw Line $event->{name}" );
	ok( scalar @{ $event->{args} } == scalar @{ $test->{args} }, "Args count $event->{name}" );
	foreach my $idx ( 0 .. $#{ $test->{args} } ) {
	    if ( ref $test->{args}->[$idx] eq 'ARRAY' ) {
		ok( scalar @{ $event->{args}->[$idx] } == scalar @{ $test->{args}->[$idx] }, "Sub args count $event->{name}" );
	    } 
	    else {
		ok( $event->{args}->[$idx] eq $test->{args}->[$idx], "Args Index $event->{name} $idx" );
	    }
	}
  }
}

