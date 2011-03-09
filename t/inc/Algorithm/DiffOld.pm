# This is a version of Algorithm::Diff that uses only a comparison function,
# like versions <= 0.59 used to.
# $Revision: 1.3 $

package Algorithm::DiffOld;
use strict;
use vars qw($VERSION @EXPORT_OK @ISA @EXPORT);
use integer;		# see below in _replaceNextLargerWith() for mod to make
					# if you don't use this
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(LCS diff traverse_sequences);
$VERSION = 1.10;	# manually tracking Algorithm::Diff


sub _replaceNextLargerWith
{
	my ( $array, $aValue, $high ) = @_;
	$high ||= $#$array;

	# off the end?
	if ( $high == -1  || $aValue > $array->[ -1 ] )
	{
		push( @$array, $aValue );
		return $high + 1;
	}

	# binary search for insertion point...
	my $low = 0;
	my $index;
	my $found;
	while ( $low <= $high )
	{
		$index = ( $high + $low ) / 2;
#		$index = int(( $high + $low ) / 2);		# without 'use integer'
		$found = $array->[ $index ];

		if ( $aValue == $found )
		{
			return undef;
		}
		elsif ( $aValue > $found )
		{
			$low = $index + 1;
		}
		else
		{
			$high = $index - 1;
		}
	}

	# now insertion point is in $low.
	$array->[ $low ] = $aValue;		# overwrite next larger
	return $low;
}

sub _longestCommonSubsequence
{
	my $a = shift;	# array ref
	my $b = shift;	# array ref
	my $compare = shift || sub { my $a = shift; my $b = shift; $a eq $b };

	my $aStart = 0;
	my $aFinish = $#$a;
	my $bStart = 0;
	my $bFinish = $#$b;
	my $matchVector = [];

	# First we prune off any common elements at the beginning
	while ( $aStart <= $aFinish
		and $bStart <= $bFinish
		and &$compare( $a->[ $aStart ], $b->[ $bStart ], @_ ) )
	{
		$matchVector->[ $aStart++ ] = $bStart++;
	}

	# now the end
	while ( $aStart <= $aFinish
		and $bStart <= $bFinish
		and &$compare( $a->[ $aFinish ], $b->[ $bFinish ], @_ ) )
	{
		$matchVector->[ $aFinish-- ] = $bFinish--;
	}

	my $thresh = [];
	my $links = [];

	my ( $i, $ai, $j, $k );
	for ( $i = $aStart; $i <= $aFinish; $i++ )
	{
		$k = 0;
		# look for each element of @b between $bStart and $bFinish
		# that matches $a->[ $i ], in reverse order
		for ($j = $bFinish; $j >= $bStart; $j--)
		{
			next if ! &$compare( $a->[$i], $b->[$j], @_ );
			# optimization: most of the time this will be true
			if ( $k
				and $thresh->[ $k ] > $j
				and $thresh->[ $k - 1 ] < $j )
			{
				$thresh->[ $k ] = $j;
			}
			else
			{
				$k = _replaceNextLargerWith( $thresh, $j, $k );
			}

			# oddly, it's faster to always test this (CPU cache?).
			if ( defined( $k ) )
			{
				$links->[ $k ] =
					[ ( $k ? $links->[ $k - 1 ] : undef ), $i, $j ];
			}
		}
	}

	if ( @$thresh )
	{
		for ( my $link = $links->[ $#$thresh ]; $link; $link = $link->[ 0 ] )
		{
			$matchVector->[ $link->[ 1 ] ] = $link->[ 2 ];
		}
	}

	return wantarray ? @$matchVector : $matchVector;
}

sub traverse_sequences
{
	my $a = shift;	# array ref
	my $b = shift;	# array ref
	my $callbacks = shift || { };
	my $compare = shift;
	my $matchCallback = $callbacks->{'MATCH'} || sub { };
	my $discardACallback = $callbacks->{'DISCARD_A'} || sub { };
	my $finishedACallback = $callbacks->{'A_FINISHED'};
	my $discardBCallback = $callbacks->{'DISCARD_B'} || sub { };
	my $finishedBCallback = $callbacks->{'B_FINISHED'};
	my $matchVector = _longestCommonSubsequence( $a, $b, $compare, @_ );
	# Process all the lines in match vector
	my $lastA = $#$a;
	my $lastB = $#$b;
	my $bi = 0;
	my $ai;
	for ( $ai = 0; $ai <= $#$matchVector; $ai++ )
	{
		my $bLine = $matchVector->[ $ai ];
		if ( defined( $bLine ) )	# matched
		{
			&$discardBCallback( $ai, $bi++, @_ ) while $bi < $bLine;
			&$matchCallback( $ai, $bi++, @_ );
		}
		else
		{
			&$discardACallback( $ai, $bi, @_ );
		}
	}
	# the last entry (if any) processed was a match.

	if ( defined( $finishedBCallback ) && $ai <= $lastA )
	{
		&$finishedBCallback( $bi, @_ );
	}
	else
	{
		&$discardACallback( $ai++, $bi, @_ ) while ( $ai <= $lastA );
	}

	if ( defined( $finishedACallback ) && $bi <= $lastB )
	{
		&$finishedACallback( $ai, @_ );
	}
	else
	{
		&$discardBCallback( $ai, $bi++, @_ ) while ( $bi <= $lastB );
	}
	return 1;
}

sub LCS
{
	my $a = shift;	# array ref
	my $matchVector = _longestCommonSubsequence( $a, @_ );
	my @retval;
	my $i;
	for ( $i = 0; $i <= $#$matchVector; $i++ )
	{
		if ( defined( $matchVector->[ $i ] ) )
		{
			push( @retval, $a->[ $i ] );
		}
	}
	return wantarray ? @retval : \@retval;
}

sub diff
{
	my $a = shift;	# array ref
	my $b = shift;	# array ref
	my $retval = [];
	my $hunk = [];
	my $discard = sub { push( @$hunk, [ '-', $_[ 0 ], $a->[ $_[ 0 ] ] ] ) };
	my $add = sub { push( @$hunk, [ '+', $_[ 1 ], $b->[ $_[ 1 ] ] ] ) };
	my $match = sub { push( @$retval, $hunk ) if scalar(@$hunk); $hunk = [] };
	traverse_sequences( $a, $b,
		{ MATCH => $match, DISCARD_A => $discard, DISCARD_B => $add },
		@_ );
	&$match();
	return wantarray ? @$retval : $retval;
}

1;
