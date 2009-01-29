# Author Chris "BinGOs" Williams
# Cribbed the regexps from Net::Ident by Jan-Pieter Cornet
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Filter::Ident;

use strict;
use warnings;
use Carp;
use vars qw($VERSION);

$VERSION = '1.14';

sub new {
  my $class = shift;
  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;
  bless \%args, $class;
}


# Set/clear the 'debug' flag.
sub debug {
  my $self = shift;
  $self->{'debug'} = $_[0] if @_;
  return $self->{'debug'};
}


sub get {
  my ($self, $raw) = @_;
  my $events = [];

  foreach my $line (@$raw) {
    warn "<<< $line\n" if $self->{'debug'};
    next unless $line =~ /\S/;

    my ($port1, $port2, $replytype, $reply) =
      $line =~
       /^\s*(\d+)\s*,\s*(\d+)\s*:\s*(ERROR|USERID)\s*:\s*(.*)$/;

    SWITCH: {
      unless ( defined $reply ) {
        push @$events, { name => 'barf', args => [ 'UKNOWN-ERROR' ] };
        last SWITCH;
      }
      if ( $replytype eq 'ERROR' ) {
	my ($error);
	( $error = $reply ) =~ s/\s+$//;
	push @$events, { name => 'error', args => [ $port1, $port2, $error ] };
        last SWITCH;
      } 
      if ( $replytype eq 'USERID' ) {
	my ($opsys, $userid);
	unless ( ($opsys, $userid) =
		 ($reply =~ /\s*((?:[^\\:]+|\\.)*):(.*)$/) ) {
	    # didn't parse properly, abort.
            push @$events, { name => 'barf', args => [ 'UKNOWN-ERROR' ] };
            last SWITCH;
	}
	# remove trailing whitespace, except backwhacked whitespaces from opsys
	$opsys =~ s/([^\\])\s+$/$1/;
	# un-backwhack opsys.
	$opsys =~ s/\\(.)/$1/g;

	# in all cases is leading whitespace removed from the username, even
	# though rfc1413 mentions that it shouldn't be done, current
	# implementation practice dictates otherwise. What insane OS would
	# use leading whitespace in usernames anyway...
	$userid =~ s/^\s+//;

	# Test if opsys is "special": if it contains a charset definition,
	# or if it is "OTHER". This means that it is rfc1413-like, instead
	# of rfc931-like. (Why can't they make these RFCs non-conflicting??? ;)
	# Note that while rfc1413 (the one that superseded rfc931) indicates
	# that _any_ characters following the final colon are part of the
	# username, current implementation practice inserts a space there,
	# even "modern" identd daemons.
	# Also, rfc931 specifically mentions escaping characters, while
	# rfc1413 does not mention it (it isn't really necessary). Anyway,
	# I'm going to remove trailing whitespace from userids, and I'm
	# going to un-backwhack them, unless the opsys is "special".
	unless ( $opsys =~ /,/ || $opsys eq 'OTHER' ) {
	    # remove trailing whitespace, except backwhacked whitespaces.
	    $userid =~ s/([^\\])\s+$/$1/;
	    # un-backwhack
	    $userid =~ s/\\(.)/$1/g;
	}
	push @$events, { name => 'reply', args => [ $port1, $port2, $opsys, $userid ] };
	last SWITCH;
      }
      # If we fell out here then it is probably an error
      push @$events, { name => 'barf', args => [ 'UKNOWN-ERROR' ] };
    }
  }

  return $events;
}


# This sub is so useless to implement that I won't even bother.
sub put {
  croak "Call to unimplemented subroutine POE::Filter::Ident->put()";
}


1;


__END__
