# $Id: Qnet.pm,v 1.2 2005/04/24 10:31:28 chris Exp $
#
# POE::Component::IRC::Qnet, by Chris Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::IRC::Qnet;

use strict;
use Carp;
use POE;
use POE::Component::IRC::Plugin::Whois;
use POE::Component::IRC::Constants;
use vars qw($VERSION);
use base qw(POE::Component::IRC);

$VERSION = '1.1';

my ($GOT_SSL);
my ($GOT_CLIENT_DNS);

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

  $self->{IRC_EVTS} = [ qw(nick ping) ];

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

sub qnet_bot_commands {
  my ($kernel, $state, $self) = @_[KERNEL,STATE,OBJECT];
  my $message = join ' ', @_[ARG0 .. $#_];
  my $pri = $self->{IRC_CMDS}->{'privmsghi'}->[CMD_PRI];
  my $command = "PRIVMSG ";

  my ($target,$cmd) = split(/_/,$state);

  SWITCH: {
    if ( uc ( $target ) eq 'QBOT' ) {
	$command .= join(' :',$self->{QBOT},uc($cmd));
	last SWITCH;
    }
    $command .= join(' :',$self->{LBOT},uc($cmd));
  }
  $command = join(' ',$command,$message) if ( defined ( $message ) );
  $kernel->yield( 'sl_prioritized', $pri, $command );
}

sub service_bots {
  my ($self) = shift;
  croak "Method requires an even number of parameters" if @_ % 2;

  my (%args) = @_;

  foreach my $botname ( qw(QBOT LBOT) ) {
	if ( defined ( $args{$botname} ) ) {
		$self->{$botname} = $args{$botname};
	}
  }
  return 1;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Qnet - a fully event-driven IRC client module for Quakenet.

=head1 SYNOPSIS

  use POE::Component::IRC::Qnet;

  # Do this when you create your sessions. 'my client' is just a
  # kernel alias to christen the new IRC connection with.
  my ($object) = POE::Component::IRC::Qnet->new('my client') or die "Oh noooo! $!";

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

POE::Component::IRC::Qnet is an extension to L<POE::Component::IRC|POE::Component::IRC>
specifically for use on Quakenet L<http://www.quakenet.org/>. See the documentation for
L<POE::Component::IRC|POE::Component::IRC> for general usage. This document covers the 
extensions.

The module provides a number of additional commands for communicating with the Quakenet
service bots, Q and L.

=head1 METHODS

=over

=item service_bots

The component will query Q and L using their default names on Quakenet. If you wish to
override these settings, use this method to configure them. 

$self->service_bots( QBOT => 'W@blah.network.net', LBOT => 'Z@blah.network.net' );

In most cases you shouldn't need to mess with these >;o)

=back

=head1 INPUT

The Quakenet service bots accept input as PRIVMSG. This module provides a wrapper around
the L<POE::Component::IRC|POE::Component::IRC> "privmsg" command.

=over

=item qbot_* 

Send commands to the Q bot. Pass additional command parameters as arguments to the event.

$kernel->post ( 'my client' => qbot_auth => $q_user => $q_pass );

=item lbot_*

Send commands to the L bot. Pass additional command parameters as arguments to the event.

$kernel->post ( 'my client' => lbot_chanlev => $channel );

=back

=head1 OUTPUT

All output from the Quakenet service bots is sent as NOTICEs. Use 'irc_notice' to trap these.

=over

=item irc_whois

Has all the same hash keys in ARG1 as L<POE::Component::IRC|POE::Component::IRC>, with the
addition of 'account', which contains the name of their Q auth account, if they have authed, or 
undef if they haven't.

=back

=head1 BUGS

A few have turned up in the past and they are sure to again. Please use
L<http://rt.cpan.org/> to report any. Alternatively, email the current maintainer.

=head1 AUTHOR

Chris 'BinGOs' Williams E<lt>chris@bingosnet.co.ukE<gt>

Based on the original POE::Component::IRC by:

Dennis Taylor, E<lt>dennis@funkplanet.comE<gt>

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>
L<http://www.quakenet.org/>

=cut
