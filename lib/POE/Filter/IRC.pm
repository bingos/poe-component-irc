# $Id: IRC.pm,v 1.2 2005/04/28 14:18:20 chris Exp $
#
# POE::Filter::IRC, by Dennis Taylor <dennis@funkplanet.com>
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Filter::IRC;

use strict;
use Carp;


# Create a new, empty POE::Filter::IRC object.
sub new {
  my $class = shift;
  my %args = @_;

  bless {}, $class;
}


# Set/clear the 'debug' flag.
sub debug {
  my $self = shift;
  $self->{'debug'} = $_[0] if @_;
  return $self->{'debug'};
}


# For each line of raw IRC input data that we're fed, spit back the
# appropriate IRC events.
sub get {
  my ($self, $raw) = @_;
  my $events = [];

  foreach my $line (@$raw) {
    warn "<<< $line\n" if $self->{'debug'};
    next unless $line =~ /\S/;

    if ($line =~ /^(PING|PONG) (.+)$/) {
      push @$events, { name => lc $1, args => [$2] };

      # PRIVMSG and NOTICE
    } elsif ($line =~ /^:(\S+) +(PRIVMSG|NOTICE) +(\S+) +(.+)$/) {
      if ($2 eq 'NOTICE') {
	push @$events, { name => 'notice',
			 args => [$1, [split /,/, $3], _decolon( $4 )] };

	# Using tr/// to count characters here tickles a bug in 5.004. Suck.
      } elsif (index( $3, '#' ) >= 0 or index( $3, '&' ) >= 0
	       or index( $3, '+' ) >= 0) {
	push @$events, { name => 'public',
			 args => [$1, [split /,/, $3], _decolon( $4 )] };

      } else {
	push @$events, { name => 'msg',
			 args => [$1, [split /,/, $3], _decolon( $4 )] };
      }

      # Numeric events
    } elsif ($line =~ /^:(\S+) +(\d+) +(\S+) +(.+)$/) {
      push @$events, { name => $2, args => [$1, _decolon( $4 )] };

      # MODE... just split the args and pass them wholesale.
    } elsif ($line =~ /^:(\S+) +MODE +(\S+) +(.+)$/) {
      push @$events, { name => 'mode', args => [$1, $2, split( /\s+/, _decolon( $3 ) )] };

    } elsif ($line =~ /^:(\S+) +KICK +(\S+) +(\S+) +(.+)$/) {
      push @$events, { name => 'kick', args => [$1, $2, $3, _decolon( $4 )] };

    } elsif ($line =~ /^:(\S+) +TOPIC +(\S+) +(.+)$/) {
      push @$events, { name => 'topic', args => [$1, $2, _decolon( $3 )] };

    } elsif ($line =~ /^:(\S+) +INVITE +\S+ +(.+)$/) {
      push @$events, { name => 'invite', args => [$1, _decolon( $2 )] };

    } elsif ($line =~ /^:(\S+) +WALLOPS +(.+)$/) {
      push @$events, { name => 'wallops', args => [$1, _decolon( $2 )] };

      # NICK, QUIT, JOIN, PART, possibly more?
    } elsif ($line =~ /^:(\S+) +(\S+) +(.+)$/) {
      unless (grep {$_ eq lc $2} qw(nick join quit part pong)) {
	warn "*** ACCIDENTAL MATCH: $2\n";
	warn "*** Accident line: $line\n";
      }
      push @$events, { name => lc $2, args => [$1, _decolon( $3 )] };

      # We'll call this 'snotice' (server notice), for lack of a better name.
    } elsif ($line =~ /^NOTICE +\S+ +(.+)$/) {
      push @$events, { name => 'snotice', args => [_decolon( $1 )] };

      # Eeek.
    } elsif ($line =~ /^ERROR +(.+)$/) {
      push @$events, { name => 'error', args => [_decolon( $1 )] };

      # If nothing matches, barf and keep reading. Seems reasonable.
      # I'll reuse the famous "Funky parse case!" error from Net::IRC,
      # just for a sense of historical continuity.
    } else {
      warn "*** Funky parse case!\nFunky line: \"$line\"\n";
    }
  }

  return $events;
}


# Strips superfluous colons from the beginning of text chunks. I can't
# believe that this ludicrous protocol can handle ":foo" and ":foo bar"
# in a totally different manner.
sub _decolon ($) {
  my $line = shift;

#  This is very, very, wrong.
#  if ($line =~ /^:.*\s.*$/) {
#	$line = substr $line, 1;
#  }

  $line =~ s/^://;
  return $line;
}


# This sub is so useless to implement that I won't even bother.
sub put {
  croak "Call to unimplemented subroutine POE::Filter::IRC->put()";
}


1;


__END__

=head1 NAME

POE::Filter::IRC -- A POE-based parser for the IRC protocol.

=head1 SYNOPSIS

    my $filter = POE::Filter::IRC->new();
    my @events = @{$filter->get( [ @lines ] )};

=head1 DESCRIPTION

POE::Filter::IRC takes lines of raw IRC input and turns them into
weird little data structures, suitable for feeding to
POE::Component::IRC. They look like this:

    { name => 'event name', args => [ some info about the event ] }

=head1 METHODS

=over

=item *

new

Creates a new POE::Filter::IRC object. Duh. :-)   Takes no arguments.

=item *

get

Takes an array reference full of lines of raw IRC text. Returns an
array reference of processed, pasteurized events.

=item *

put

There is no "put" method. That would be kinda silly for this filter,
don't you think?

=back

=head1 AUTHOR

Dennis "fimmtiu" Taylor, E<lt>dennis@funkplanet.comE<gt>.

=head1 SEE ALSO

The documentation for POE and POE::Component::IRC.

=cut
