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
use Carp;
use POE qw(Component::IRC::Plugin::Whois);
use POE::Component::IRC::Constants;
use POE::Component::IRC::Common qw(:ALL);
use vars qw($VERSION);
use base qw(POE::Component::IRC::Qnet POE::Component::IRC::State);

$VERSION = '1.3';

my ($GOT_CLIENT_DNS);
my ($GOT_SSL);

BEGIN {
    $GOT_CLIENT_DNS = 0;
    eval {
      require POE::Component::Client::DNS;
      $GOT_CLIENT_DNS = 1;
    };
}

BEGIN {
    $GOT_SSL = 0;
    eval {
      require POE::Component::SSLify;
      import POE::Component::SSLify qw( Client_SSLify );
      $GOT_SSL = 1;
    };
}

sub _create {
  my ($package) = shift;

  my $self = bless ( { }, $package );

  if ( $GOT_CLIENT_DNS ) {
    POE::Component::Client::DNS->spawn( Alias => "irc_resolver" );
  }

  $self->{IRC_CMDS} =
  { 'rehash'    => [ PRI_HIGH,   'noargs',        ],
    'restart'   => [ PRI_HIGH,   'noargs',        ],
    'quit'      => [ PRI_NORMAL, 'oneoptarg',     ],
    'version'   => [ PRI_HIGH,   'oneoptarg',     ],
    'time'      => [ PRI_HIGH,   'oneoptarg',     ],
    'trace'     => [ PRI_HIGH,   'oneoptarg',     ],
    'admin'     => [ PRI_HIGH,   'oneoptarg',     ],
    'info'      => [ PRI_HIGH,   'oneoptarg',     ],
    'away'      => [ PRI_HIGH,   'oneoptarg',     ],
    'users'     => [ PRI_HIGH,   'oneoptarg',     ],
    'locops'    => [ PRI_HIGH,   'oneoptarg',     ],
    'operwall'  => [ PRI_HIGH,   'oneoptarg',     ],
    'wallops'   => [ PRI_HIGH,   'oneoptarg',     ],
    'motd'      => [ PRI_HIGH,   'oneoptarg',     ],
    'who'       => [ PRI_HIGH,   'oneoptarg',     ],
    'nick'      => [ PRI_HIGH,   'onlyonearg',    ],
    'oper'      => [ PRI_HIGH,   'onlytwoargs',   ],
    'invite'    => [ PRI_HIGH,   'onlytwoargs',   ],
    'squit'     => [ PRI_HIGH,   'onlytwoargs',   ],
    'kill'      => [ PRI_HIGH,   'onlytwoargs',   ],
    'privmsg'   => [ PRI_NORMAL, 'privandnotice', ],
    'privmsglo' => [ PRI_NORMAL+1, 'privandnotice', ],
    'privmsghi' => [ PRI_NORMAL-1, 'privandnotice', ],
    'notice'    => [ PRI_NORMAL, 'privandnotice', ],
    'noticelo'  => [ PRI_NORMAL+1, 'privandnotice', ],   
    'noticehi'  => [ PRI_NORMAL-1, 'privandnotice', ],   
    'join'      => [ PRI_HIGH,   'oneortwo',      ],
    'summon'    => [ PRI_HIGH,   'oneortwo',      ],
    'sconnect'  => [ PRI_HIGH,   'oneandtwoopt',  ],
    'whowas'    => [ PRI_HIGH,   'oneandtwoopt',  ],
    'stats'     => [ PRI_HIGH,   'spacesep',      ],
    'links'     => [ PRI_HIGH,   'spacesep',      ],
    'mode'      => [ PRI_HIGH,   'spacesep',      ],
    'part'      => [ PRI_HIGH,   'commasep',      ],
    'names'     => [ PRI_HIGH,   'commasep',      ],
    'list'      => [ PRI_HIGH,   'commasep',      ],
    'whois'     => [ PRI_HIGH,   'commasep',      ],
    'ctcp'      => [ PRI_HIGH,   'ctcp',          ],
    'ctcpreply' => [ PRI_HIGH,   'ctcp',          ],
    'ping'      => [ PRI_HIGH,   'oneortwo',      ],
    'pong'      => [ PRI_HIGH,   'oneortwo',      ],
  };

  $self->{IRC_EVTS} = [ qw(001 ping join part kick nick mode quit 354 324 315 disconnected socketerr error) ];

  my (@event_map) = map {($_, $self->{IRC_CMDS}->{$_}->[CMD_SUB])} keys %{ $self->{IRC_CMDS} };

  $self->{OBJECT_STATES_ARRAYREF} = [qw( _dcc_failed
				      _dcc_read
				      _dcc_timeout
				      _dcc_up
				      _parseline
				      __send_event
				      _sock_down
				      _sock_failed
				      _sock_up
				      _start
				      _stop
				      debug
				      connect
				      dcc
				      dcc_accept
				      dcc_resume
				      dcc_chat
				      dcc_close
				      do_connect
				      got_dns_response
				      ison
				      kick
				      register
				      shutdown
				      sl
				      sl_login
				      sl_high
                                      sl_delayed
				      sl_prioritized
				      topic
				      unregister
				      userhost ), ( map {( 'irc_' . $_ )} @{ $self->{IRC_EVTS} } ) ];


  # Stuff specific to IRC-Qnet

  my @qbot_commands = qw(
        hello
        whoami
        challengeauth
        showcommands
        auth
        challenge
        help
        unlock
        requestpassword
        reset
        newpass
        email
        authhistory
        banclear
        op
        invite
        removeuser
        banlist
        recover
        limit
        unbanall
        whois
        version
        autolimit
        ban
        clearchan
        adduser
        settopic
        chanflags
        deopall
        requestowner
        bandel
        chanlev
        key
        welcome
        voice
        );

  my @lbot_commands = qw(
        whoami
        whois
        chanlev
        adduser
        removeuser
        showcommands
        op
        voice
        invite
        setinvite
        clearinvite
        recover
        deopall
        unbanall
        clearchan
        version
        welcome
        requestowner
        );

  my @qbot_map = map {('qbot_' . $_, 'qnet_bot_commands')} @qbot_commands;
  my @lbot_map = map {('lbot_' . $_, 'qnet_bot_commands')} @lbot_commands;

  $self->{OBJECT_STATES_HASHREF} = { @event_map, @qbot_map, @lbot_map, '_tryclose' => 'dcc_close' };

  $self->{server} = 'irc.quakenet.org';
  $self->{QBOT} = 'Q@Cserve.quakenet.org';
  $self->{LBOT} = 'L@lightweight.quakenet.org';

  return $self;
}

