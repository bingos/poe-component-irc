package POE::Filter::IRC::Compat;

use strict;
use warnings;
use POE::Filter::CTCP;
use base qw(POE::Filter);
use vars qw($VERSION);

$VERSION = '1.3';

sub new {
    my ($package, %params) = @_;
    
    $params{lc $_} = delete $params{$_} for keys %params;
    $params{BUFFER} = [ ];
    $params{_ctcp} = POE::Filter::CTCP->new( debug => $params{DEBUG} );
    $params{chantypes} = [ '#', '&' ] if ref $params{chantypes} ne 'ARRAY';
    $params{commands} = {
        qr/^\d{3,3}$/ => sub {
            my ($self, $event, $line) = @_;
            $event->{args}->[0] = _decolon( $line->{prefix} );
            shift @{ $line->{params} };
            if ( $line->{params}->[0] && $line->{params}->[0] =~ /\s+/ ) {
                $event->{args}->[1] = $line->{params}->[0];
            }
            else {
                $event->{args}->[1] = join(' ', ( map { /\s+/ ? ":$_" : $_ } @{ $line->{params} } ) );
            }
            $event->{args}->[2] = $line->{params};
        },
        qr/notice/ => sub {
            my ($self, $event, $line) = @_;
            if ($line->{prefix}) {
                $event->{args} = [ _decolon( $line->{prefix} ), [split /,/, $line->{params}->[0]], $line->{params}->[1] ];
            }
            else {
                $event->{name} = 'snotice';
                $event->{args}->[0] = $line->{params}->[1];
            }
        },
        qr/privmsg/ => sub {
            my ($self, $event, $line) = @_;
            if ( grep { index( $line->{params}->[0], $_ ) >= 0 } @{ $self->{chantypes} } ) {
                $event->{args} = [ _decolon( $line->{prefix} ), [split /,/, $line->{params}->[0]], $line->{params}->[1] ];
                $event->{name} = 'public';
            }
            else {
                $event->{args} = [ _decolon( $line->{prefix} ), [split /,/, $line->{params}->[0]], $line->{params}->[1] ];
                $event->{name} = 'msg';
            }
        },
        qr/invite/ => sub {
            my ($self, $event, $line) = @_;
            shift( @{ $line->{params} } );
            unshift( @{ $line->{params} }, _decolon( $line->{prefix} || '' ) ) if $line->{prefix};
            $event->{args} = $line->{params};
        },
    };
  
    return bless \%params, $package;
}

# Set/clear the 'debug' flag.
sub debug {
    my ($self, $flag) = @_;
    if (defined $flag) {
        $self->{debug} = $flag;
        $self->{_ctcp}->debug($flag);
    }
    return $self->{debug};
}

sub chantypes {
    my ($self, $ref) = @_;
    return if ref $ref ne 'ARRAY' || !scalar @{ $ref };
    $self->{chantypes} = $ref;
    return 1;
}

sub get {
    my ($self, $raw_lines) = @_;
    my $events = [ ];

    LINE: for my $line (@$raw_lines) {
        if (ref $line ne 'HASH' || !$line->{command} || !$line->{params}) {
            warn "Received line '$line' that is not IRC protocol\n" if $self->{debug};
            next LINE;
        }
    
        my $event = {
            name     => lc $line->{command},
            raw_line => $line->{raw_line},
        };
    
        if ( $line->{raw_line} =~ tr/\001// ) {
            $event = shift( @{ $self->{_ctcp}->get( [$line->{raw_line}] ) } );
            push @$events, $event;
            next LINE;
        }
    
        for my $cmd (keys %{ $self->{commands} }) {
            if ($event->{name} =~ $cmd) {
                $self->{commands}->{$cmd}->($self, $event, $line);
                push @$events, $event;
                next LINE;
            }
        }
    
        # default
        unshift( @{ $line->{params} }, _decolon( $line->{prefix} || '' ) ) if $line->{prefix};
        $event->{args} = $line->{params};
        push @$events, $event;
    }
  
    return $events;
}

sub get_one_start {
    my ($self, $raw_lines) = @_;

    for my $line (@$raw_lines) {
        push ( @{ $self->{BUFFER} }, $line );
    }
    return;
}

sub get_one {
    my ($self) = @_;

    my $events = $self->get($self->{BUFFER});
    $self->{BUFFER} = [ ];
    return $events;
}

sub clone {
  my $self = shift;
  my $nself = { };
  $nself->{$_} = $self->{$_} for keys %{ $self };
  $nself->{BUFFER} = [ ];
  return bless $nself, ref $self;
}

sub _decolon {
    my ($line) = @_;

    $line =~ s/^://;
    return $line;
}

1;
__END__

=head1 NAME

POE::Filter::IRC::Compat - A filter which converts L<POE::Filter::IRCD|POE::Filter::IRCD>
output into L<POE::Component::IRC|POE::Component::IRC> events.

=head1 DESCRIPTION

POE::Filter::IRC::Compat is a L<POE::Filter|POE::Filter> that converts
L<POE::Filter::IRCD|POE::Filter::IRCD> output into the L<POE::Component::IRC|POE::Component::IRC>
compatible event references. Basically a hack, so I could replace
L<POE::Filter::IRC|POE::Filter::IRC> with something that was more
generic.

=head1 CONSTRUCTOR

=over

=item C<new>

Returns a POE::Filter::IRC::Compat object.

=back

=head1 METHODS

=over

=item C<get>

Takes an arrayref of L<POE::Filter::IRCD> hashrefs and produces an arrayref of
L<POE::Component::IRC|POE::Component::IRC> compatible event hashrefs. Yay.

=item C<get_one_start>

=item C<get_one>

These perform a similar function as get() but enable the filter to work with
L<POE::Filter::Stackable|POE::Filter::Stackable>.

=item C<chantypes>

Takes an arrayref of possible channel prefix indicators.

=item C<debug>

Takes a true/false value which enables/disbles debugging accordingly.
Returns the debug status.

=item clone

Makes a copy of the filter, and clears the copy's buffer.

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Filter|POE::Filter>

L<POE::Filter::Stackable|POE::Filter::Stackable>

=cut
