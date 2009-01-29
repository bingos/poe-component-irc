# Author: Chris "BinGOs" Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::Client::Ident::Agent;

use strict;
use warnings;
use POE qw( Wheel::SocketFactory Wheel::ReadWrite Driver::SysRW
            Filter::Line Filter::Stream Filter::Ident);
use Carp;
use Socket;
use vars qw($VERSION);

$VERSION = '1.14';

sub spawn {
    my $package = shift;

    my ($peeraddr,$peerport,$sockaddr,$sockport,$identport,$buggyidentd,$timeout,$reference) = _parse_arguments(@_);
 
    unless ( $peeraddr and $peerport and $sockaddr and $sockport ) {
        croak "Not enough arguments supplied to $package->spawn";
    }

    my $self = $package->_new($peeraddr,$peerport,$sockaddr,$sockport,$identport,$buggyidentd,$timeout,$reference);

    $self->{session_id} = POE::Session->create(
        object_states => [
	    $self => { shutdown => '_shutdown', },
            $self => [qw(_start _sock_up _sock_down _sock_failed _parse_line _time_out)],
        ],
    )->ID();

    return $self;
}

sub _new {
    my ( $package, $peeraddr, $peerport, $sockaddr, $sockport, $identport, $buggyidentd, $timeout, $reference) = @_;
    return bless { event_prefix => 'ident_agent_', peeraddr => $peeraddr, peerport => $peerport, sockaddr => $sockaddr, sockport => $sockport, identport => $identport, buggyidentd => $buggyidentd, timeout => $timeout, reference => $reference }, $package;
}

sub session_id {
  return $_[0]->{session_id};
}

sub _start {
    my ( $kernel, $self, $session, $sender ) = @_[ KERNEL, OBJECT, SESSION, SENDER ];

    $self->{sender} = $sender->ID();
    $self->{session_id} = $session->ID();
    $self->{ident_filter} = POE::Filter::Ident->new();
    $kernel->delay( '_time_out' => $self->{timeout} );
    $self->{socketfactory} = POE::Wheel::SocketFactory->new(
                                        SocketDomain => AF_INET,
                                        SocketType => SOCK_STREAM,
                                        SocketProtocol => 'tcp',
                                        RemoteAddress => $self->{'peeraddr'},
                                        RemotePort => ( $self->{'identport'} ? ( $self->{'identport'} ) : ( 113 ) ),
                                        SuccessEvent => '_sock_up',
                                        FailureEvent => '_sock_failed',
                                        ( $self->{sockaddr} ? (BindAddress => $self->{sockaddr}) : () ),
    );
    $self->{query_string} = $self->{peerport} . ", " . $self->{sockport};
    $self->{query} = { PeerAddr => $self->{peeraddr}, PeerPort => $self->{peerport}, SockAddr => $self->{sockaddr}, SockPort => $self->{sockport}, Reference => $self->{reference} };
    undef;
}

sub _sock_up {
  my ($kernel,$self,$socket) = @_[KERNEL,OBJECT,ARG0];
  my $filter;

  delete $self->{socketfactory};

  if ( $self->{buggyidentd} ) {
	$filter = POE::Filter::Line->new();
  } else {
	$filter = POE::Filter::Line->new( Literal => "\x0D\x0A" );
  }

  $self->{socket} = new POE::Wheel::ReadWrite
  (
        Handle => $socket,
        Driver => POE::Driver::SysRW->new(),
        Filter => $filter,
        InputEvent => '_parse_line',
        ErrorEvent => '_sock_down',
  );

  $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" ) unless $self->{socket};
  $self->{socket}->put($self->{query_string}) if $self->{socket};
  $kernel->delay( '_time_out' => $self->{timeout} );
  undef;
}

sub _sock_down {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" ) unless $self->{had_a_response};
  delete $self->{socket};
  $kernel->delay( '_time_out' => undef );
  undef;
}


sub _sock_failed {
  my ($kernel, $self) = @_[KERNEL,OBJECT];

  $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
  $kernel->delay( '_time_out' => undef );
  delete $self->{socketfactory};
  undef;
}

sub _time_out {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
  delete $self->{socketfactory};
  delete $self->{socket};
  undef;
}

sub _parse_line {
  my ($kernel,$self,$line) = @_[KERNEL,OBJECT,ARG0];
  my @cooked;

  @cooked = @{$self->{ident_filter}->get( [$line] )};

  foreach my $ev (@cooked) {
    if ( $ev->{name} eq 'barf' ) {
	# Filter choaked for whatever reason
        $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
    } else {
      $ev->{name} = $self->{event_prefix} . $ev->{name};
      my ($port1, $port2, @args) = @{$ev->{args}};
      if ( $self->_port_pair_matches( $port1, $port2 ) ) {
        $kernel->post( $self->{sender}, $ev->{name}, $self->{query}, @args );
      } else {
        $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
      }
    }
  }
  $kernel->delay( '_time_out' => undef );
  $self->{had_a_response} = 1;
  delete $self->{socket};
  undef;
}

sub shutdown {
  my $self = shift;
  $poe_kernel->call( $self->session_id() => 'shutdown' => @_ );
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{had_a_response} = 1;
  delete $self->{socket};
  $kernel->delay( '_time_out' => undef );
  undef;
}

sub _port_pair_matches {
  my ($self) = shift;
  my ($port1,$port2) = @_;
  return 1 if $port1 == $self->{peerport} and $port2 == $self->{sockport};
  return 0;
}

sub _parse_arguments {
  my ( %hash ) = @_;
  my @returns;

  # If we get a socket it takes precedence over any other arguments
  SWITCH: {
	if ( defined ( $hash{'Reference'} ) ) {
	  $returns[7] = $hash{'Reference'};
	}
        if ( defined ( $hash{'IdentPort'} ) ) {
	  $returns[4] = $hash{'IdentPort'};
        }
	if ( defined ( $hash{'BuggyIdentd'} ) and $hash{'BuggyIdentd'} == 1 ) {
	  $returns[5] = $hash{'BuggyIdentd'};
	}
	if ( defined ( $hash{'TimeOut'} ) and ( $hash{'TimeOut'} > 5 or $hash{'TimeOut'} < 30 ) ) {
	  $returns[6] = $hash{'TimeOut'};
        }
	$returns[6] = 30 unless ( defined ( $returns[6] ) );
	if ( defined ( $hash{'Socket'} ) ) {
	  $returns[0] = inet_ntoa( (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[1] );
    	  $returns[1] = (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[0];
	  $returns[2] = inet_ntoa( (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[1] );
          $returns[3] = (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[0];
	  last SWITCH;
	}
	if ( defined ( $hash{'PeerAddr'} ) and defined ( $hash{'PeerPort'} ) and defined ( $hash{'SockAddr'} ) and defined ( $hash{'SockAddr'} ) ) {
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