sub _parseline {
  my ($session, $self, $ev) = @_[SESSION, OBJECT, ARG0];
  my (@events, @cooked);

  $self->_send_event( 'irc_raw' => $ev->{raw_line} ) if ( $self->{raw_events} );

  # If its 001 event grab the server name and stuff it into {INFO}
  if ( $ev->{name} eq '001' ) {
        $self->{INFO}->{ServerName} = $ev->{args}->[0];
        $self->{RealNick} = ( split / /, $ev->{raw_line} )[2];
  }
  if ( $ev->{name} eq 'nick' or $ev->{name} eq 'quit' ) {
        push ( @{$ev->{args}}, [ $self->nick_channels( ( split( /!/, $ev->{args}->[0] ) )[0] ) ] );
  }
  $ev->{name} = 'irc_' . $ev->{name};
  $self->_send_event( $ev->{name}, @{$ev->{args}} );
  undef;
}

# Qnet extension to RPL_WHOIS
sub irc_330 {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  my ($nick,$account) = ( split / /, $_[ARG1] )[0..1];

  $self->{WHOIS}->{ $nick }->{account} = $account;
  undef;
}

# Qnet extension RPL_WHOEXT
sub irc_354 {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  my ($first,$real) = split(/ :/,$_[ARG1]);
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
  undef;
}

#RPL_ENDOFWHO
sub irc_315 {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  my ($channel) = ( split / :/, $_[ARG1] )[0];

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
  undef;
}

# Channel JOIN messages
sub irc_join {
  my ($kernel,$self,$who,$channel) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my ($nick) = ( split /!/, $who )[0];
  my ($userhost) = ( split /!/, $who )[1];
  my ($user,$host) = split(/\@/,$userhost);
  my ($flags) = '%cunharsft';

  if ( u_irc ( $nick ) eq u_irc ( $self->{RealNick} ) ) {
        delete ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) } );
        $self->{CHANNEL_SYNCH}->{ u_irc ( $channel ) } = { MODE => 0, WHO => 0 };
        $kernel->yield ( 'sl' => "WHO $channel $flags,101" );
        $kernel->yield ( 'mode' => $channel );
  } else {
        $kernel->yield ( 'sl' => "WHO $nick $flags,102" );
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Nick} = $nick;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{User} = $user;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Host} = $host;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{CHANS}->{ u_irc ( $channel ) } = '';
        $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $nick ) } = '';
  }
  undef;
}

# Channel MODE
sub irc_mode {
  my ($kernel,$self,$who,$channel) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my ($source) = u_irc ( ( split /!/, $who )[0] );

  # Do nothing if it is UMODE
  if ( u_irc ( $channel ) ne u_irc ( $self->{RealNick} ) ) {
     my ($parsed_mode) = parse_mode_line( @_[ARG2 .. $#_] );
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
		   $kernel->yield ( 'sl' => "WHO $arg " . '%cunharsft,102' );
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
        delete ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} );
     }
  }
  undef;
}

sub is_nick_authed {
  my ($self) = shift;
  my ($nick) = u_irc ( $_[0] ) || return undef;

  unless ( $self->_nick_exists($nick) ) {
	return undef;
  }

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

  use POE::Component::IRC::Qnet::State;

  # Do this when you create your sessions. 'my client' is just a
  # kernel alias to christen the new IRC connection with.
  my ($object) = POE::Component::IRC::Qnet::State->new('my client') or die "Oh noooo! $!";

  # Do stuff like this from within your sessions. This line tells the
  # connection named "my client" to send your session the following
  # events when they happen.
  $kernel->post('my client', 'register', qw(connected msg public cdcc cping));
  # You can guess what this line does.
  $kernel->post('my client', 'connect',
	        { Nick     => 'Boolahman',
		  Server   => 'irc-w.primenet.com',
		  Port     => 6669,
		  Username => 'quetzal',
		  Ircname  => 'Ask me about my colon!', } );

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
