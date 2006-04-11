# $Id: State.pm,v 1.4 2005/04/28 14:18:20 chris Exp $
#
# POE::Component::IRC::Qnet::State, by Chris Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::IRC::Qnet::State;

use strict;
use warnings;
use Carp;
use POE::Component::IRC::Common qw(:ALL);
use POE::Component::IRC::Plugin qw(:ALL);
use vars qw($VERSION);
use base qw(POE::Component::IRC::Qnet POE::Component::IRC::State);

$VERSION = '1.4';

# Qnet extension to RPL_WHOIS
sub S_330 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick,$account) = ( split / /, ${ $_[1] } )[0..1];

  $self->{WHOIS}->{ $nick }->{account} = $account;
  return PCI_EAT_NONE;
}

# Qnet extension RPL_WHOEXT
sub S_354 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($first,$real) = split(/ :/,${ $_[1] });
  my ($query,$channel,$user,$host,$server,$nick,$status,$auth) = split(/ /,$first);
  
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Nick} = $nick;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{User} = $user;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Host} = $host;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Real} = $real;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Server} = $server;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Auth} = $auth if ( $auth );
  if ( $auth and defined ( $self->{USER_AUTHED}->{ u_irc ( $nick ) } ) ) {
	$self->{USER_AUTHED}->{ u_irc ( $nick ) } = $auth;
  }
  if ( $query eq '101' ) {
    my ($whatever) = '';
    if ( $status =~ /\@/ ) { $whatever .= 'o'; }
    if ( $status =~ /\+/ ) { $whatever .= 'v'; }
    if ( $status =~ /\%/ ) { $whatever .= 'h'; }
    $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{CHANS}->{ u_irc ( $channel ) } = $whatever;
    $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Name} = $channel;
    $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $nick ) } = $whatever;
  }
  if ( $status =~ /\*/ ) {
    $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{IRCop} = 1;
  }
  return PCI_EAT_NONE;
}

#RPL_ENDOFWHO
sub S_315 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($channel) = ( split / :/, ${ $_[1] } )[0];

  # If it begins with #, &, + or ! its a channel apparently. RFC2812.
  if ( $channel =~ /^[\x23\x2B\x21\x26]/ ) {
    $self->_channel_sync_who($channel);
    if ( $self->_channel_sync($channel) ) {
        delete ( $self->{CHANNEL_SYNCH}->{ u_irc ( $channel ) } );
        $self->_send_event( 'irc_chan_sync', $channel );
    }
  # Otherwise we assume its a nickname
  } else {
	if ( defined ( $self->{USER_AUTHED}->{ u_irc ( $channel ) } ) ) {
	   $self->_send_event( 'irc_nick_authed', $channel, delete ( $self->{USER_AUTHED}->{ u_irc ( $channel ) } ) );
	} else {
           $self->_send_event( 'irc_nick_sync', $channel );
	}
  }
  return PCI_EAT_NONE;
}

# Channel JOIN messages
sub S_join {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick) = ( split /!/, ${ $_[0] } )[0];
  my ($userhost) = ( split /!/, ${ $_[0] } )[1];
  my ($user,$host) = split(/\@/,$userhost);
  my $channel = ${ $_[1] };
  my $flags = '%cunharsft';

  if ( u_irc ( $nick ) eq u_irc ( $self->{RealNick} ) ) {
        delete ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) } );
        $self->{CHANNEL_SYNCH}->{ u_irc ( $channel ) } = { MODE => 0, WHO => 0 };
        $self->yield ( 'sl' => "WHO $channel $flags,101" );
        $self->yield ( 'mode' => $channel );
  } else {
        $self->yield ( 'sl' => "WHO $nick $flags,102" );
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Nick} = $nick;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{User} = $user;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Host} = $host;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{CHANS}->{ u_irc ( $channel ) } = '';
        $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $nick ) } = '';
  }
  return PCI_EAT_NONE;
}

