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
use warnings;

use POE::Filter::Stackable;
use POE::Filter::IRCD;
use POE::Filter::IRC::Compat;

use vars qw($VERSION);

$VERSION = '5.1';

sub new {
  my $package = shift;
  my %opts = @_;
  $opts{lc $_} = delete $opts{$_} for keys %opts;
  return POE::Filter::Stackable->new(
	Filters => [ 
		POE::Filter::IRCD->new( DEBUG => $opts{debug} ),
		POE::Filter::IRC::Compat->new( DEBUG => $opts{debug} ),
	],
  );
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
L<POE::Component::IRC>. They look like this:

    { name => 'event name', args => [ some info about the event ] }

This module was long deprecated in L<POE::Component::IRC>. It now uses the same mechanism that
that uses to parse IRC text.

=head1 CONSTRUCTOR

=over

=item new

Returns a new L<POE::Filter::Stackable> object containing a L<POE::Filter::IRCD> object and a
L<POE::Filter::IRC::Compat> object. This does the same job that POE::Filter::IRC used to do.

=back

=head1 METHODS

=over

=item get

Takes an array reference full of lines of raw IRC text. Returns an
array reference of processed, pasteurised events.

=item put

There is no "put" method. That would be kinda silly for this filter,
don't you think?

=back

=head1 AUTHOR

Dennis C<fimmtiu> Taylor

Refactoring by Chris C<BinGOs> Williams <chris@bingosnet.co.uk>

=head1 SEE ALSO

The documentation for POE and POE::Component::IRC.

L<POE::Filter::Stackable>

L<POE::Filter::IRCD>

L<POE::Filter::IRC::Compat>

=cut
