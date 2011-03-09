package POE::Component::Server::IRC::Common;

# We export some stuff
require Exporter;
@ISA = qw( Exporter );
%EXPORT_TAGS = ( 'ALL' => [ qw(u_irc l_irc gen_mode_change parse_mode_line unparse_mode_line parse_ban_mask validate_nick_name validate_chan_name matches_mask_array matches_mask parse_user mkpasswd chkpasswd) ] );
Exporter::export_ok_tags( 'ALL' );

use strict;
use warnings FATAL => 'all';
use Algorithm::Diff qw(diff);
use Crypt::PasswdMD5;
use vars qw($VERSION);

$VERSION = '1.21';

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
  my @args = @_;
  my $chanmodes = [qw(beI k l imnpst)];
  my $statmodes = 'ohv';
  my $hashref = { };
  my $count = 0;
  while ( my $arg = shift @args ) {
        if ( ref $arg eq 'ARRAY' ) {
           $chanmodes = $arg;
           next;
        }
        if ( ref $arg eq 'HASH' ) {
           $statmodes = join '', keys %{ $arg };
           next;
        }
        if ( $arg =~ /^(\+|-)/ or $count == 0 ) {
           my $action = '+';
           foreach my $char ( split (//,$arg) ) {
                if ( $char eq '+' or $char eq '-' ) {
                   $action = $char;
                } else {
                   push @{ $hashref->{modes} }, $action . $char;
                }
                push @{ $hashref->{args} }, shift @args if $char =~ /[$statmodes$chanmodes->[0]$chanmodes->[1]]/;
                push @{ $hashref->{args} }, shift @args if $action eq '+' and $char =~ /[$chanmodes->[2]]/;
           }
         } else {
                push @{ $hashref->{args} }, $arg;
         }
         $count++;
  }
  return $hashref;
}

sub parse_ban_mask {
  my $arg = shift || return undef;

  $arg =~ s/\x2a+/\x2a/g;
  my @ban; my $remainder;
  if ( $arg !~ /\x21/ and $arg =~ /\x40/ ) {
     $remainder = $arg;
  } else {
     ($ban[0],$remainder) = split (/\x21/,$arg,2);
  }
  $remainder =~ s/\x21//g if ( defined ( $remainder ) );
  @ban[1..2] = split (/\x40/,$remainder,2) if ( defined ( $remainder ) );
  $ban[2] =~ s/\x40//g if ( defined ( $ban[2] ) );
  for ( my $i = 0; $i <= 2; $i++ ) {
    if ( !defined ( $ban[$i] ) or $ban[$i] eq '' ) {
       $ban[$i] = '*';
    }
  }
  return $ban[0] . '!' . $ban[1] . '@' . $ban[2];
}

sub unparse_mode_line {
  my $line = $_[0] || return;

  my $action; my $return;
  foreach my $mode ( split(//,$line) ) {
	if ( $mode =~ /^(\+|-)$/ and ( !$action or $mode ne $action ) ) {
	  $return .= $mode;
	  $action = $mode;
	  next;
	}
	$return .= $mode if ( $mode ne '+' and $mode ne '-' );
  }
  $return =~ s/[+-]$//;
  return $return;
}

sub validate_nick_name {
  my $nickname = shift || return 0;
  return 1 if $nickname =~ /^[A-Za-z_0-9`\-^\|\\\{}\[\]]+$/;
  return 0;
}

sub validate_chan_name {
  my $channel = shift || return 0;
  return 1 if $channel =~ /^(\x23|\x26|\x2B)/ and $channel !~ /(\x20|\x07|\x00|\x0D|\x0A|\x2C)+/;
  return 0;
}

sub matches_mask_array {
  my ($masks,$matches) = @_;
  return unless $masks and $matches;
  return unless ref $masks eq 'ARRAY';
  return unless ref $matches eq 'ARRAY';
  my $ref = { };
  foreach my $mask ( @{ $masks } ) {
	foreach my $match ( @{ $matches } ) {
    	   push @{ $ref->{ $mask } }, $match if matches_mask( $mask, $match );
	}
  }
  return $ref;
}

sub matches_mask {
  my ($mask,$match) = @_;
  return unless $mask and $match;
  $match = u_irc $match;
  $mask =~ s/\x2A+/\x2A/g;
  my $umask = quotemeta u_irc $mask;
  $umask =~ s/\\\*/[\x01-\xFF]{0,}/g;
  $umask =~ s/\\\?/[\x01-\xFF]{1,1}/g;
  return 1 if $match =~ /^$umask$/;
  return 0;
}

sub gen_mode_change {
  my $before = shift || '';
  my $after  = shift || '';
  my @before = split //, $before;
  my @after  = split //, $after;
  my $string = '';
  my @hunks = diff( \@before, \@after );
  foreach my $h ( @hunks ) {
	$string .= $_->[0] . $_->[2] for @{ $h };
  }
  return unparse_mode_line( $string );
}

sub parse_user {
  my $user = shift || return;
  my ($n,$u,$h) = split /[!@]/, $user;
  return ($n,$u,$h) if wantarray();
  return $n;
}

sub mkpasswd {
  my $plain = shift || return;
  my %opts = @_;
  $opts{lc $_} = delete $opts{$_} for keys %opts;
  return unix_md5_crypt($plain) if $opts{md5};
  return apache_md5_crypt($plain) if $opts{apache};
  my $salt = join '', ('.','/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
  return crypt( $plain, $salt );
}

sub chkpasswd {
  my $pass = shift || return;
  my $chk = shift || return;
  my $md5 = '$1$'; my $apr = '$apr1$';
  if ( index($chk,$apr) == 0 ) {
     my $salt = $chk;
     $salt =~ s/^\Q$apr//;
     $salt =~ s/^(.*)\$/$1/;
     $salt = substr( $salt, 0, 8 );
     return 1 if apache_md5_crypt( $pass, $salt ) eq $chk;
  }
  elsif ( index($chk,$md5) == 0 ) {
     my $salt = $chk;
     $salt =~ s/^\Q$md5//;
     $salt =~ s/^(.*)\$/$1/;
     $salt = substr( $salt, 0, 8 );
     return 1 if unix_md5_crypt( $pass, $salt ) eq $chk;
  }
  return 1 if crypt( $pass, $chk ) eq $chk;
  return 1 if $pass eq $chk;
  return;
}

1;
__END__
