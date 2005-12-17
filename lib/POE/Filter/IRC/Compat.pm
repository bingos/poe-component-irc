package POE::Filter::IRC::Compat;

use strict;
use warnings;
use Carp;
use POE::Filter::CTCP;
use Data::Dumper;

our $VERSION = '1.0';

sub new {
  my $type = shift;
  croak "$type requires an even number of parameters" if @_ % 2;
  my $buffer = { @_ };
  $buffer->{BUFFER} = [];
  $buffer->{_ctcp} = POE::Filter::CTCP->new( debug => $buffer->{DEBUG} );
  return bless($buffer, $type);
}

sub get {
  my ($self, $raw_lines) = @_;
  my $events = [];

  foreach my $record (@$raw_lines) {
    warn Dumper( $record ) if ( $self->{DEBUG} );
    if ( ref( $record ) eq 'HASH' and $record->{command} and $record->{params} ) {
      my $event = { raw_line => $record->{raw_line} };
      SWITCH:{
        if ( $record->{raw_line} and $record->{raw_line} =~ tr/\001// ) {
           $event = shift( @{ $self->{_ctcp}->get( [$record->{raw_line}] ) } );
           last SWITCH;
        }
        $event->{name} = lc $record->{command};
        if ( $event->{name} =~ /^\d{3,3}$/ ) {
          $event->{args}->[0] = _decolon( $record->{prefix} );
          shift @{ $record->{params} };
          if ( $record->{params}->[0] and $record->{params}->[0] =~ /\s+/ ) {
            $event->{args}->[1] = $record->{params}->[0];
          } else {
            $event->{args}->[1] = join(' ', ( map { /\s+/ ? ':' . $_ : $_; } @{ $record->{params} } ) );
          }
          $event->{args}->[2] = $record->{params};
        } elsif ( $event->{name} eq 'notice' and !$record->{prefix} ) {
          $event->{name} = 'snotice';
          $event->{args}->[0] = $record->{params}->[1];
        } elsif ( $event->{name} =~ /(privmsg|notice)/ ) {
          if ( $event->{name} eq 'notice' ) {
            $event->{args} = [ _decolon( $record->{prefix} ), [split /,/, $record->{params}->[0]], $record->{params}->[1] ];
          } elsif ( index( $record->{params}->[0], '#' ) >= 0 or index( $record->{params}->[0], '&' ) >= 0
                                or index( $record->{params}->[0], '+' ) >= 0) {
            $event->{args} = [ _decolon( $record->{prefix} ), [split /,/, $record->{params}->[0]], $record->{params}->[1] ];
            $event->{name} = 'public';
          } else {
            $event->{args} = [ _decolon( $record->{prefix} ), [split /,/, $record->{params}->[0]], $record->{params}->[1] ];
            $event->{name} = 'msg';
          }
        } else {
          shift( @{ $record->{params} } ) if ( $event->{name} eq 'invite' );
          unshift( @{ $record->{params} }, _decolon( $record->{prefix} || '' ) ) if $record->{prefix};
          $event->{args} = $record->{params};
        }
      }
      push @$events, $event;
    } else {
      warn "Received line $record that is not IRC protocol\n";
    }
  }
  return $events;
}

sub get_one_start {
  my ($self, $raw_lines) = @_;

  foreach my $record (@$raw_lines) {
	push ( @{ $self->{BUFFER} }, $record );
  }
}

sub get_one {
  my ($self) = shift;
  my $events = [];

  if ( my $record = shift ( @{ $self->{BUFFER} } ) ) {
    warn Dumper( $record ) if ( $self->{DEBUG} );
    if ( ref( $record ) eq 'HASH' and $record->{command} and $record->{params} ) {
      my $event = { raw_line => $record->{raw_line} };
      SWITCH:{
        if ( $record->{raw_line} and $record->{raw_line} =~ tr/\001// ) {
           $event = shift( @{ $self->{_ctcp}->get( [$record->{raw_line}] ) } );
           last SWITCH;
        }
        $event->{name} = lc $record->{command};
        if ( $event->{name} =~ /^\d{3,3}$/ ) {
          $event->{args}->[0] = _decolon( $record->{prefix} );
          shift @{ $record->{params} };
          if ( $record->{params}->[0] and $record->{params}->[0] =~ /\s+/ ) {
            $event->{args}->[1] = $record->{params}->[0];
          } else {
            $event->{args}->[1] = join(' ', ( map { /\s+/ ? ':' . $_ : $_; } @{ $record->{params} } ) );
          }
          $event->{args}->[2] = $record->{params};
        } elsif ( $event->{name} eq 'notice' and !$record->{prefix} ) {
          $event->{name} = 'snotice';
          $event->{args}->[0] = $record->{params}->[1];
        } elsif ( $event->{name} =~ /(privmsg|notice)/ ) {
          if ( $event->{name} eq 'notice' ) {
            $event->{args} = [ _decolon( $record->{prefix} ), [split /,/, $record->{params}->[0]], $record->{params}->[1] ];
          } elsif ( index( $record->{params}->[0], '#' ) >= 0 or index( $record->{params}->[0], '&' ) >= 0
                                or index( $record->{params}->[0], '+' ) >= 0) {
            $event->{args} = [ _decolon( $record->{prefix} ), [split /,/, $record->{params}->[0]], $record->{params}->[1] ];
            $event->{name} = 'public';
          } else {
            $event->{args} = [ _decolon( $record->{prefix} ), [split /,/, $record->{params}->[0]], $record->{params}->[1] ];
            $event->{name} = 'msg';
          }
        } else {
          shift( @{ $record->{params} } ) if ( $event->{name} eq 'invite' );
          unshift( @{ $record->{params} }, _decolon( $record->{prefix} || '' ) ) if $record->{prefix};
          $event->{args} = $record->{params};
        }
      }
      push @$events, $event;
    } else {
      warn "Received line $record that is not IRC protocol\n";
    }
  }
  return $events;
}

sub _decolon ($) {
  my $line = shift;

  $line =~ s/^://;
  return $line;
}

1;
__END__