# Channel MODE
sub S_mode {
  my ($self,$irc) = splice @_, 0, 2;
  my ($source) = u_irc ( ( split /!/, ${ $_[0] } )[0] );
  my $channel = ${ $_[1] };
  pop @_;

  # Do nothing if it is UMODE
  if ( u_irc ( $channel ) ne u_irc ( $self->{RealNick} ) ) {
     my ($parsed_mode) = parse_mode_line( @_[2 .. $#_] );
     while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
        my ($arg);
        $arg = shift ( @{ $parsed_mode->{args} } ) if ( $mode =~ /^(\+[hovklbIe]|-[hovbIe])/ );
        SWITCH: {
          if ( $mode =~ /\+([ohv])/ ) {
                my ($flag) = $1;
                unless ( $self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) } =~ $flag ) {
                	$self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) } .= $flag;
                	$self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $arg ) } = $self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) };
		}
		if ( $source =~ /^[QL]$/ and ( not $self->is_nick_authed($arg) ) and ( not $self->{USER_AUTHED}->{ u_irc ( $arg ) } ) ) {
		   $self->{USER_AUTHED}->{ u_irc ( $arg ) } = 0;
		   $self->yield ( 'sl' => "WHO $arg " . '%cunharsft,102' );
		}
                last SWITCH;
          }
          if ( $mode =~ /-([ohv])/ ) {
                my ($flag) = $1;
                $self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) } =~ s/$flag//;
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $arg ) } = $self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) };
                last SWITCH;
          }
          if ( $mode =~ /[bIe]/ ) {
                last SWITCH;
          }
          if ( $mode eq '+l' and defined ( $arg ) ) {
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} .= 'l' unless ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ /l/ );
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{ChanLimit} = $arg;
                last SWITCH;
          }
          if ( $mode eq '+k' and defined ( $arg ) ) {
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} .= 'k' unless ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ /k/ );
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{ChanKey} = $arg;
                last SWITCH;
          }
          if ( $mode eq '-l' ) {
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ s/l//;
                delete ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{ChanLimit} );
                last SWITCH;
          }
          if ( $mode eq '-k' ) {
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ s/k//;
                delete ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{ChanKey} );
                last SWITCH;
          }
          # Anything else doesn't have arguments so just adjust {Mode} as necessary.
          if ( $mode =~ /^\+(.)/ ) {
                my ($flag) = $1;
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} .= $flag unless ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ /$flag/ );
                last SWITCH;
          }
          if ( $mode =~ /^-(.)/ ) {
                my ($flag) = $1;
                $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ s/$flag//;
                last SWITCH;
          }
        }
     }
     # Lets make the channel mode nice
     if ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} ) {
        $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} = join('', sort( split( //, $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} ) ) );
     } else {
        delete $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode};
     }
  }
  return PCI_EAT_NONE;
}

