# Author: Chris "BinGOs" Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::Client::Ident;

use strict;
use warnings;
use Socket;
use POE qw(Component::Client::Ident::Agent);
use Carp;
use vars qw($VERSION);

$VERSION = '1.14';

sub spawn {
    my ( $package, $alias ) = splice @_, 0, 2;

    my $self = bless { alias => $alias }, $package;

    $self->{session_id} = POE::Session->create (
	object_states => [ 
		$self => [qw(_start _child query)],
		$self => { ident_agent_reply => '_ident_agent_reply',
			   ident_agent_error => '_ident_agent_error',
			   shutdown          => '_shutdown',
		},
        ],
    )->ID();

    return $self;
}

sub session_id {
  $_[0]->{session_id};
}

sub shutdown {
  my $self = shift;
  $poe_kernel->call( $self->{session_id}, @_ );
}

sub _start {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
  $self->{session_id} = $session->ID();
  $kernel->alias_set( $self->{alias} ) if $self->{alias};
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ ) unless $self->{alias};
  undef;
}

sub _child {
  my ($kernel,$self,$what,$child) = @_[KERNEL,OBJECT,ARG0,ARG1];

  if ( $what eq 'create' ) {
    # Stuff here to match up to our query
    $self->{children}->{ $child->ID() } = 1;
  }
  if ( $what eq 'lose' ) {
    delete $self->{children}->{ $child->ID() };
  }
  undef;
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $kernel->call( $_ => 'shutdown' ) for keys %{ $self->{children} };
  $kernel->alias_remove($_) for $kernel->alias_list();
  $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ ) unless $self->{alias};
  undef;
}

sub query {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  my $package = ref $self;

  my ($peeraddr,$peerport,$sockaddr,$sockport,$socket) = _parse_arguments( @_[ARG0 .. $#_] );

  unless ( $peeraddr and $peerport and $sockaddr and $sockport ) {
    croak "Not enough arguments/items for $package->query";
  }

  $kernel->refcount_increment( $sender->ID() => __PACKAGE__ );

  POE::Component::Client::Ident::Agent->spawn( @_[ARG0 .. $#_], Reference => $sender->ID() );
  undef;
}

sub _ident_agent_reply {
  my ($kernel,$self,$ref) = @_[KERNEL,OBJECT,ARG0];
  my $requester = delete $ref->{Reference};
  $kernel->post( $requester, 'ident_client_reply' , $ref, @_[ARG1 .. $#_] );
  $kernel->refcount_decrement( $requester => __PACKAGE__ );
  undef;
}

sub _ident_agent_error {
  my ($kernel,$self,$ref) = @_[KERNEL,OBJECT,ARG0];
  my $requester = delete $ref->{Reference};
  $kernel->post( $requester, 'ident_client_error', $ref, @_[ARG1 .. $#_] );
  $kernel->refcount_decrement( $requester => __PACKAGE__ );
  undef;
}

sub _parse_arguments {
  my %hash = @_;
  my @returns;

  # If we get a socket it takes precedence over any other arguments
  SWITCH: {
        if ( defined $hash{'Socket'} ) {
          $returns[0] = inet_ntoa( (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[1] );
          $returns[1] = (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[0];
          $returns[2] = inet_ntoa( (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[1] );
          $returns[3] = (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[0];
          $returns[4] = $hash{'Socket'};
          last SWITCH;
        }
        if ( defined $hash{'PeerAddr'} and defined $hash{'PeerPort'} and defined $hash{'SockAddr'} and defined $hash{'SockAddr'} ) {
          $returns[0] = $hash{'PeerAddr'};
          $returns[1] = $hash{'PeerPort'};
          $returns[2] = $hash{'SockAddr'};
          $returns[3] = $hash{'SockPort'};
          last SWITCH;
        }
  }
  return @returns;
}

'Who are you?';

__END__
