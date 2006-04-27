package POE::Component::IRC::Common;

use strict;
use warnings;

our $VERSION = '4.86';

# We export some stuff
require Exporter;
our @ISA = qw( Exporter );
our %EXPORT_TAGS = ( 'ALL' => [ qw(u_irc l_irc parse_mode_line parse_ban_mask) ] );
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

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC>