sub is_nick_authed {
  my $self = shift;
  my $nick = u_irc ( $_[0] ) || return undef;

  return undef unless $self->_nick_exists($nick);

  if ( defined ( $self->{STATE}->{Nicks}->{ $nick }->{Auth} ) ) {
	return $self->{STATE}->{Nicks}->{ $nick }->{Auth};
  }
  return undef;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Qnet::State - a fully event-driven IRC client module for Quakenet,
with nickname and channel tracking from L<POE::Component::IRC::State|POE::Component::IRC::State>.

=head1 SYNOPSIS

  # A simple Rot13 'encryption' bot

  use strict;
  use warnings;
  use POE qw(Component::IRC::Qnet::State);

  my $nickname = 'Flibble' . $$;
  my $ircname = 'Flibble the Sailor Bot';
  my $ircserver = 'irc.blahblahblah.irc';
  my $port = 6667;
  my $qauth = 'FlibbleBOT';
  my $qpass = 'fubar';

  my @channels = ( '#Blah', '#Foo', '#Bar' );

  # We create a new PoCo-IRC object and component.
  my $irc = POE::Component::IRC::Qnet::State->spawn( 
        nick => $nickname,
        server => $ircserver,
        port => $port,
        ircname => $ircname,
  ) or die "Oh noooo! $!";

  POE::Session->create(
        package_states => [
                'main' => [ qw(_default _start irc_001 irc_public) ],
        ],
        heap => { irc => $irc },
  );

  $poe_kernel->run();
  exit 0;

  sub _start {
    my ($kernel,$heap) = @_[KERNEL,HEAP];

    # We get the session ID of the component from the object
    # and register and connect to the specified server.
    my $irc_session = $heap->{irc}->session_id();
    $kernel->post( $irc_session => register => 'all' );
    $kernel->post( $irc_session => connect => { } );
    undef;
  }

  sub irc_001 {
    my ($kernel,$sender) = @_[KERNEL,SENDER];

    # Get the component's object at any time by accessing the heap of
    # the SENDER
    my $poco_object = $sender->get_heap();
    print "Connected to ", $poco_object->server_name(), "\n";

    # Lets authenticate with Quakenet's Q bot
    $kernel->post( $sender => qbot_auth => $qauth => $qpass );

    # In any irc_* events SENDER will be the PoCo-IRC session
    $kernel->post( $sender => join => $_ ) for @channels;
    undef;
  }

  sub irc_public {
    my ($kernel,$sender,$who,$where,$what) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    if ( my ($rot13) = $what =~ /^rot13 (.+)/ ) {
        # Only operators can issue a rot13 command to us.
        return unless $poco_object->is_channel_operator( $channel, $nick );

        $rot13 =~ tr[a-zA-Z][n-za-mN-ZA-M];
        $kernel->post( $sender => privmsg => $channel => "$nick: $rot13" );
    }
    undef;
  }

  # We registered for all events, this will produce some debug info.
  sub _default {
    my ($event, $args) = @_[ARG0 .. $#_];
    my @output = ( "$event: " );

    foreach my $arg ( @$args ) {
        if ( ref($arg) eq 'ARRAY' ) {
                push( @output, "[" . join(" ,", @$arg ) . "]" );
        } else {
                push ( @output, "'$arg'" );
        }
    }
    print STDOUT join ' ', @output, "\n";
    return 0;
  }


=head1 DESCRIPTION

POE::Component::IRC::Qnet::State is an extension to L<POE::Component::IRC::Qnet|POE::Component::IRC::Qnet>
specifically for use on Quakenet L<http://www.quakenet.org/>, which includes the nickname and channel tracking
from L<POE::Component::IRC::State|POE::Component::IRC::State>. See the documentation for
L<POE::Component::IRC::Qnet|POE::Component::IRC::Qnet> and L<POE::Component::IRC::State|POE::Component::IRC::State> for general usage. This document covers the extensions.

=head1 METHODS

=over

=item is_nick_authed

Expects a nickname as parameter. Will return that users authname ( account ) if that nick is in the state 
and have authed with Q. Returns undef if the user is not authed or the nick doesn't exist in the state.

=item nick_info

Expects a nickname. Returns a hashref containing similar information to that returned by WHOIS. Returns an undef
if the nickname doesn't exist in the state. The hashref contains the following keys: 'Nick', 'User', 'Host', 'Se
rver', 'Auth', if authed, and, if applicable, 'IRCop'.

=back

=head1 OUTPUT

This module returns one additional event over and above the usual events:

=over

=item irc_nick_authed

Sent when the component detects that a user has authed with Q. Due to the mechanics of Quakenet you will
usually only receive this if an unauthed user joins a channel, then at some later point auths with Q. The
component 'detects' the auth by seeing if Q or L decides to +v or +o the user. Klunky? Indeed. But it is the
only way to do it, unfortunately.

=back

=head1 CAVEATS

Like L<POE::Component::IRC::State|POE::Component::IRC::State> this component registers itself for
a number of events. The main difference with L<POE::Component::IRC::State|POE::Component::IRC::State> is
that it uses an extended form of 'WHO' supported by the Quakenet ircd, asuka. This WHO returns a different
numeric reply than the original WHO, namely, 'irc_354'. Also, due to the way Quakenet is configured all users
will appear to be on the server '*.quakenet.org'.

=head1 BUGS

A few have turned up in the past and they are sure to again. Please use
L<http://rt.cpan.org/> to report any. Alternatively, email the current maintainer.

=head1 AUTHOR

Chris 'BinGOs' Williams E<lt>chris@bingosnet.co.ukE<gt>

Based on the original POE::Component::IRC by:

Dennis Taylor, E<lt>dennis@funkplanet.comE<gt>

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>
L<POE::Component::IRC::State|POE::Component::IRC::State>
L<POE::Component::IRC::Qnet|POE::Component::IRC::Qnet>
L<http://www.quakenet.org/>

=cut
