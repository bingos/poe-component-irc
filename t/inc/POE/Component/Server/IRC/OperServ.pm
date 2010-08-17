package POE::Component::Server::IRC::OperServ;

use strict;
use warnings FATAL => 'all';
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
