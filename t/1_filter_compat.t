use strict;
use warnings;
use Test::More;
use POE::Filter::Stackable;
use POE::Filter::IRCD;
use POE::Filter::IRC::Compat;
use POE::Filter::IRC;

my $long = ':joe!joe@example.com PRIVMSG #quitealongchannelnamereally :This is a really really long message really. Quite long in fact when you look at it. I could go on on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on about how long it actually is, but really the IRC server will kick my pimply white ass about it anyways.';

my %tests = (
'part' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo',
                      'Goodbye'
                    ],
          'line' => ':joe!joe@example.com PART #foo :Goodbye',
	  'tests' => 6,
        },
'join' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo'
                    ],
          'line' => ':joe!joe@example.com JOIN #foo',
	  'tests' => 5,
        },
 '366' => 
	{
          'args' => [
                      'magnet.shadowcat.co.uk',
                      '#IRC.pm :End of /NAMES list.',
                      [
                        '#IRC.pm',
                        'End of /NAMES list.'
                      ]
                    ],
	  'line' => ':magnet.shadowcat.co.uk 366 Flibble28185 #IRC.pm :End of /NAMES list.',
	  'tests' => 8,
	},
  'public' =>
	{
          'args' => [
                      'joe!joe@example.com',
                      [
                        '#foo'
                      ],
                      'Fish go moo'
                    ],
          'line' => ':joe!joe@example.com PRIVMSG #foo :Fish go moo',
	  'tests' => 7,
	},
  'notice' =>
	{
          'args' => [
                      'joe!joe@example.com',
                      [
                        '#foo'
                      ],
                      'Fish go moo'
                    ],
          'line' => ':joe!joe@example.com NOTICE #foo :Fish go moo',
	  'tests' => 7,
	},
  'msg' =>
	{
          'args' => [
                      'joe!joe@example.com',
                      [
                        'foobar'
                      ],
                      'Fish go moo'
                    ],
          'line' => ':joe!joe@example.com PRIVMSG foobar :Fish go moo',
	  'tests' => 7,
	},
  'nick' =>
	{
          'args' => [
                      'joe!joe@example.com',
                      'moe'
                    ],
          'line' => ':joe!joe@example.com NICK :moe',
	  'tests' => 5,
	},
  'quit' =>
	{
          'args' => [
                      'joe!joe@example.com',
                      'moe'
                    ],
          'line' => ':joe!joe@example.com QUIT :moe',
	  'tests' => 5,
	},
  'ping' => 
	{
          'args' => [
                      'moe'
                    ],
          'line' => 'PING :moe',
	  'tests' => 4,
	},
  'topic' =>
	{
          'args' => [
                      'joe!joe@example.com',
		      '#foo',
                      'Fish go moo'
                    ],
          'line' => ':joe!joe@example.com TOPIC #foo :Fish go moo',
	  'tests' => 6,
	},
  'kick' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo',
		      'foobar',
                      'Goodbye'
                    ],
          'line' => ':joe!joe@example.com KICK #foo foobar :Goodbye',
	  'tests' => 7,
        },
  'invite' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo',
                    ],
          'line' => ':joe!joe@example.com INVITE foobar :#foo',
	  'tests' => 5,
        },
  'mode' => 
	{
          'args' => [
                      'joe!joe@example.com',
                      '#foo',
		      '+m',
                    ],
          'line' => ':joe!joe@example.com MODE #foo +m',
	  'tests' => 6,
        },
  'ctcp_action' =>
	{
	  'args' => [
                      'joe!joe@example.com',
                      [
                        '#foo'
                      ],
		      'barfs on the floor.',
		    ],
          'line' => ":joe!joe\@example.com PRIVMSG #foo \001ACTION barfs on the floor.\001",
	  'tests' => 7,
	},
);

my $sum;
$sum += $_ for map { $tests{$_}->{tests} } keys %tests;

plan tests => ( 2 + 2 * $sum );

my $stack = POE::Filter::Stackable->new(
		Filters => [ POE::Filter::IRCD->new(), POE::Filter::IRC::Compat->new() ],
);

my $irc_filter = POE::Filter::IRC->new();

foreach my $filter ( $stack, $irc_filter ) {
  isa_ok( $filter, 'POE::Filter::Stackable');
  foreach my $event ( @{ $filter->get([map { $tests{$_}->{line} } sort keys %tests]) } ) {
	next unless defined $tests{ $event->{name} };
	my $test = $tests{ $event->{name} };
	pass('irc_' . $event->{name});
	ok( $event->{raw_line} = $test->{line}, "Raw Line $event->{name}" );
	ok( scalar @{ $event->{args} } == scalar @{ $test->{args} }, "Args count $event->{name}" );
	foreach my $idx ( 0 .. $#{ $test->{args} } ) {
	    if ( ref $test->{args}->[$idx] eq 'ARRAY' ) {
		ok( scalar @{ $event->{args}->[$idx] } == scalar @{ $test->{args}->[$idx] }, "Sub args count $event->{name}" );
		foreach my $iidx ( 0 .. $#{ $test->{args}->[$idx] } ) {
		  ok( $event->{args}->[$idx]->[$iidx] eq $test->{args}->[$idx]->[$iidx], "Sub args Index $event->{name} $idx $iidx" );
		}
	    } 
	    else {
		ok( $event->{args}->[$idx] eq $test->{args}->[$idx], "Args Index $event->{name} $idx" );
	    }
	}
  }
}
