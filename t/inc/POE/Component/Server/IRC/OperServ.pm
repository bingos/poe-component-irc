package POE::Component::Server::IRC::OperServ;

use strict;
use warnings;
use POE::Component::Server::IRC::Plugin qw(:ALL);
use base qw(POE::Component::Server::IRC);

our $VERSION = '1.25';

sub _load_our_plugins {
  my $self = shift;
  $self->SUPER::_load_our_plugins();
  $self->yield( 'add_spoofed_nick', { nick => 'OperServ', umode => 'Doi', ircname => 'The OperServ bot' } );
}

sub IRCD_daemon_privmsg {
  my ($self,$ircd) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  return PCSI_EAT_NONE unless $ircd->state_user_is_operator( $nick );
  my $request = ${ $_[2] };
  SWITCH: {
    if ( my ($chan) = $request =~ /^clear\s+(#.+)\s*$/i ) {
	last SWITCH unless $ircd->state_chan_exists( $chan );
	$ircd->yield( 'daemon_cmd_sjoin', 'OperServ', $chan );
	last SWITCH;
    }
    if ( my ($chan) = $request =~ /^join\s+(#.+)\s*$/i ) {
	last SWITCH unless $ircd->state_chan_exists( $chan );
	$ircd->yield( 'daemon_cmd_join', 'OperServ', $chan );
	last SWITCH;
    }
    if ( my ($chan) = $request =~ /^part\s+(#.+)\s*$/i ) {
	last SWITCH unless $ircd->state_chan_exists( $chan );
	$ircd->yield( 'daemon_cmd_part', 'OperServ', $chan );
	last SWITCH;
    }
    if ( my ($chan, $mode) = $request =~ /^mode\s+(#.+)\s+(.+)\s*$/i ) {
    	last SWITCH unless $ircd->state_chan_exists( $chan );
    	$ircd->yield( 'daemon_cmd_mode', 'OperServ', $chan, $mode );
    	last SWITCH;
    }
    if ( my ($chan, $target) = $request =~ /^op\s+(#.+)\s+(.+)\s*$/i ) {
	last SWITCH unless $ircd->state_chan_exists( $chan );
	$ircd->daemon_server_mode( $chan, '+o', $target );
    }
  }
  return PCSI_EAT_NONE;
}

sub IRCD_daemon_join {
  my ($self,$ircd) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  return PCSI_EAT_NONE unless $ircd->state_user_is_operator( $nick )
  	&& $nick eq 'OperServ';
  my $channel = ${ $_[1] };
  return PCSI_EAT_NONE if $ircd->state_is_chan_op( $nick, $channel );
  $ircd->daemon_server_mode( $channel, '+o', $nick );
  return PCSI_EAT_NONE;
}

1;
__END__

=head1 NAME

POE::Component::Server::IRC::OperServ - a fully event-driven networkable IRC server daemon module with an OperServ.

=head1 SYNOPSIS

  # A fairly simple example:
  use strict;
  use warnings;
  use POE qw(Component::Server::IRC::OperServ);

  my %config = ( 
		servername => 'simple.poco.server.irc', 
		nicklen    => 15,
		network    => 'SimpleNET'
  );

  my $pocosi = POE::Component::Server::IRC::OperServ->spawn( config => \%config );

  POE::Session->create(
	package_states => [
	   'main' => [qw(_start _default)],
	],
	heap => { ircd => $pocosi },
  );

  $poe_kernel->run();
  exit 0;

  sub _start {
    my ($kernel,$heap) = @_[KERNEL,HEAP];
    $heap->{ircd}->yield( 'register' );
    # Anyone connecting from the loopback gets spoofed hostname
    $heap->{ircd}->add_auth( mask => '*@localhost', spoof => 'm33p.com', no_tilde => 1 );
    # We have to add an auth as we have specified one above.
    $heap->{ircd}->add_auth( mask => '*@*' );
    # Start a listener on the 'standard' IRC port.
    $heap->{ircd}->add_listener( port => 6667 );
    # Add an operator who can connect from localhost
    $heap->{ircd}->add_operator( { username => 'moo', password => 'fishdont' } );
    undef;
  }

  sub _default {
     my ( $event, $args ) = @_[ ARG0 .. $#_ ];
     print STDOUT "$event: ";
     foreach (@$args) {
     SWITCH: {
              if ( ref($_) eq 'ARRAY' ) {
                  print STDOUT "[", join ( ", ", @$_ ), "] ";
                  last SWITCH;
              }
              if ( ref($_) eq 'HASH' ) {
                  print STDOUT "{", join ( ", ", %$_ ), "} ";
                  last SWITCH;
              }
              print STDOUT "'$_' ";
          }
      }
      print STDOUT "\n";
      return 0;    # Don't handle signals.
  }

=head1 DESCRIPTION

POE::Component::Server::IRC::OperServ is subclass of L<POE::Component::Server::IRC> 
which provides simple operator services.

The documentation is the same as for L<POE::Component::Server::IRC>, consult that for usage.

=head1 OperServ

This subclass provides a server user called OperServ. OperServ accepts PRIVMSG commands from operators.

  /msg OperServ <command> <parameters>

The following commands are accepted:

=over

=item clear CHANNEL

The OperServ will remove all channel modes on the indicated channel, including all users' +ov flags. The timestamp
of the channel will be reset and the OperServ will join that channel with +o.

=item join CHANNEL

The OperServ will simply join the channel you specify with +o.

=item part CHANNEL

The OperServ will part (leave) the channel specified.

=item mode CHANNEL MODE

The OperServ will set the channel mode you tell it to. You can also remove the channel mode by prefixing
the mode with a '-' (minus) sign.

=item op CHANNEL USER

The OperServ will give +o to any user on a channel you specify. OperServ does not need to be in that channel (as this is mostly a server hack).

=back

Whenever the OperServ joins a channel (which you specify with the join command) it will automatically gain +o.

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 LICENSE

Copyright C<(c)> Chris Williams

This module may be used, modified, and distributed under the same terms as Perl itself. Please see the license that came with your Perl distribution for details.

=head1 SEE ALSO

L<POE::Component::Server::IRC>

=cut
