package POE::Component::IRC::Common;

use strict;
use warnings;

our $VERSION = '4.86';

# We export some stuff
require Exporter;
our @ISA = qw( Exporter );
our %EXPORT_TAGS = ( 'ALL' => [ qw(u_irc l_irc parse_mode_line parse_ban_mask matches_mask parse_user) ] );
Exporter::export_ok_tags( 'ALL' );

sub u_irc {
  my $value = shift || return;
  my $type = shift || 'rfc1459';
  $type = lc $type;

  SWITCH: {
    if ( $type eq 'ascii' ) {
	$value =~ tr/a-z/A-Z/;
	last SWITCH;
    }
    if ( $type eq 'strict-rfc1459' ) {
    	$value =~ tr/a-z{}|/A-Z[]\\/;
	last SWITCH;
    }
    $value =~ tr/a-z{}|^/A-Z[]\\~/;
  }
  return $value;
}

sub l_irc {
  my $value = shift || return;
  my $type = shift || 'rfc1459';
  $type = lc $type;

  SWITCH: {
    if ( $type eq 'ascii' ) {
    	$value =~ tr/A-Z/a-z/;
	last SWITCH;
    }
    if ( $type eq 'strict-rfc1459' ) {
    	$value =~ tr/A-Z[]\\/a-z{}|/;
	last SWITCH;
    }
    $value =~ tr/A-Z[]\\~/a-z{}|^/;
  }
  return $value;
}

sub parse_mode_line {
  my $hashref = { };

  my $count = 0;
  foreach my $arg ( @_ ) {
        if ( $arg =~ /^(\+|-)/ or $count == 0 ) {
           my $action = '+';
           foreach my $char ( split (//,$arg) ) {
                if ( $char eq '+' or $char eq '-' ) {
                   $action = $char;
                } else {
                   push @{ $hashref->{modes} }, $action . $char;
                }
           }
         } else {
                push @{ $hashref->{args} }, $arg;
         }
         $count++;
  }
  return $hashref;
}

sub parse_ban_mask {
  my $arg = shift || return;

  $arg =~ s/\x2a{2,}/\x2a/g;
  my @ban; my $remainder;
  if ( $arg !~ /\x21/ and $arg =~ /\x40/ ) {
     $remainder = $arg;
  } else {
     ($ban[0],$remainder) = split (/\x21/,$arg,2);
  }
  $remainder =~ s/\x21//g if defined $remainder;
  @ban[1..2] = split (/\x40/,$remainder,2) if defined $remainder;
  $ban[2] =~ s/\x40//g if defined $ban[2];
  for ( my $i = 0; $i <= 2; $i++ ) {
     $ban[$i] = '*' unless $ban[$i];
  }
  return $ban[0] . '!' . $ban[1] . '@' . $ban[2];
}

sub matches_mask_array {
  my ($masks,$matches,$mapping) = @_;
  return unless $masks and $matches;
  return unless ref $masks eq 'ARRAY';
  return unless ref $matches eq 'ARRAY';
  my $ref = { };
  foreach my $mask ( @{ $masks } ) {
        foreach my $match ( @{ $matches } ) {
           push @{ $ref->{ $mask } }, $match if matches_mask( $mask, $match, $mapping );
        }
  }
  return $ref;
}

sub matches_mask {
  my ($mask,$match,$mapping) = @_;
  return unless $mask and $match;
  $mask = parse_ban_mask( $mask );
  $mask =~ s/\x2A+/\x2A/g;
  my $umask = quotemeta u_irc( $mask, $mapping );
  $umask =~ s/\\\*/[\x01-\xFF]{0,}/g;
  $umask =~ s/\\\?/[\x01-\xFF]{1,1}/g;
  $match = u_irc $match, $mapping;
  return 1 if $match =~ /^$umask$/;
  return 0;
}

sub parse_user {
  my $user = shift || return;
  my ($n,$u,$h) = split /[!@]/, $user;
  return ($n,$u,$h) if wantarray();
  return $n;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Common - provides a set of common functions for the L<POE::Component::IRC> suite.

=head1 SYNOPSIS

  use strict;
  use warnings;

  use POE::Component::IRC::Common qw( :ALL );

  my $nickname = '^Lame|BOT[moo]';

  my $uppercase_nick = u_irc( $nickname );
  my $lowercase_nick = l_irc( $nickname );

  my $mode_line = 'ov+b-i Bob sue stalin*!*@*';
  my $hashref = parse_mode_line( $mode_line );

  my $banmask = 'stalin*';
  $full_banmask = parse_ban_mask( $banmask );

  if ( matches_mask( $full_banmask, 'stalin!joe@kremlin.ru' ) ) {
	print "EEK!";
  }

  my $results_hashref = matches_mask_array( \@masks, \@items_to_match_against );

  my $nick = parse_user( 'stalin!joe@kremlin.ru' );
  my ($nick,$user,$host) = parse_user( 'stalin!joe@kremlin.ru' );

=head1 DESCRIPTION

POE::Component::IRC::Common provides a set of common functions for the L<POE::Component::IRC> suite. There are included functions for uppercase and lowercase nicknames/channelnames and for parsing mode lines and ban masks.

=head1 FUNCTIONS

=over

=item u_irc

Takes one mandatory parameter, a string to convert to IRC uppercase, and one optional parameter, the casemapping of the ircd ( which can be 'rfc1459', 'strict-rfc1459' or 'ascii'. Default is 'rfc1459' ). Returns the IRC uppercase equivalent of the passed string.

=item l_irc

Takes one mandatory parameter, a string to convert to IRC lowercase, and one optional parameter, the casemapping of the ircd ( which can be 'rfc1459', 'strict-rfc1459' or 'ascii'. Default is 'rfc1459' ). Returns the IRC lowercase equivalent of the passed string.

=item parse_mode_line

Takes a list representing an IRC mode line. Returns a hashref. If the modeline couldn't be parsed the hashref will be empty. On success the following keys will be available in the hashref:

   'modes', an arrayref of normalised modes;
   'args', an arrayref of applicable arguments to the modes;

Example:

   my $hashref = parse_mode_line( 'ov+b-i', 'Bob', 'sue', 'stalin*!*@*' );

   $hashref will be 
   {
	'modes' => [ '+o', '+v', '+b', '-i' ],
	'args'  => [ 'Bob', 'sue', 'stalin*!*@*' ],
   };

=item parse_ban_mask

Takes one parameter, a string representing an IRC ban mask. Returns a normalised full banmask.

Example:

   $fullbanmask = parse_ban_mask( 'stalin*' );

   $fullbanmask will be 'stalin*!*@*';

=item matches_mask

Takes two parameters, a string representing an IRC mask ( it'll be processed with parse_ban_mask() to ensure that it is normalised ) and something to match against the IRC mask, such as a nick!user@hostname string. Returns 1 if they match, 0 otherwise. Returns undef if parameters are missing. Optionally, one may pass the casemapping ( see u_irc() ), as this function ises u_irc() internally.

=item matches_mask_array

Takes two array references, the first being a list of strings representing IRC mask, the second a list of somethings to test against the masks. Returns an empty hashref if there are no matches. Matches are returned are arrayrefs keyed on the mask that they matched.

=item parse_user

Takes one parameter, a string representing a user in the form nick!user@hostname. In a scalar context it returns just the nickname. In a list context it returns a list consisting of the nick, user and hostname, respectively.

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC>
