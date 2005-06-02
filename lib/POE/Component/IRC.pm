# $Id: IRC.pm,v 1.4 2005/04/24 10:31:28 chris Exp $
#
# POE::Component::IRC, by Dennis Taylor <dennis@funkplanet.com>
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::IRC;

use strict;
use POE qw( Wheel::SocketFactory Wheel::ReadWrite Driver::SysRW
	    Filter::Line Filter::Stream );
use POE::Filter::IRC;
use POE::Filter::CTCP;
use POE::Component::IRC::Plugin::Whois;
use POE::Component::IRC::Constants;
use Carp;
use Socket;
use Sys::Hostname;
use File::Basename ();
use Symbol;
use vars qw($VERSION $REVISION $GOT_SSL $GOT_CLIENT_DNS);

# Load the plugin stuff
use POE::Component::IRC::Plugin qw( :ALL );

$VERSION = '4.61';
$REVISION = do {my@r=(q$Revision: 1.4 $=~/\d+/g);sprintf"%d."."%04d"x$#r,@r};

# BINGOS: I have bundled up all the stuff that needs changing for inherited classes
# 	  into _create. This gets called from 'spawn'.
#	  $self->{OBJECT_STATES_ARRAYREF} contains event mappings to methods that have
#		the same name, gets passed to POE::Session->create as $self => [ ];
#	  $self->{OBJECT_STATES_HASHREF} contains event mappings to methods, where the
#		event and the method have diferent names.
#	  $self->{IRC_EVTS} is an array of IRC events that the component will register to
#		receive from itself. Should be specified without the 'irc_' prefix.
#	  $self->{IRC_CMDS} contains the traditional %irc_commands, mapping commands to events
#		and the priority that the command has.

my ($GOT_SSL);
my ($GOT_CLIENT_DNS);

# Check for SSL availability
BEGIN {
	$GOT_SSL = 0;
	eval {
		require POE::Component::SSLify;
		import POE::Component::SSLify qw( Client_SSLify );
		$GOT_SSL = 1;
	};
}

# Check for Client::DNS availability
BEGIN {
	$GOT_CLIENT_DNS = 0;
	eval {
		require POE::Component::Client::DNS;
		$GOT_CLIENT_DNS = 1;
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
				      register_session
				      shutdown
				      sl
				      sl_login
				      sl_high
                                      sl_delayed
				      sl_prioritized
				      topic
				      unregister
				      unregister_sessions
				      userhost ), ( map {( 'irc_' . $_ )} @{ $self->{IRC_EVTS} } ) ];

  $self->{OBJECT_STATES_HASHREF} = { @event_map, '_tryclose' => 'dcc_close' };

  return $self;
}

# BINGOS: the component can now get its configuration from either spawn() or connect()
#	  _configure() deals with this.

sub _configure {
  my ($self) = shift;

  my ($spawned) = 0;

  my ($args) = shift;

  if ( defined ( $args ) and ref $args eq 'HASH' ) {
    my (%arg) = %$args;

    if (exists $arg{'flood'} and $arg{'flood'}) {
      $self->{'dont_flood'} = 0;
    } else {
      $self->{'dont_flood'} = 1;
    }

    if (exists $arg{'raw'} and $arg{'raw'}) {
      $self->{'raw_events'} = 1;
    } else {
      $self->{'raw_events'} = 0;
    }

    if (exists $arg{'partfix'} and ( not $arg{'partfix'} ) ) {
      $self->{'dont_partfix'} = 1;
    } else {
      $self->{'dont_partfix'} = 0;
    }

    $self->{'password'} = $arg{'password'} if exists $arg{'password'};
    $self->{'localaddr'} = $arg{'localaddr'} if exists $arg{'localaddr'};
    $self->{'localport'} = $arg{'localport'} if exists $arg{'localport'};
    $self->{'nick'} = $arg{'nick'} if exists $arg{'nick'};
    $self->{'port'} = $arg{'port'} if exists $arg{'port'};
    $self->{'server'} = $arg{'server'} if exists $arg{'server'};
    $self->{'proxy'} = $arg{'proxy'} if exists $arg{'proxy'};
    $self->{'proxyport'} = $arg{'proxyport'} if exists $arg{'proxyport'};
    $self->{'ircname'} = $arg{'ircname'} if exists $arg{'ircname'};
    $self->{'username'} = $arg{'username'} if exists $arg{'username'};
    $self->{'NoDNS'} = $arg{'nodns'} if exists $arg{'nodns'};
    $self->{'nat_addr'} = $arg{'nataddr'} if exists $arg{'nataddr'};
    $self->{'user_bitmode'} = $arg{'bitmode'} if exists $arg{'bitmode'};
    if (exists $arg{'debug'}) {
      $self->{'debug'} = $arg{'debug'};
      $self->{irc_filter}->debug( $arg{'debug'} );
      $self->{ctcp_filter}->debug( $arg{'debug'} );
    }
    my ($dccport) = delete ( $arg{'dccports'} );
    $self->{'UseSSL'} = $arg{'usessl'} if exists $arg{'usessl'};

    if ( defined ( $dccport ) and ref ( $dccport ) eq 'ARRAY' ) {
	  $self->{dcc_bind_port} = $dccport;
    }

    # This is a hack to make sure that the component doesn't die if no IRCServer is
    # specified as the result of being called from new() via spawn().

    $spawned = $arg{'CALLED_FROM_SPAWN'} if exists $arg{'CALLED_FROM_SPAWN'};
  }

  # Make sure that we have reasonable defaults for all the attributes.
  # The "IRC*" variables are ircII environment variables.
  $self->{'nick'} = $ENV{IRCNICK} || eval { scalar getpwuid($>) } ||
    $ENV{USER} || $ENV{LOGNAME} || "WankerBot"
      unless ($self->{'nick'});
  $self->{'username'} = eval { scalar getpwuid($>) } || $ENV{USER} ||
    $ENV{LOGNAME} || "foolio"
      unless ($self->{'username'});
  $self->{'ircname'} = $ENV{IRCNAME} || eval { (getpwuid $>)[6] } ||
    "Just Another Perl Hacker"
      unless ($self->{'ircname'});
  unless ($self->{'server'}) {
    die "No IRC server specified" unless $ENV{IRCSERVER} or $spawned;
    $self->{'server'} = $ENV{IRCSERVER};
  }
  $self->{'port'} = 6667 unless $self->{'port'};
  if ($self->{localaddr} and $self->{localport}) {
    $self->{localaddr} .= ":" . $self->{localport};
  }
}

# What happens when an attempted DCC connection fails.
sub _dcc_failed {
  my ($self, $operation, $errnum, $errstr, $id) =
    @_[OBJECT, ARG0 .. ARG3];

  unless (exists $self->{dcc}->{$id}) {
    if (exists $self->{wheelmap}->{$id}) {
      $id = $self->{wheelmap}->{$id};
    } else {
      warn "_dcc_failed: Unknown wheel ID: $id";
      return;
    }
  }

  # Reclaim our port if necessary.
  if ( $self->{dcc}->{$id}->{listener} and $self->{dcc_bind_port} and $self->{dcc}->{$id}->{listenport} ) {
	push ( @{ $self->{dcc_bind_port} }, $self->{dcc}->{$id}->{listenport} );
  }

  # Did the peer of a DCC GET connection close the socket after the file
  # transfer finished? If so, it's not really an error.
  if ($errnum == 0 and
  $self->{dcc}->{$id}->{type} eq "GET" and
  $self->{dcc}->{$id}->{done} >= $self->{dcc}->{$id}->{size}) {
    $self->_send_event( 'irc_dcc_done', $id,
    @{$self->{dcc}->{$id}}{ qw(nick type port file size done listenport clientaddr) } );
    close $self->{dcc}->{$id}->{fh};
    delete $self->{wheelmap}->{$self->{dcc}->{$id}->{wheel}->ID};
    delete $self->{dcc}->{$id}->{wheel};
    delete $self->{dcc}->{$id};
  }

  elsif ($errnum == 0 and
  $self->{dcc}->{$id}->{type} eq "CHAT") {
    $self->_send_event( 'irc_dcc_done', $id,
    @{$self->{dcc}->{$id}}{ qw(nick type port file size done listenport clientaddr) } );
    close $self->{dcc}->{$id}->{fh};
    delete $self->{wheelmap}->{$self->{dcc}->{$id}->{wheel}->ID};
    delete $self->{dcc}->{$id}->{wheel};
    delete $self->{dcc}->{$id};
  }

  else {
    # In this case, something went wrong.
    if ($errnum == 0 and $self->{dcc}->{$id}->{type} eq "GET") {
      $errstr = "Aborted by sender";
    }
    else {
      if ($errstr) {
        $errstr = "$operation error $errnum: $errstr";
      }
      else {
        $errstr = "$operation error $errnum";
      }
    }
    $self->_send_event( 'irc_dcc_error', $id, $errstr,
		 @{$self->{dcc}->{$id}}{qw(nick type port file size done listenport clientaddr)} );
    # gotta close the file
    close $self->{dcc}->{$id}->{fh} if exists $self->{dcc}->{$id}->{fh};
    if (exists $self->{dcc}->{$id}->{wheel}) {
      delete $self->{wheelmap}->{$self->{dcc}->{$id}->{wheel}->ID};
      delete $self->{dcc}->{$id}->{wheel};
    }
    delete $self->{dcc}->{$id};
  }
}

sub debug {
    my ( $self, $switch ) = @_[ OBJECT, ARG0 ];

    if ($switch eq "on") {
        $switch = 1;
    } elsif ($switch eq "off") {
        $switch = 0;
    }

    $self->{debug} = $switch;
    $self->{irc_filter}->debug( $switch );
    $self->{ctcp_filter}->debug( $switch );
}


# Accept incoming data on a DCC socket.
sub _dcc_read {
  my ($self, $data, $id) = @_[OBJECT, ARG0, ARG1];

  $id = $self->{wheelmap}->{$id};

  if ($self->{dcc}->{$id}->{type} eq "GET") {

    # Acknowledge the received data.
    print {$self->{dcc}->{$id}->{fh}} $data;
    $self->{dcc}->{$id}->{done} += length $data;
    $self->{dcc}->{$id}->{wheel}->put( pack "N", $self->{dcc}->{$id}->{done} );

    # Send an event to let people know about the newly arrived data.
    $self->_send_event( 'irc_dcc_get', $id,
		 @{$self->{dcc}->{$id}}{ qw(nick port file size done listenport clientaddr) } );


  } elsif ($self->{dcc}->{$id}->{type} eq "SEND") {

    # Record the client's download progress.
    $self->{dcc}->{$id}->{done} = unpack "N", substr( $data, -4 );
    $self->_send_event( 'irc_dcc_send', $id,
		 @{$self->{dcc}->{$id}}{ qw(nick port file size done listenport clientaddr) } );

    # Are we done yet?
    if ($self->{dcc}->{$id}->{done} >= $self->{dcc}->{$id}->{size}) {

      # Reclaim our port if necessary.
      if ( $self->{dcc}->{$id}->{listener} and $self->{dcc_bind_port} and $self->{dcc}->{$id}->{listenport} ) {
        push ( @{ $self->{dcc_bind_port} }, $self->{dcc}->{$id}->{listenport} );
      }

      $self->_send_event( 'irc_dcc_done', $id,
		   @{$self->{dcc}->{$id}}{ qw(nick type port file size done listenport clientaddr) }
		 );
      delete $self->{wheelmap}->{$self->{dcc}->{$id}->{wheel}->ID};
      delete $self->{dcc}->{$id}->{wheel};
      delete $self->{dcc}->{$id};
      return;
    }

    # Send the next 'blocksize'-sized packet.
    read $self->{dcc}->{$id}->{fh}, $data, $self->{dcc}->{$id}->{blocksize};
    $self->{dcc}->{$id}->{wheel}->put( $data );

  }
  else {
    $self->_send_event( 'irc_dcc_' . lc $self->{dcc}->{$id}->{type},
		 $id, @{$self->{dcc}->{$id}}{'nick', 'port'}, $data );
  }
}


# What happens when a DCC connection sits waiting for the other end to
# pick up the phone for too long.
sub _dcc_timeout {
  my ($kernel, $self, $id) = @_[KERNEL, OBJECT, ARG0];

  if (exists $self->{dcc}->{$id} and not $self->{dcc}->{$id}->{open}) {
    $kernel->yield( '_dcc_failed', 'connection', 0,
		    'DCC connection timed out', $id );
  }
}


# This event occurs when a DCC connection is established.
sub _dcc_up {
  my ($kernel, $self, $sock, $addr, $port, $id) =
    @_[KERNEL, OBJECT, ARG0 .. ARG3];

  my $buf = '';

  # Monitor the new socket for incoming data and delete the listening socket.
  delete $self->{dcc}->{$id}->{factory};
  $self->{dcc}->{$id}->{addr} = $addr;
  $self->{dcc}->{$id}->{clientaddr} = inet_ntoa($addr);
  $self->{dcc}->{$id}->{port} = $port;
  $self->{dcc}->{$id}->{open} = 1;
  #bboett: -second step - the connection per DCC is opened, following the protocol we have to send a PRIVMSG User1 :DCC RESUME filename port position
  #set the correct filter....
  my $actualFilter = "";
  if($self->{dcc}->{$id}->{type} eq "CHAT" )
  {
    $actualFilter = POE::Filter::Line->new( Literal => "\012" );
  }# if("CHAT")
  else
  {
    #assume filetrasnfer
    $actualFilter = POE::Filter::Stream->new() ;
  }# else
  #->bboett
  $self->{dcc}->{$id}->{wheel} = POE::Wheel::ReadWrite->new(
      Handle => $sock,
      Driver => ($self->{dcc}->{$id}->{type} eq "GET" ?
		   POE::Driver::SysRW->new( BlockSize => INCOMING_BLOCKSIZE ) :
		   POE::Driver::SysRW->new() ),
#Filter => ($self->{dcc}->{$id}->{type} eq "CHAT" ?
#	       POE::Filter::Line->new( Literal => "\012" ) :
#	       POE::Filter::Stream->new() ),
      Filter => $actualFilter, #bboett
      InputEvent => '_dcc_read',
      ErrorEvent => '_dcc_failed',
  );
  $self->{wheelmap}->{$self->{dcc}->{$id}->{wheel}->ID} = $id;

  if ($self->{dcc}->{$id}->{'type'} eq 'GET') {
    my $handle = gensym();
    #bboett: added a check if the size is !=0 we suppose a resume
    if(-s $self->{dcc}->{$id}->{file})
    {
      unless (open $handle, ">>" . $self->{dcc}->{$id}->{file})
      {
	$kernel->yield( '_dcc_failed', 'open file', $! + 0, "$!", $id );
	return;
      }# unless (open $handle, ">>" . $self->{dcc}->{$id}->{file})
    }# if(-s $self->{dcc}->{$id}->{file})
    else
    {
      unless (open $handle, ">" . $self->{dcc}->{$id}->{file}) {
	$kernel->yield( '_dcc_failed', 'open file', $! + 0, "$!", $id );
	return;
      }
    }
    binmode $handle;

    # Store the filehandle with the rest of this connection's state.
    $self->{dcc}->{$id}->{'fh'} = $handle;

  }
  elsif ($self->{dcc}->{$id}->{type} eq 'SEND') {
    # Open up the file we're going to send.
    my $handle = gensym();
    unless (open $handle, "<" . $self->{dcc}->{$id}->{'file'}) {
      $kernel->yield( '_dcc_failed', 'open file', $! + 0, "$!", $id );
      return;
    }
    binmode $handle;

    # Send the first packet to get the ball rolling.
    read $handle, $buf, $self->{dcc}->{$id}->{'blocksize'};
    $self->{dcc}->{$id}->{wheel}->put( $buf );

    # Store the filehandle with the rest of this connection's state.
    $self->{dcc}->{$id}->{'fh'} = $handle;
  }

  # Tell any listening sessions that the connection is up.
  $self->_send_event( 'irc_dcc_start',
	       $id, @{$self->{dcc}->{$id}}{'nick', 'type', 'port'},
	       ($self->{dcc}->{$id}->{'type'} =~ /^(SEND|GET)$/ ?
		(@{$self->{dcc}->{$id}}{'file', 'size'}) : ()), @{$self->{dcc}->{$id}}{'listenport', 'clientaddr'} );
}


# Parse a message from the IRC server and generate the appropriate
# event(s) for listening sessions.
sub _parseline {
  my ($session, $self, $line) = @_[SESSION, OBJECT, ARG0];
  my (@events, @cooked);

  $self->_send_event( 'irc_raw' => $line ) if ( $self->{raw_events} );

  # Feed the proper Filter object the raw IRC text and get the
  # "cooked" events back for sending, then deliver each event. We
  # handle CTCPs separately from normal IRC messages here, to avoid
  # silly module dependencies later.

  @cooked = ($line =~ tr/\001// ? @{$self->{ctcp_filter}->get( [$line] )}
	     : @{$self->{irc_filter}->get( [$line] )} );

  foreach my $ev (@cooked) {
    if ( $ev->{name} eq 'part' and not $self->{'dont_partfix'} ) {
	(@{$ev->{args}}[1..2]) = split(/ /,$ev->{args}->[1],2);
	$ev->{args}->[2] =~ s/^:// if ( defined ( $ev->{args}->[2] ) );
    }
    # If its 001 event grab the server name and stuff it into {INFO}
    if ( $ev->{name} eq '001' ) {
	$self->{INFO}->{ServerName} = $ev->{args}->[0];
	# Kind of assuming that $line is a single line of IRC protocol.
	$self->{RealNick} = ( split / /, $line )[2];
    }
    $ev->{name} = 'irc_' . $ev->{name};
    $self->_send_event( $ev->{name}, @{$ev->{args}} );
  }
}


# Hack to make plugin_add/del send events from OUR session
sub __send_event {
	my( $self, $event, @args ) = @_[ OBJECT, ARG0, ARG1 .. $#_ ];

	# Actually send the event...
	$self->_send_event( $event, @args );
	return 1;
}

# Sends an event to all interested sessions. This is a separate sub
# because I do it so much, but it's not an actual POE event because it
# doesn't need to be one and I don't need the overhead.
# Changed to a method by BinGOs, 21st January 2005.
# Amended by BinGOs (2nd February 2005) use call to send events to *our* session first.
sub _send_event  {
  my ($self) = shift;
  my ($event, @args) = @_;
  my $kernel = $POE::Kernel::poe_kernel;
  my ($session) = $kernel->get_active_session();
  my %sessions;

  # Let the plugin system process this
  if ( $self->_plugin_process( 'SERVER', $event, \( @args ) ) == PCI_EAT_ALL ) {
  	return 1;
  }

  # BINGOS:
  # We have a hack here, because the component used to send 'irc_connected' and
  # 'irc_disconnected' events to every registered session regardless of whether
  # that session had registered from them or not.
  if ( $event =~ /connected$/ ) {
    foreach (keys %{$self->{sessions}}) {
      $kernel->post( $self->{sessions}->{$_}->{'ref'},
		   $event, @args );
    }
    return 1;
  }

  foreach (values %{$self->{events}->{'irc_all'}},
	   values %{$self->{events}->{$event}}) {
    $sessions{$_} = $_;
  }
  # Make sure our session gets notified of any requested events before any other bugger
  $self->call( $event => @args ) if ( defined ( $sessions{$session} ) );
  foreach (values %sessions) {
    $kernel->post( $_, $event, @args ) unless ( $_ eq $session );
  }
}


# Internal function called when a socket is closed.
sub _sock_down {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  # Destroy the RW wheel for the socket.
  delete $self->{'socket'};
  $self->{connected} = 0;

  # Stop any delayed sends.
  $self->{send_queue} = [ ];
  $_[HEAP]->{send_queue} = $self->{send_queue};
  $self->{send_time}  = 0;
  $kernel->delay( sl_delayed => undef );

  # post a 'irc_disconnected' to each session that cares
  $self->_send_event( 'irc_disconnected', $self->{server} );
}


# Internal function called when a socket fails to be properly opened.
sub _sock_failed {
  my ($self, $op, $errno, $errstr) = @_[OBJECT, ARG0..ARG2];

  $self->_send_event( 'irc_socketerr', "$op error $errno: $errstr" );
}


# Internal function called when a connection is established.
sub _sock_up {
  my ($kernel, $self, $session, $socket) = @_[KERNEL, OBJECT, SESSION, ARG0];

  # We no longer need the SocketFactory wheel. Scrap it.
  delete $self->{'socketfactory'};

  # Remember what IP address we're connected through, for multihomed boxes.
  $self->{'localaddr'} = (unpack_sockaddr_in( getsockname $socket ))[1];

  #ssl!
  if ($GOT_SSL and $self->{'UseSSL'}) {
    eval {
      $socket = Client_SSLify( $socket );
    };
    if ($@) {
      #something didn't work
      warn "Couldn't use an SSL socket: $@ \n";
      $self->{'UseSSL'} = 0;
    }
  }

  # Create a new ReadWrite wheel for the connected socket.
  $self->{'socket'} = new POE::Wheel::ReadWrite
    ( Handle     => $socket,
      Driver     => POE::Driver::SysRW->new(),
      Filter     => POE::Filter::Line->new( InputRegexp => '\015?\012',
					    OutputLiteral => "\015\012" ),
      InputEvent => '_parseline',
      ErrorEvent => '_sock_down',
    );

  if ($self->{'socket'}) {
    $self->{connected} = 1;
  } else {
    $self->_send_event( 'irc_socketerr', "Couldn't create ReadWrite wheel for IRC socket" );
  }

  # Post a 'irc_connected' event to each session that cares
  $self->_send_event( 'irc_connected', $self->{server} );

  # CONNECT if we're using a proxy
  if ($self->{proxy}) {
    $kernel->call($session, 'sl_login', "CONNECT $self->{server}:$self->{port}");
  }

  # Now that we're connected, attempt to log into the server.
  if ($self->{password}) {
    $kernel->call( $session, 'sl_login', "PASS " . $self->{password} );
  }
  $kernel->call( $session, 'sl_login', "NICK " . $self->{nick} );
  $kernel->call( $session, 'sl_login', "USER " .
		 join( ' ', $self->{username},
		       ($self->{'user_bitmode'} ? $self->{'user_bitmode'} : 0),
		       '*',
		       ':' . $self->{ircname} ));

  # If we have queued data waiting, its flush loop has stopped
  # while we were disconnected.  Start that up again.
  $kernel->delay(sl_delayed => 0);
}


# Set up the component's IRC session.
sub _start {
  my ($kernel, $session, $self, $alias) = @_[KERNEL, SESSION, OBJECT, ARG0];
  my @options = @_[ARG1 .. $#_];

  # Send queue is used to hold pending lines so we don't flood off.
  # The count is used to track the number of lines sent at any time.
  $self->{send_queue} = [ ];
  $_[HEAP]->{send_queue} = $self->{send_queue};
  $self->{send_time}  = 0;

  $session->option( @options ) if @options;

  if ( $alias ) {
     $kernel->alias_set($alias);
  } else {
     $kernel->alias_set('PoCo-IRC-' . $session->ID() );
  }

  $kernel->yield( 'register', @{ $self->{IRC_EVTS} } );
  $self->{irc_filter} = POE::Filter::IRC->new();
  $self->{ctcp_filter} = POE::Filter::CTCP->new();

  $self->{SESSION_ID} = $session->ID();

  # Plugin 'irc_whois' and 'irc_whowas' support
  $self->plugin_add ( 'Whois', POE::Component::IRC::Plugin::Whois->new() );

  return 1;
}


# Destroy ourselves when asked politely.
sub _stop {
  my ($kernel, $self, $quitmsg) = @_[KERNEL, OBJECT, ARG0];

  if ($self->{connected}) {
    $kernel->call( $_[SESSION], 'quit', $quitmsg );
    $kernel->call( $_[SESSION], 'shutdown', $quitmsg );
  }
}


# The handler for commands which have N arguments, separated by commas.
sub commasep {
  my ($kernel, $self, $state) = @_[KERNEL, OBJECT, STATE];
  my $args = join ',', @_[ARG0 .. $#_];
  my $pri = $self->{IRC_CMDS}->{$state}->[CMD_PRI];

  $state = uc $state;
  $state .= " $args" if defined $args;
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# Get variables in order for openning a connection
sub connect {
  my ($kernel, $self, $session, $sender, $args) = @_[KERNEL, OBJECT, SESSION, SENDER, ARG0];
  my %arg;

  if ($args) {
    SWITCH: {
      if (ref $args eq 'ARRAY') {
        %arg = @$args;
	last SWITCH;
      }
      if (ref $args eq 'HASH') {
        %arg = %$args;
	last SWITCH;
      }
    }
  }

  foreach my $key ( keys %arg ) {
	$arg{ lc $key } = delete $arg{$key};
  }

  $self->_configure( \%arg );

  # try and use non-blocking resolver if needed
  if ( $GOT_CLIENT_DNS && !($self->{'server'} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) && ( not $self->{'NoDNS'} ) ) {
    $kernel->post(irc_resolver => resolve => got_dns_response => $self->{'server'} => "A", "IN");
  } else {
    $kernel->yield("do_connect");
  }

  # Is the calling session registered or not.
  #if ( not $self->{sessions}->{$sender} ) {
  #	$kernel->call( $session => 'register_session' => $sender => 'all' );
  #}

  $self->{RealNick} = $self->{nick};
}

# open the connection
sub do_connect {
  my ($kernel, $self, $session, $args) = @_[KERNEL, OBJECT, SESSION];

  # Disconnect if we're already logged into a server.
  if ($self->{'sock'}) {
    $kernel->call( $session, 'quit' );
  }

  $self->{'socketfactory'} =
    POE::Wheel::SocketFactory->new( SocketDomain   => AF_INET,
				    SocketType     => SOCK_STREAM,
				    SocketProtocol => 'tcp',
				    RemoteAddress  => $self->{'proxy'} || $self->{'server'},
				    RemotePort     => $self->{'proxyport'} || $self->{'port'},
				    SuccessEvent   => '_sock_up',
				    FailureEvent   => '_sock_failed',
				    ($self->{localaddr} ?
				       (BindAddress => $self->{localaddr}) : ()),
				  );
}

# got response from POE::Component::Client::DNS
sub got_dns_response {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($net_dns_packet, $net_dns_errorstring) = @{$_[ARG1]};

  unless(defined $net_dns_packet) {
    $self->_send_event( 'irc_socketerr', $net_dns_errorstring );
    return;
  }

  my @net_dns_answers = $net_dns_packet->answer;

  unless (@net_dns_answers) {
    $self->_send_event( 'irc_socketerr', "Unable to resolve $self->{'server'}");
    return;
  }

  foreach my $net_dns_answer (@net_dns_answers) {
    next unless $net_dns_answer->type eq "A";

    $self->{'server'} = $net_dns_answer->rdatastr;
    $kernel->yield("do_connect");
    return;
  }

  $self->_send_event( 'irc_socketerr', "Unable to resolve $self->{'server'}");

}

# Send a CTCP query or reply, with the same syntax as a PRIVMSG event.
sub ctcp {
  my ($kernel, $state, $self, $to) = @_[KERNEL, STATE, OBJECT, ARG0];
  my $message = join ' ', @_[ARG1 .. $#_];

  unless (defined $to and defined $message) {
    warn "The POE::Component::IRC event \"$state\" requires two arguments";
    return;
  }

  # CTCP-quote the message text.
  ($message) = @{$self->{ctcp_filter}->put([ $message ])};

  # Should we send this as a CTCP request or reply?
  $state = $state eq 'ctcpreply' ? 'notice' : 'privmsg';

  $kernel->yield( $state, $to, $message );
}


# Attempt to initiate a DCC SEND or CHAT connection with another person.
sub dcc {
  my ($kernel, $self, $nick, $type, $file, $blocksize, $timeout) =
    @_[KERNEL, OBJECT, ARG0 .. ARG4];
  my ($factory, $port, $myaddr, $size);

  unless ($type) {
    warn "The POE::Component::IRC event \"dcc\" requires at least two arguments";
    return;
  }

  $type = uc $type;

  # Let the plugin system process this
  if ( $self->_plugin_process( 'USER', 'DCC', \$nick, \$type, \$file, \$blocksize ) == PCI_EAT_ALL ) {
  	return 1;
  }

  if ($type eq 'CHAT') {
    $file = 'chat';		# As per the semi-specification

  } elsif ($type eq 'SEND') {
    unless ($file) {
      warn "The POE::Component::IRC event \"dcc\" requires three arguments for a SEND";
      return;
    }
    $size = (stat $file)[7];
    unless (defined $size) {
      $self->_send_event( 'irc_dcc_error', 0,
		   "Couldn't get ${file}'s size: $!", $nick, $type, 0, $file );
    }
  }

  if ($self->{localaddr} and $self->{localaddr} =~ tr/a-zA-Z.//) {
    $self->{localaddr} = inet_aton( $self->{localaddr} );
  }

  my ($bindport) = 0;

  if ( $self->{dcc_bind_port} ) {
	$bindport = shift @{ $self->{dcc_bind_port} };
	unless ($bindport) {
		warn "dcc: Can't allocate listen port for DCC $type";
		return;
	}
  }

  $factory = POE::Wheel::SocketFactory->new(
      BindAddress  => $self->{localaddr} || INADDR_ANY,
      BindPort     => $bindport,
      SuccessEvent => '_dcc_up',
      FailureEvent => '_dcc_failed',
      Reuse        => 'yes',
  );
  ($port, $myaddr) = unpack_sockaddr_in( $factory->getsockname() );
  $myaddr = inet_aton($self->{nat_addr}) || $self->{localaddr} || inet_aton(hostname() || 'localhost');
  unless ($myaddr) {
    warn "dcc: Can't determine our IP address! ($!)";
    return;
  }
  $myaddr = unpack "N", $myaddr;

  # Tell the other end that we're waiting for them to connect.
  my $basename = File::Basename::basename( $file );
  $basename =~ s/\s/_/g;

  $kernel->yield( 'ctcp', $nick, "DCC $type $basename $myaddr $port"
		  . ($size ? " $size" : "") );

  # Store the state for this connection.
  $self->{dcc}->{$factory->ID} = { open => undef,
				   nick => $nick,
				   type => $type,
				   file => $file,
				   size => $size,
				   port => $port,
				   addr => $myaddr,
				   done => 0,
				   blocksize => ($blocksize || BLOCKSIZE),
				   listener => 1,
				   factory => $factory,

				   listenport => $bindport,
				   clientaddr => $myaddr,
				 };
  $kernel->alarm( '_dcc_timeout', time() + ($timeout || DCC_TIMEOUT), $factory->ID );
}


# Accepts a proposed DCC connection to another client. See '_dcc_up' for
# the rest of the logic for this.
sub dcc_accept {
  my ($kernel, $self, $cookie, $myfile) = @_[KERNEL, OBJECT, ARG0, ARG1];

  # Let the plugin system process this
  if ( $self->_plugin_process( 'USER', 'DCC_ACCEPT', \$cookie, \$myfile ) == PCI_EAT_ALL ) {
  	return 1;
  }

  if ($cookie->{type} eq 'SEND' || $cookie->{type} eq 'ACCEPT')
  {
    $cookie->{type} = 'GET';
    $cookie->{file} = $myfile if defined $myfile;   # filename override
  }

  my $factory = POE::Wheel::SocketFactory->new(
      RemoteAddress => $cookie->{addr},
      RemotePort    => $cookie->{port},
      SuccessEvent  => '_dcc_up',
      FailureEvent  => '_dcc_failed',
  );
  $self->{dcc}->{$factory->ID} = $cookie;
  $self->{dcc}->{$factory->ID}->{factory} = $factory;
}
# bboett - first step - the user asks for a resume:
# tries to resume a previous dcc transfer. See '_dcc_up' for
# the rest of the logic for this.
sub dcc_resume
{
  my ($kernel, $self, $cookie) = @_[KERNEL, OBJECT, ARG0 .. ARG2];

  # Let the plugin system process this
  if ( $self->_plugin_process( 'USER', 'DCC_RESUME', \$cookie ) == PCI_EAT_ALL ) {
  	return 1;
  }

  if ($cookie->{type} eq 'SEND') {
    $cookie->{type} = 'RESUME';

    my $myfile = $cookie->{tmpfile};
    if($cookie->{tmpfile})
    {
      my $mysize = -s $cookie->{tmpfile};
      my $fraction = $mysize % INCOMING_BLOCKSIZE;
      print("DCC RESUME org size $mysize frac= $fraction\n");
      $mysize -= $fraction;
      $cookie->{resumesize} = $mysize;
      # we need to truncate the whole thing, adjust the size we are
      # requesting to the size we will truncate the file to
      if(open(FILE,">>".$myfile))
      {
	if(truncate(FILE,$mysize))
	{
	  print("Success truncating file to size=$mysize\n");
	}
	my ($nick,$name,$host) = ( $cookie->{nick} =~ /(\S+)!(\S+)@(\S+)/);
	close(FILE);

	my $message = 'DCC RESUME '.$cookie->{file}." ".$cookie->{port}." ".$mysize.'';
	my $state = 'PRIVMSG';
	my $pri = $self->{IRC_CMDS}->{$state}->[CMD_PRI];

	$state .= " $nick :$message";
	$kernel->yield( 'sl_prioritized', $pri, $state );
      }# if(open(FILE,">>".$myfile))
    }# if($mysize)
  }
}# sub dcc_resume


# Send data over a DCC CHAT connection.
sub dcc_chat {
  my ($kernel, $self, $id, @data) = @_[KERNEL, OBJECT, ARG0, ARG1 .. $#_];

  unless (exists $self->{dcc}->{$id}) {
    warn "dcc_chat: Unknown wheel ID: $id";
    return;
  }
  unless (exists $self->{dcc}->{$id}->{wheel}) {
    warn "dcc_chat: No DCC wheel for $id!";
    return;
  }
  unless ($self->{dcc}->{$id}->{type} eq "CHAT") {
    warn "dcc_chat: $id isn't a DCC CHAT connection!";
    return;
  }

  # Let the plugin system process this
  if ( $self->_plugin_process( 'USER', 'DCC_CHAT', \$id, \( @data ) ) == PCI_EAT_ALL ) {
  	return 1;
  }

  $self->{dcc}->{$id}->{wheel}->put( join "\n", @data );
}


# Terminate a DCC connection manually.
sub dcc_close {
  my ($kernel, $self, $id) = @_[KERNEL, OBJECT, ARG0];

  if ($self->{dcc}->{$id}->{wheel}->get_driver_out_octets()) {
    $kernel->delay( _tryclose => .2 => @_[ARG0..$#_] );
    return;
  }

  # Let the plugin system process this
  if ( $self->_plugin_process( 'USER', 'DCC_CLOSE', \$id ) == PCI_EAT_ALL ) {
  	return 1;
  }

  $self->_send_event( 'irc_dcc_done', $id,
	       @{$self->{dcc}->{$id}}{ qw(nick type port file size done listenport clientaddr) } );

  # Reclaim our port if necessary.
  if ( $self->{dcc}->{$id}->{listener} and $self->{dcc_bind_port} and $self->{dcc}->{$id}->{listenport} ) {
	push ( @{ $self->{dcc_bind_port} }, $self->{dcc}->{$id}->{listenport} );
  }

  if (exists $self->{dcc}->{$id}->{wheel}) {
    delete $self->{wheelmap}->{$self->{dcc}->{$id}->{wheel}->ID};
    delete $self->{dcc}->{$id}->{wheel};
  }
  delete $self->{dcc}->{$id};
}



# The way /notify is implemented in IRC clients.
sub ison {
  my ($kernel, @nicks) = @_[KERNEL, ARG0 .. $#_];
  my $tmp = "ISON";

  unless (@nicks) {
    warn "No nicknames passed to POE::Component::IRC::ison";
    return;
  }

  # We can pass as many nicks as we want, as long as it's shorter than
  # the maximum command length (510). If the list we get is too long,
  # w'll break it into multiple ISON commands.
  while (@nicks) {
    my $nick = shift @nicks;
    if (length($tmp) + length($nick) >= 509) {
      $kernel->yield( 'sl_high', $tmp );
      $tmp = "ISON";
    }
    $tmp .= " $nick";
  }
  $kernel->yield( 'sl_high', $tmp );
}


# Tell the IRC server to forcibly remove a user from a channel.
sub kick {
  my ($kernel, $chan, $nick) = @_[KERNEL, ARG0, ARG1];
  my $message = join '', @_[ARG2 .. $#_];

  unless (defined $chan and defined $nick) {
    warn "The POE::Component::IRC event \"kick\" requires at least two arguments";
    return;
  }

  $nick .= " :$message" if defined $message;
  $kernel->yield( 'sl_high', "KICK $chan $nick" );
}

# Set up a new IRC component. Deprecated.
sub new {
  my ($package, $alias) = splice @_, 0, 2;

  unless ($alias) {
    croak "Not enough arguments to POE::Component::IRC::new()";
  }

  my ($self) = $package->spawn ( alias => $alias, options => { @_ } );

  return $self;
}

# Set up a new IRC component. New interface.
sub spawn {
  my ($package) = shift;
  croak "$package requires an even number of parameters" if @_ & 1;

  my %parms = @_;

  foreach my $key ( keys %parms ) {
	$parms{ lc $key } = delete $parms{$key};
  }

  delete ( $parms{'options'} ) unless ( ref ( $parms{'options'} ) eq 'HASH' );

  my ($self) = $package->_create();

  my ($alias) = delete ( $parms{'alias'} );

  POE::Session->create(
		object_states => [
		     $self => $self->{OBJECT_STATES_HASHREF},
		     $self => $self->{OBJECT_STATES_ARRAYREF}, ],
		( defined ( $parms{'options'} ) ? ( options => $parms{'options'} ) : () ),
		args => [ $alias ] );

  $parms{'CALLED_FROM_SPAWN'} = 1;
  $self->_configure( \%parms );

  return $self;
}


# The handler for all IRC commands that take no arguments.
sub noargs {
  my ($kernel, $state, $arg) = @_[KERNEL, STATE, ARG0];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  if (defined $arg) {
    warn "The POE::Component::IRC event \"$state\" takes no arguments";
    return;
  }
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# The handler for commands that take one required and two optional arguments.
sub oneandtwoopt {
  my ($kernel, $state) = @_[KERNEL, STATE];
  my $arg = join '', @_[ARG0 .. $#_];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  $state = uc $state;
  if (defined $arg) {
    $arg = ':' . $arg if $arg =~ /\s/;
    $state .= " $arg";
  }
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# The handler for commands that take at least one optional argument.
sub oneoptarg {
  my ($kernel, $state) = @_[KERNEL, STATE];
  my $arg = join '', @_[ARG0 .. $#_] if defined $_[ARG0];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  $state = uc $state;
  if (defined $arg) {
    $arg = ':' . $arg if $arg =~ /\s/;
    $state .= " $arg";
  }
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# The handler for commands which take one required and one optional argument.
sub oneortwo {
  my ($kernel, $state, $one) = @_[KERNEL, STATE, ARG0];
  my $two = join '', @_[ARG1 .. $#_];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  unless (defined $one) {
    warn "The POE::Component::IRC event \"$state\" requires at least one argument";
    return;
  }

  $state = uc( $state ) . " $one";
  $state .= " $two" if defined $two;
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# Handler for commands that take exactly one argument.
sub onlyonearg {
  my ($kernel, $state) = @_[KERNEL, STATE];
  my $arg = join '', @_[ARG0 .. $#_];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  unless (defined $arg) {
    warn "The POE::Component::IRC event \"$state\" requires one argument";
    return;
  }

  $state = uc $state;
  $arg = ':' . $arg if $arg =~ /\s/;
  $state .= " $arg";
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# Handler for commands that take exactly two arguments.
sub onlytwoargs {
  my ($kernel, $state, $one) = @_[KERNEL, STATE, ARG0];
  my ($two) = join '', @_[ARG1 .. $#_];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  unless (defined $one and defined $two) {
    warn "The POE::Component::IRC event \"$state\" requires two arguments";
    return;
  }

  $state = uc $state;
  $two = ':' . $two if $two =~ /\s/;
  $state .= " $one $two";
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# Handler for privmsg or notice events.
sub privandnotice {
  my ($kernel, $state, $to) = @_[KERNEL, STATE, ARG0];
  my $message = join ' ', @_[ARG1 .. $#_];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  $state =~ s/privmsglo/privmsg/;
  $state =~ s/privmsghi/privmsg/;
  $state =~ s/noticelo/notice/;
  $state =~ s/noticehi/notice/;

  unless (defined $to and defined $message) {
    warn "The POE::Component::IRC event \"$state\" requires two arguments";
    return;
  }

  if (ref $to eq 'ARRAY') {
    $to = join ',', @$to;
  }

  $state = uc $state;
  $state .= " $to :$message";
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# Ask P::C::IRC to send you certain events, listed in @events.
sub register {
  my ($kernel, $self, $session, $sender, @events) =
    @_[KERNEL, OBJECT, SESSION, SENDER, ARG0 .. $#_];

  unless (@events) {
    warn "register: Not enough arguments";
    return;
  }

  # FIXME: What "special" event names go here? (ie, "errors")
  # basic, dcc (implies ctcp), ctcp, oper ...what other categories?
  foreach (@events) {
    $_ = "irc_" . $_ unless /^_/;
    $self->{events}->{$_}->{$sender} = $sender;
    $self->{sessions}->{$sender}->{'ref'} = $sender;
    unless ($self->{sessions}->{$sender}->{refcnt}++ or $session == $sender) {
      $kernel->refcount_increment($sender->ID(), PCI_REFCOUNT_TAG);
    }
  }
  # BINGOS:
  # Apocalypse is gonna hate me for this as 'irc_registered' events will bypass 
  # the Plugins system, but I can't see how this event will be relevant without 
  # some sort of reference, like what session has registered. I'm not going to
  # start hurling session references around at this point :)

  $kernel->post( $sender => 'irc_registered' => $self );
}

sub register_session {
  my ($kernel, $self, $session, $called_by, $sender, @events) =
    @_[KERNEL, OBJECT, SESSION, SENDER, ARG0 .. $#_];

  unless ($session eq $called_by) {
    warn "register_session: Naughty. Naughty. Only my session can call this";
    return;
  }
  unless (@events) {
    warn "register_session: Not enough arguments";
    return;
  }

  # FIXME: What "special" event names go here? (ie, "errors")
  # basic, dcc (implies ctcp), ctcp, oper ...what other categories?
  foreach (@events) {
    $_ = "irc_" . $_ unless /^_/;
    $self->{events}->{$_}->{$sender} = $sender;
    $self->{sessions}->{$sender}->{'ref'} = $sender;
    unless ($self->{sessions}->{$sender}->{refcnt}++ or $session == $sender) {
      $kernel->refcount_increment($sender->ID(), PCI_REFCOUNT_TAG);
    }
  }
}

# Tell the IRC session to go away.
sub shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  foreach ($kernel->alias_list( $_[SESSION] )) {
    $kernel->alias_remove( $_ );
  }

  foreach (qw(socket sock socketfactory dcc wheelmap)) {
    delete $self->{$_};
  }

  #if ( $self->{sessions}->{ $_[SENDER] } ) {
  #	$kernel->yield ( 'unregister_sessions' );
  #}
}


# Send a line of login-priority IRC output.  These are things which
# must go first.
sub sl_login {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $arg = join '', @_[ARG0 .. $#_];
  $kernel->yield( 'sl_prioritized', PRI_LOGIN, $arg );
}


# Send a line of high-priority IRC output.  Things like channel/user
# modes, kick messages, and whatever.
sub sl_high {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $arg = join '', @_[ARG0 .. $#_];
  $kernel->yield( 'sl_prioritized', PRI_HIGH, $arg );
}


# Send a line of normal-priority IRC output to the server.  PRIVMSG
# and other random chatter.  Uses sl() for compatibility with existing
# code.
sub sl {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $arg = join '', @_[ARG0 .. $#_];

  $kernel->yield( 'sl_prioritized', PRI_NORMAL, $arg );
}


# Prioritized sl().  This keeps the queue ordered by priority, low to
# high in the UNIX tradition.  It also throttles transmission
# following the hybrid ircd's algorithm, so you can't accidentally
# flood yourself off.  Thanks to Raistlin for explaining how ircd
# throttles messages.
sub sl_prioritized {
  my ($kernel, $self, $priority, $msg) = @_[KERNEL, OBJECT, ARG0, ARG1];

  # Get the first word for the plugin system
  if ( $msg =~ /^(\w+)\s*/ ) {
  	# Let the plugin system process this
  	if ( $self->_plugin_process( 'USER', $1, \$msg ) == PCI_EAT_ALL ) {
  		return 1;
  	}
  } else {
  	warn "Unable to extract the event name from '$msg'";
  }

  my $now = time();
  $self->{send_time} = $now if $self->{send_time} < $now;

  if (@{$self->{send_queue}}) {
    my $i = @{$self->{send_queue}};
    $i-- while ($i and $priority < $self->{send_queue}->[$i-1]->[MSG_PRI]);
    splice( @{$self->{send_queue}}, $i, 0,
            [ $priority,  # MSG_PRI
              $msg,       # MSG_TEXT
            ]
          );
  } elsif ( $self->{dont_flood} and
            $self->{send_time} - $now >= 10 or not defined $self->{socket}
          ) {
    push( @{$self->{send_queue}},
          [ $priority,  # MSG_PRI
            $msg,       # MSG_TEXT
	   ]
	 );
    $kernel->delay( sl_delayed => $self->{send_time} - $now - 10 );
  } else {
    warn ">>> $msg\n" if $self->{debug};
    $self->{send_time} += 2 + length($msg) / 120;
    $self->{socket}->put($msg);
  }
}

# Send delayed lines to the ircd.  We manage a virtual "send time"
# that progresses into the future based on hybrid ircd's rules every
# time a message is sent.  Once we find it ten or more seconds into
# the future, we wait for the realtime clock to catch up.
sub sl_delayed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  return unless defined $self->{'socket'};

  my $now = time();
  $self->{send_time} = $now if $self->{send_time} < $now;

  while (@{$self->{send_queue}} and ($self->{send_time} - $now < 10)) {
    my $arg = (shift @{$self->{send_queue}})->[MSG_TEXT];
    warn ">>> $arg\n" if $self->{'debug'};
    $self->{send_time} += 2 + length($arg) / 120;
    $self->{'socket'}->put( "$arg" );
  }

  $kernel->delay( sl_delayed => $self->{send_time} - $now - 10 )
    if @{$self->{send_queue}};
}


# The handler for commands which have N arguments, separated by spaces.
sub spacesep {
  my ($kernel, $state) = @_[KERNEL, STATE];
  my $args = join ' ', @_[ARG0 .. $#_];
  my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

  $state = uc $state;
  $state .= " $args" if defined $args;
  $kernel->yield( 'sl_prioritized', $pri, $state );
}


# Set or query the current topic on a channel.
sub topic {
  my ($kernel, $chan) = @_[KERNEL, ARG0];
  my $topic = join '', @_[ARG1 .. $#_];

  $chan .= " :$topic" if length $topic;
  $kernel->yield( 'sl_prioritized', PRI_NORMAL, "TOPIC $chan" );
}


# Ask P::C::IRC to stop sending you certain events, listed in $evref.
sub unregister {
  my ($kernel, $self, $session, $sender, @events) =
    @_[KERNEL,  OBJECT, SESSION,  SENDER,  ARG0 .. $#_];

  unless (@events) {
    warn "unregister: Not enough arguments";
    return;
  }

  foreach (@events) {
    delete $self->{events}->{$_}->{$sender};
    if (--$self->{sessions}->{$sender}->{refcnt} <= 0) {
      delete $self->{sessions}->{$sender};
      unless ($session == $sender) {
        $kernel->refcount_decrement($sender->ID(), PCI_REFCOUNT_TAG);
      }
    }
  }
}

sub unregister_sessions {
  my ($kernel, $self, $session, $called_by) =
    @_[KERNEL,  OBJECT, SESSION,  SENDER];

  unless ($session eq $called_by) {
    warn "unregister_sessions: Naughty. Naughty. Only I can call this event";
    return;
  }

  foreach my $sender ( keys %{ $self->{sessions} } ) {
    foreach ( keys %{ $self->{events} } ) {
      delete $self->{events}->{$_}->{$sender};
      if (--$self->{sessions}->{$sender}->{refcnt} <= 0) {
        delete $self->{sessions}->{$sender};
        unless ($session == $sender) {
          $kernel->refcount_decrement($sender->ID(), PCI_REFCOUNT_TAG);
        }
      }
    }
  }
}


# Asks the IRC server for some random information about particular nicks.
sub userhost {
  my ($kernel, @nicks) = @_[KERNEL, ARG0 .. $#_];
  my @five;

  unless (@nicks) {
    warn "No nicknames passed to POE::Component::IRC::userhost";
    return;
  }

  # According to the RFC, you can only send 5 nicks at a time.
  while (@nicks) {
    $kernel->yield( 'sl_prioritized', PRI_HIGH,
		    "USERHOST " . join(' ', splice(@nicks, 0, 5)) );
  }
}

# Non-event methods

sub version {
  my ($self) = shift;

  return $VERSION;
}

sub server_name {
  my ($self) = shift;

  return $self->{INFO}->{ServerName};
}

sub nick_name {
  my ($self) = shift;

  return $self->{RealNick};
}

sub send_queue {
  my ($self) = shift;

  if ( defined ( $self->{send_queue} ) and ref ( $self->{send_queue} ) eq 'ARRAY' ) {
	return scalar @{ $self->{send_queue} };
  }
  return 0;
}

sub session_id {
  my ($self) = shift;

  return $self->{SESSION_ID};
}

sub yield {
  my ($self) = shift;

  $poe_kernel->post( $self->session_id() => @_ );
}

sub call {
  my ($self) = shift;

  $poe_kernel->call( $self->session_id() => @_ );
}

sub _validate_command {
  my ($self) = shift;
  my ($cmd) = lc ( $_[0] ) || return 0;

  foreach my $command ( keys %{ $self->{IRC_CMDS} } ) {
	if ( $cmd eq $command ) {
		return 1;
	}
  }
  return 0;
}

sub connected {
  my ($self) = shift;

  return $self->{connected};
}

# Automatically replies to a PING from the server. Do not confuse this
# with CTCP PINGs, which are a wholly different animal that evolved
# much later on the technological timeline.
sub irc_ping {
  my ($kernel, $arg) = @_[KERNEL, ARG0];

  $kernel->yield( 'sl_login', "PONG $arg" );
}

# NICK messages for the purposes of determining our current nickname
sub irc_nick {
  my ($kernel,$self,$who,$new) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my ($nick) = ( split /!/, $who )[0];

  if ( $nick eq $self->{RealNick} ) {
	$self->{RealNick} = $new;
  }
}

# Adds a new plugin object
sub plugin_add {
	my( $self, $name, $plugin ) = @_;

	# Sanity check
	if ( ! defined $name or ! defined $plugin ) {
		warn 'Please supply a name and the plugin object to be added!';
		return undef;
	}

	# Tell the plugin to register itself
	my ($return);

	eval {
	   $return = $plugin->PCI_register( $self );
	};

	if ( $return ) {
		$self->{PLUGINS}->{OBJECTS}->{ $name } = $plugin;

		# Okay, send an event to let others know this plugin is loaded
		$self->yield( '__send_event', 'irc_plugin_add', $name, $plugin );

		return 1;
	} else {
		return undef;
	}
}

# Removes a plugin object
sub plugin_del {
	my( $self, $name ) = @_;

	# Sanity check
	if ( ! defined $name ) {
		warn 'Please supply a name/object for the plugin to be removed!';
		return undef;
	}

	# Is it an object or a name?
	my $plugin = undef;
	if ( ! ref( $name ) ) {
		# Check if it is loaded
		if ( exists $self->{PLUGINS}->{OBJECTS}->{ $name } ) {
			$plugin = delete $self->{PLUGINS}->{OBJECTS}->{ $name };
		} else {
			return undef;
		}
	} else {
		# It's an object...
		foreach my $key ( keys %{ $self->{PLUGINS}->{OBJECTS} } ) {
			# Check if it's the same object
			if ( ref( $self->{PLUGINS}->{OBJECTS}->{ $key } ) eq ref( $name ) ) {
				$plugin = $name;
				$name = $key;
			}
		}
	}

	# Did we get it?
	if ( defined $plugin ) {
		# Automatically remove all registrations for this plugin
		foreach my $type ( qw( SERVER USER ) ) {
			foreach my $event ( keys %{ $self->{PLUGINS}->{ $type } } ) {
				$self->_plugin_unregister_do( $type, $event, $plugin );
			}
		}

		# Tell the plugin to unregister
		eval {
			$plugin->PCI_unregister( $self );
		};

		# Okay, send an event to let others know this plugin is deleted
		$self->yield( '__send_event', 'irc_plugin_del', $name, $plugin );

		# Success!
		return $plugin;
	} else {
		return undef;
	}
}

# Gets the plugin object
sub plugin_get {
	my( $self, $name ) = @_;

	# Sanity check
	if ( ! defined $name ) {
		warn 'Please supply a name for the plugin object to be retrieved!';
		return undef;
	}

	# Check if it is loaded
	if ( exists $self->{PLUGINS}->{OBJECTS}->{ $name } ) {
		return $self->{PLUGINS}->{OBJECTS}->{ $name };
	} else {
		return undef;
	}
}

# Lists loaded plugins
sub plugin_list {
	my ($self) = shift;
	my $return = { };

	foreach my $name ( keys %{ $self->{PLUGINS}->{OBJECTS} } ) {
		$return->{ $name } = $self->{PLUGINS}->{OBJECTS}->{ $name };
	}
	return $return;
}

# Lets a plugin register for certain events
sub plugin_register {
	my( $self, $plugin, $type, @events ) = @_;

	# Sanity checks
	if ( ! defined $type or ! ( $type eq 'SERVER' or $type eq 'USER' ) ) {
		warn 'Type should be SERVER or USER!';
		return undef;
	}
	if ( ! defined $plugin ) {
		warn 'Please supply the plugin object to register!';
		return undef;
	}
	if ( ! @events ) {
		warn 'Please supply at least one event name to register!';
		return undef;
	}

	# Okay, do the actual work here!
	foreach my $ev ( @events ) {
		# Is it an arrayref?
		if ( ref( $ev ) and ref( $ev ) eq 'ARRAY' ) {
			# Loop over it!
			foreach my $evnt ( @$ev ) {
				# Make sure it is lowercased
				$evnt = lc( $evnt );

				# Push it to the end of the queue
				push( @{ $self->{PLUGINS}->{ $type }->{ $evnt } }, $plugin );
			}
		} else {
			# Make sure it is lowercased
			$ev = lc( $ev );

			# Push it to the end of the queue
			push( @{ $self->{PLUGINS}->{ $type }->{ $ev } }, $plugin );
		}
	}

	# All done!
	return 1;
}

# Lets a plugin unregister events
sub plugin_unregister {
	my( $self, $plugin, $type, @events ) = @_;

	# Sanity checks
	if ( ! defined $type or ! ( $type eq 'SERVER' or $type eq 'USER' ) ) {
		warn 'Type should be SERVER or USER!';
		return undef;
	}
	if ( ! defined $plugin ) {
		warn 'Please supply the plugin object to register!';
		return undef;
	}
	if ( ! @events ) {
		warn 'Please supply at least one event name to unregister!';
		return undef;
	}

	# Okay, do the actual work here!
	foreach my $ev ( @events ) {
		# Is it an arrayref?
		if ( ref( $ev ) and ref( $ev ) eq 'ARRAY' ) {
			# Loop over it!
			foreach my $evnt ( @$ev ) {
				# Make sure it is lowercased
				$evnt = lc( $evnt );

				# Check if the event even exists
				if ( ! exists $self->{PLUGINS}->{ $type }->{ $evnt } ) {
					warn "The event '$evnt' does not exist!";
					next;
				}

				$self->_plugin_unregister_do( $type, $evnt, $plugin );
			}
		} else {
			# Make sure it is lowercased
			$ev = lc( $ev );

			# Check if the event even exists
			if ( ! exists $self->{PLUGINS}->{ $type }->{ $ev } ) {
				warn "The event '$ev' does not exist!";
				next;
			}

			$self->_plugin_unregister_do( $type, $ev, $plugin );
		}
	}

	# All done!
	return 1;
}

# Helper routine to remove plugins
sub _plugin_unregister_do {
	my( $self, $type, $event, $plugin ) = @_;

	# Check if the plugin is there
	# Yes, this sucks but it doesn't happen often...
	my $counter = 0;

	# Loop over the array
	while ( $counter < scalar( @{ $self->{PLUGINS}->{ $type }->{ $event } } ) ) {
		# See if it is a match
		if ( ref( $self->{PLUGINS}->{ $type }->{ $event }->[$counter] ) eq ref( $plugin ) ) {
			# Splice it!
			splice( @{ $self->{PLUGINS}->{ $type }->{ $event } }, $counter, 1 );
			last;
		}

		# Increment the counter
		$counter++;
	}

	# All done!
	return 1;
}

# Process an input event for plugins
sub _plugin_process {
	my( $self, $type, $event, @args ) = @_;

	# Make sure event is lowercased
	$event = lc( $event );

	# And remove the irc_ prefix
	if ( $event =~ /^irc\_(.*)$/ ) {
		$event = $1;
	}

	# Check if any plugins are interested in this event
	if ( not ( exists $self->{PLUGINS}->{ $type }->{ $event } or exists $self->{PLUGINS}->{ $type }->{ 'all' } ) ) {
		return PCI_EAT_NONE;
	}

	# Determine the return value
	my $return = PCI_EAT_NONE;

	# Which type are we doing?
	my $sub;
	if ( $type eq 'SERVER' ) {
		$sub = 'S_' . $event;
	} else {
		$sub = 'U_' . $event;
	}

	# Okay, have the plugins process this event!
	foreach my $plugin ( @{ $self->{PLUGINS}->{ $type }->{ $event } }, @{ $self->{PLUGINS}->{ $type }->{ 'all' } } ) {
		# What does the plugin return?
		my ($ret) = PCI_EAT_NONE;
		# Added eval cos we can't trust plugin authors to play by the rules *sigh*
		eval {
			$ret = $plugin->$sub( $self, @args );
		};

		if ( $@ ) {
		   # Okay, no method of that name fallback on _default() method.
		   eval {
			$ret = $plugin->_default( $self, $sub, @args );
		   };
		}

		if ( $ret == PCI_EAT_PLUGIN ) {
			return $return;
		} elsif ( $ret == PCI_EAT_CLIENT ) {
			$return = PCI_EAT_ALL;
		} elsif ( $ret == PCI_EAT_ALL ) {
			return PCI_EAT_ALL;
		}
	}

	# All done!
	return $return;
}

1;
__END__

=head1 NAME

POE::Component::IRC - a fully event-driven IRC client module.

=head1 SYNOPSIS

  # The old way

  use POE::Component::IRC;

  # Do this when you create your sessions. 'my client' is just a
  # kernel alias to christen the new IRC connection with.

  POE::Component::IRC->new('my client') or die "Oh noooo! $!";

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

  # The new way using the object

  use POE::Component::IRC;

  my ($irc) = POE::Component::IRC->spawn() or die "Oh noooo! $!";

  $irc->yield( 'connect',
		{ Nick     => 'Boolahman',
                  Server   => 'irc-w.primenet.com',
                  Port     => 6669,
                  Username => 'quetzal',
                  Ircname  => 'Ask me about my colon!', } );

  $kernel->post( $irc->session_id(), 'connect',
                { Nick     => 'Boolahman',
                  Server   => 'irc-w.primenet.com',
                  Port     => 6669,
                  Username => 'quetzal',
                  Ircname  => 'Ask me about my colon!',
                  UseSSL   => 1, } );

=head1 DESCRIPTION

POE::Component::IRC is a POE component (who'd have guessed?) which
acts as an easily controllable IRC client for your other POE
components and sessions. You create an IRC component and tell it what
events your session cares about and where to connect to, and it sends
back interesting IRC events when they happen. You make the client do
things by sending it events. That's all there is to it. Cool, no?

[Note that using this module requires some familiarity with the
details of the IRC protocol. I'd advise you to read up on the gory
details of RFC 1459
E<lt>http://cs-pub.bu.edu/pub/irc/support/rfc1459.txtE<gt> before you
get started. Keep the list of server numeric codes handy while you
program. Needless to say, you'll also need a good working knowledge of
POE, or this document will be of very little use to you.]

The old way:-

So you want to write a POE program with POE::Component::IRC? Listen
up. The short version is as follows: Create your session(s) and an
alias for a new POE::Component::IRC client. (Conceptually, it helps if
you think of them as little IRC clients.) In your session's _start
handler, send the IRC client a 'register' event to tell it which IRC
events you want to receive from it. Send it a 'connect' event at some
point to tell it to join the server, and it should start sending you
interesting events every once in a while. If you want to tell it to
perform an action, like joining a channel and saying something witty,
send it the appropriate events like so:

  $kernel->post( 'my client', 'join', '#perl' );
  $kernel->post( 'my client', 'privmsg', '#perl', 'Pull my finger!' );

The new way:-

As of version 3.4, having to use an alias became optional. Using the 'spawn'
method, creates a new component and returns an POE::Component::IRC object.

One can always get the session ID of the component using the 'session_id()'
method of the object. Alternatively, one can post events using the object with
the 'yield()' method.

  my ($irc) = POE::Component::IRC->spawn() or die;

  $irc->yield( 'register' => 'all' );

  $irc->yield( 'connect',
                { Nick     => 'Boolahman',
                  Server   => 'irc-w.primenet.com',
                  Port     => 6669,
                  Username => 'quetzal',
                  Ircname  => 'Ask me about my colon!', } );

The long version is the rest of this document.

=head1 The Plugin system

As of 3.7, PoCo-IRC sports a plugin system. The documentation for it can be read by looking
at L<POE::Component::IRC::Plugin>. That is not a subclass, just a placeholder for documentation!

=head1 METHODS

=over

=item spawn

Takes a number of arguments. "alias", a name (kernel alias) that this
instance of the component will be known by; "options", a hashref containing
POE::Session options for the component's session. See 'connect()' for additional
arguments that this method accepts. All arguments are optional.

=item new

This method is deprecated. See 'spawn' method instead.
Takes one argument: a name (kernel alias) which this new connection
will be known by. Returns a POE::Component::IRC object :)

=item server_name

Takes no arguments. Returns the name of the IRC server that the component
is currently connected to.

=item nick_name

Takes no arguments. Returns a scalar containing the current nickname that the
bot is using.

=item session_id

Takes no arguments. Returns the ID of the component's session. Ideal for posting
events to the component.

$kernel->post( $irc->session_id() => 'mode' => $channel => '+o' => $dude );

=item yield

This method provides an alternative object based means of posting events to the component.
First argument is the event to post, following arguments are sent as arguments to the resultant
post.

$irc->yield( 'mode' => $channel => '+o' => $dude );

=item call

This method provides an alternative object based means of calling events to the component.
First argument is the event to call, following arguments are sent as arguments to the resultant
call.

$irc->call( 'mode' => $channel => '+o' => $dude );

=item version

Takes no arguments. Returns the version number of the module.

=item send_queue

The component provides anti-flood throttling. This method takes no arguments and returns a scalar
representing the number of messages that are queued up waiting for dispatch to the irc server.

=item connected 

Takes no arguments. Returns true or false depending on whether the component is currently
connected to an IRC network or not.

=back

=head1 INPUT

How to talk to your new IRC component... here's the events we'll accept.

=head2 Important Commands

=over

=item connect

Takes one argument: a hash reference of attributes for the new
connection (see the L<SYNOPSIS> section of this doc for an
example). This event tells the IRC client to connect to a
new/different server. If it has a connection already open, it'll close
it gracefully before reconnecting. Possible attributes for the new
connection are:

=over

"Server", the server name;
"Password", an optional password for restricted servers;
"Port", the remote port number;
"LocalAddr", which local IP address on a multihomed box to connect as;
"LocalPort", the local TCP port to open your socket on;
"Nick", your client's IRC nickname;
"Username", your client's username;
"Ircname", some cute comment or something.
"UseSSL", set to some true value if you want to connect using SSL.
"Raw", set to some true value to enable the component to send 'irc_raw' events.

=back

C<connect()> will supply
reasonable defaults for any of these attributes which are missing, so
don't feel obliged to write them all out.

If the component finds that L<POE::Component::Client::DNS|POE::Component::Client::DNS>
is installed it will use that to resolve the server name passed. Disable this
behaviour if you like, by passing NoDNS => 1.

The ever popular I<irc_part> bug has been fixed. To get the bot to exhibit the old broken
behaviour pass PartFix => 0.

Additionally there is a "Flood" parameter.  When true, it disables the
component's flood protection algorithms, allowing it to send messages
to an IRC server at full speed.  Disconnects and k-lines are some
common side effects of flooding IRC servers, so care should be used
when enabling this option.

Two new attributes are "Proxy" and "ProxyPort" for sending your
IRC traffic through a proxy server.  "Proxy"'s value should be the IP
address or server name of the proxy.  "ProxyPort"'s value should be the
port on the proxy to connect to.  C<connect()> will default to using the
I<actual> IRC server's port if you provide a proxy but omit the proxy's
port.

For those people who run bots behind firewalls and/or Network Address Translation
there are two additional attributes for DCC. "DCCPorts", is an arrayref of ports
to use when initiating DCC, using dcc(). "NATAddr", is the NAT'ed IP address that your bot is
hidden behind, this is sent whenever you do DCC.

SSL support requires POE::Component::SSLify, as well as an IRC server that supports
SSL connections. If you're missing POE::Component::SSLify, specifing 'UseSSL' will do
nothing. The default is to not try to use SSL.

Setting 'Raw' to true, will enable the component to send 'irc_raw' events to interested plugins
and sessions. See below for more details on what a 'irc_raw' events is :)

=item ctcp and ctcpreply

Sends a CTCP query or response to the nick(s) or channel(s) which you
specify. Takes 2 arguments: the nick or channel to send a message to
(use an array reference here to specify multiple recipients), and the
plain text of the message to send (the CTCP quoting will be handled
for you).

=item dcc

Send a DCC SEND or CHAT request to another person. Takes at least two
arguments: the nickname of the person to send the request to and the
type of DCC request (SEND or CHAT). For SEND requests, be sure to add
a third argument for the filename you want to send. Optionally, you
can add a fourth argument for the DCC transfer blocksize, but the
default of 1024 should usually be fine.

Incidentally, you can send other weird nonstandard kinds of DCCs too;
just put something besides 'SEND' or 'CHAT' (say, "FOO") in the type
field, and you'll get back "irc_dcc_foo" events when activity happens
on its DCC connection.

If you are behind a firewall or Network Address Translation, you may want to
consult 'connect()' for some parameters that are useful with this command.

=item dcc_accept

Accepts an incoming DCC connection from another host. First argument:
the magic cookie from an 'irc_dcc_request' event. In the case of a DCC
GET, the second argument can optionally specify a new name for the
destination file of the DCC transfer, instead of using the sender's name
for it. (See the 'irc_dcc_request' section below for more details.)

=item dcc_chat

Sends lines of data to the person on the other side of a DCC CHAT
connection. Takes any number of arguments: the magic cookie from an
'irc_dcc_start' event, followed by the data you wish to send. (It'll be
chunked into lines by a POE::Filter::Line for you, don't worry.)

=item dcc_close

Terminates a DCC SEND or GET connection prematurely, and causes DCC CHAT
connections to close gracefully. Takes one argument: the magic cookie
from an 'irc_dcc_start' or 'irc_dcc_request' event.

=item join

Tells your IRC client to join a single channel of your choice. Takes
at least one arg: the channel name (required) and the channel key
(optional, for password-protected channels).

=item kick

Tell the IRC server to forcibly evict a user from a particular
channel. Takes at least 2 arguments: a channel name, the nick of the
user to boot, and an optional witty message to show them as they sail
out the door.

=item mode

Request a mode change on a particular channel or user. Takes at least
one argument: the mode changes to effect, as a single string (e.g.,
"+sm-p+o"), and any number of optional operands to the mode changes
(nicks, hostmasks, channel keys, whatever.) Or just pass them all as one
big string and it'll still work, whatever. I regret that I haven't the
patience now to write a detailed explanation, but serious IRC users know
the details anyhow.

=item nick

Allows you to change your nickname. Takes exactly one argument: the
new username that you'd like to be known as.

=item notice

Sends a NOTICE message to the nick(s) or channel(s) which you
specify. Takes 2 arguments: the nick or channel to send a notice to
(use an array reference here to specify multiple recipients), and the
text of the notice to send.

=item part

Tell your IRC client to leave the channels which you pass to it. Takes
any number of arguments: channel names to depart from.

=item privmsg

Sends a public or private message to the nick(s) or channel(s) which
you specify. Takes 2 arguments: the nick or channel to send a message
to (use an array reference here to specify multiple recipients), and
the text of the message to send.

=item quit

Tells the IRC server to disconnect you. Takes one optional argument:
some clever, witty string that other users in your channels will see
as you leave. You can expect to get an C<irc_disconnect> event shortly
after sending this.

=item register

Takes N arguments: a list of event names that your session wants to
listen for, minus the "irc_" prefix. So, for instance, if you just
want a bot that keeps track of which people are on a channel, you'll
need to listen for JOINs, PARTs, QUITs, and KICKs to people on the
channel you're in. You'd tell POE::Component::IRC that you want those
events by saying this:

  $kernel->post( 'my client', 'register', qw(join part quit kick) );

Then, whenever people enter or leave a channel your bot is on (forcibly
or not), your session will receive events with names like "irc_join",
"irc_kick", etc., which you can use to update a list of people on the
channel.

Registering for C<'all'> will cause it to send all IRC-related events to
you; this is the easiest way to handle it. See the test script for an
example.

Registering will generate an 'irc_registered' event that your session can
trap. ARG0 is the components object. Useful if you want to bolt PoCo-IRC's
new features such as Plugins into a bot coded to the older deprecated API.
If you are using the new API, ignore this :)

=item shutdown

By default, POE::Component::IRC sessions never go away. Even after
they're disconnected, they're still sitting around in the background,
waiting for you to call C<connect()> on them again to reconnect.
(Whether this behavior is the Right Thing is doubtful, but I don't want
to break backwards compatibility at this point.) You can send the IRC
session a C<shutdown> event manually to make it delete itself.

=item unregister

Takes N arguments: a list of event names which you I<don't> want to
receive. If you've previously done a 'register' for a particular event
which you no longer care about, this event will tell the IRC
connection to stop sending them to you. (If you haven't, it just
ignores you. No big deal.)

=item debug

Takes 1 argument: 0 to turn debugging off or 1 to turn debugging on.
This turns debugging on in POE::Filter::IRC, POE::Filter::CTCP, and
POE::Component::IRC. This has the same effect as setting Debug to true
in 'connect'.

=back

=head2 Not-So-Important Commands

=over

=item admin

Asks your server who your friendly neighborhood server administrators
are. If you prefer, you can pass it a server name to query, instead of
asking the server you're currently on.

=item away

When sent with an argument (a message describig where you went), the
server will note that you're now away from your machine or otherwise
preoccupied, and pass your message along to anyone who tries to
communicate with you. When sent without arguments, it tells the server
that you're back and paying attention.

=item info

Basically the same as the "version" command, except that the server is
permitted to return any information about itself that it thinks is
relevant. There's some nice, specific standards-writing for ya, eh?

=item invite

Invites another user onto an invite-only channel. Takes 2 arguments:
the nick of the user you wish to admit, and the name of the channel to
invite them to.

=item ison

Asks the IRC server which users out of a list of nicknames are
currently online. Takes any number of arguments: a list of nicknames
to query the IRC server about.

=item links

Asks the server for a list of servers connected to the IRC
network. Takes two optional arguments, which I'm too lazy to document
here, so all you would-be linklooker writers should probably go dig up
the RFC.

=item list

Asks the server for a list of visible channels and their topics. Takes
any number of optional arguments: names of channels to get topic
information for. If called without any channel names, it'll list every
visible channel on the IRC network. This is usually a really big list,
so don't do this often.

=item motd

Request the server's "Message of the Day", a document which typically
contains stuff like the server's acceptable use policy and admin
contact email addresses, et cetera. Normally you'll automatically
receive this when you log into a server, but if you want it again,
here's how to do it. If you'd like to get the MOTD for a server other
than the one you're logged into, pass it the server's hostname as an
argument; otherwise, no arguments.

=item names

Asks the server for a list of nicknames on particular channels. Takes
any number of arguments: names of channels to get lists of users
for. If called without any channel names, it'll tell you the nicks of
everyone on the IRC network. This is a really big list, so don't do
this much.

=item sl

Sends a raw line of text to the server. Takes one argument: a string
of a raw IRC command to send to the server. It is more optimal to use
the events this module supplies instead of writing raw IRC commands
yourself.

=item stats

Returns some information about a server. Kinda complicated and not
terribly commonly used, so look it up in the RFC if you're
curious. Takes as many arguments as you please.

=item time

Asks the server what time it thinks it is, which it will return in a
human-readable form. Takes one optional argument: a server name to
query. If not supplied, defaults to current server.

=item topic

Retrieves or sets the topic for particular channel. If called with just
the channel name as an argument, it will ask the server to return the
current topic. If called with the channel name and a string, it will
set the channel topic to that string.

=item trace

If you pass a server name or nick along with this request, it asks the
server for the list of servers in between you and the thing you
mentioned. If sent with no arguments, it will show you all the servers
which are connected to your current server.

=item userhost

Asks the IRC server for information about particular nicknames. (The
RFC doesn't define exactly what this is supposed to return.) Takes any
number of arguments: the nicknames to look up.

=item users

Asks the server how many users are logged into it. Defaults to the
server you're currently logged into; however, you can pass a server
name as the first argument to query some other machine instead.

=item version

Asks the server about the version of ircd that it's running. Takes one
optional argument: a server name to query. If not supplied, defaults
to current server.

=item who

Lists the logged-on users matching a particular channel name, hostname,
nickname, or what-have-you. Takes one optional argument: a string for
it to search for. Wildcards are allowed; in the absence of this
argument, it will return everyone who's currently logged in (bad
move). Tack an "o" on the end if you want to list only IRCops, as per
the RFC.

=item whois

Queries the IRC server for detailed information about a particular
user. Takes any number of arguments: nicknames or hostmasks to ask for
information about. As of version 3.2, you will receive an 'irc_whois'
event in addition to the usual numeric responses. See below for details.

=item whowas

Asks the server for information about nickname which is no longer
connected. Takes at least one argument: a nickname to look up (no
wildcards allowed), the optional maximum number of history entries to
return, and the optional server hostname to query. As of version 3.2,
you will receive an 'irc_whowas' event in addition to the usual numeric
responses. See below for details.

=item ping/pong

Included for completeness sake. The component will deal with ponging to
pings automatically. Don't worry about it.

=back

=head2 Purely Esoteric Commands

=over

=item locops

Opers-only command. This one sends a message to all currently
logged-on local-opers (+l).  This option is specific to EFNet.

=item oper

In the exceedingly unlikely event that you happen to be an IRC
operator, you can use this command to authenticate with your IRC
server. Takes 2 arguments: your username and your password.

=item operwall

Opers-only command. This one sends a message to all currently
logged-on global opers.  This option is specific to EFNet.

=item rehash

Tells the IRC server you're connected to to rehash its configuration
files. Only useful for IRCops. Takes no arguments.

=item restart

Tells the IRC server you're connected to to shut down and restart itself.
Only useful for IRCops, thank goodness. Takes no arguments.

=item sconnect

Tells one IRC server (which you have operator status on) to connect to
another. This is actually the CONNECT command, but I already had an
event called 'connect', so too bad. Takes the args you'd expect: a
server to connect to, an optional port to connect on, and an optional
remote server to connect with, instead of the one you're currently on.

=item summon

Don't even ask.

=item wallops

Another opers-only command. This one sends a message to all currently
logged-on opers (and +w users); sort of a mass PA system for the IRC
server administrators. Takes one argument: some clever, witty message
to send.

=back

=head1 OUTPUT

The events you will receive (or can ask to receive) from your running
IRC component. Note that all incoming event names your session will
receive are prefixed by "irc_", to inhibit event namespace pollution.

If you wish, you can ask the client to send you every event it
generates. Simply register for the event name "all". This is a lot
easier than writing a huge list of things you specifically want to
listen for. FIXME: I'd really like to classify these somewhat
("basic", "oper", "ctcp", "dcc", "raw" or some such), and I'd welcome
suggestions for ways to make this easier on the user, if you can think
of some.

=head2 Important Events

=over

=item irc_connected

The IRC component will send an "irc_connected" event as soon as it
establishes a connection to an IRC server, before attempting to log
in. ARG0 is the server name.

B<NOTE:> When you get an "irc_connected" event, this doesn't mean you
can start sending commands to the server yet. Wait until you receive
an irc_001 event (the server welcome message) before actually sending
anything back to the server.

=item irc_ctcp_*

irc_ctcp_whatever events are generated upon receipt of CTCP messages.
For instance, receiving a CTCP PING request generates an irc_ctcp_ping
event, CTCP ACTION (produced by typing "/me" in most IRC clients)
generates an irc_ctcp_action event, blah blah, so on and so forth. ARG0
is the nick!hostmask of the sender. ARG1 is the channel/recipient
name(s). ARG2 is the text of the CTCP message.

Note that DCCs are handled separately -- see the 'irc_dcc_request'
event, below.

=item irc_ctcpreply_*

irc_ctcpreply_whatever messages are just like irc_ctcp_whatever
messages, described above, except that they're generated when a response
to one of your CTCP queries comes back. They have the same arguments and
such as irc_ctcp_* events.

=item irc_disconnected

The counterpart to irc_connected, sent whenever a socket connection
to an IRC server closes down (whether intentionally or
unintentionally). ARG0 is the server name.

=item irc_error

You get this whenever the server sends you an ERROR message. Expect
this to usually be accompanied by the sudden dropping of your
connection. ARG0 is the server's explanation of the error.

=item irc_join

Sent whenever someone joins a channel that you're on. ARG0 is the
person's nick!hostmask. ARG1 is the channel name.

=item irc_invite

Sent whenever someone offers you an invitation to another channel. ARG0
is the person's nick!hostmask. ARG1 is the name of the channel they want
you to join.

=item irc_kick

Sent whenever someone gets booted off a channel that you're on. ARG0
is the kicker's nick!hostmask. ARG1 is the channel name. ARG2 is the
nick of the unfortunate kickee. ARG3 is the explanation string for the
kick.

=item irc_mode

Sent whenever someone changes a channel mode in your presence, or when
you change your own user mode. ARG0 is the nick!hostmask of that
someone. ARG1 is the channel it affects (or your nick, if it's a user
mode change). ARG2 is the mode string (i.e., "+o-b"). The rest of the
args (ARG3 .. $#_) are the operands to the mode string (nicks,
hostmasks, channel keys, whatever).

=item irc_msg

Sent whenever you receive a PRIVMSG command that was addressed to you
privately. ARG0 is the nick!hostmask of the sender. ARG1 is an array
reference containing the nick(s) of the recipients. ARG2 is the text
of the message.

=item irc_nick

Sent whenever you, or someone around you, changes nicks. ARG0 is the
nick!hostmask of the changer. ARG1 is the new nick that they changed
to.

=item irc_notice

Sent whenever you receive a NOTICE command. ARG0 is the nick!hostmask
of the sender. ARG1 is an array reference containing the nick(s) or
channel name(s) of the recipients. ARG2 is the text of the NOTICE
message.

=item irc_part

Sent whenever someone leaves a channel that you're on. ARG0 is the
person's nick!hostmask. ARG1 is the channel name.

( There has been a slight bug with irc_part and part messages. ARG1
would contain "<#channel> :part message". This has been fixed, but
you must pass PartFix => 1 to the 'connect' request ).

=item irc_ping

An event sent whenever the server sends a PING query to the
client. (Don't confuse this with a CTCP PING, which is another beast
entirely. If unclear, read the RFC.) Note that POE::Component::IRC will
automatically take care of sending the PONG response back to the
server for you, although you can still register to catch the event for
informational purposes.

=item irc_public

Sent whenever you receive a PRIVMSG command that was sent to a
channel. ARG0 is the nick!hostmask of the sender. ARG1 is an array
reference containing the channel name(s) of the recipients. ARG2 is
the text of the message.

=item irc_quit

Sent whenever someone on a channel with you quits IRC (or gets
KILLed). ARG0 is the nick!hostmask of the person in question. ARG1 is
the clever, witty message they left behind on the way out.

=item irc_socketerr

Sent when a connection couldn't be established to the IRC server. ARG0
is probably some vague and/or misleading reason for what failed.

=item irc_whois

Sent in response to a 'whois' query. ARG0 is a hashref, with the following
keys: 'nick', the users nickname; 'user', the users username; 'host', their
hostname; 'real', their real name; 'idle', their idle time in seconds; 'signon',
the epoch time they signed on ( will be undef if ircd does not support this );
'channels', an arrayref listing visible channels they are on, the channel is prefixed
with '@','+','%' depending on whether they have +o +v or +h; 'server', their server (
might not be useful on some networks ); 'oper', whether they are an IRCop, contains the
IRC operator string if they are, undef if they aren't. On Freenode if the user has
identified with NICKSERV there will be an additional key: 'identified'.

=item irc_whowas

Similar to the above, except some keys will be missing.

=item irc_raw

Enabled by passing 'Raw' => 1 to spawn() or connect(), ARG0 is the raw IRC string received
by the component from the IRC server, before it has been mangled by filters and such like.

=item irc_registered

Sent once to the requesting session on registration ( see register() ). ARG0 is a reference to
the component's object.

=item All numeric events (see RFC 1459)

Most messages from IRC servers are identified only by three-digit
numeric codes with undescriptive constant names like RPL_UMODEIS and
ERR_NOTOPLEVEL. (Actually, the list of codes in the RFC is kind of
out-of-date... the list in the back of Net::IRC::Event.pm is more
complete, and different IRC networks have different and incompatible
lists. Ack!) As an example, say you wanted to handle event 376
(RPL_ENDOFMOTD, which signals the end of the MOTD message). You'd
register for '376', and listen for 'irc_376' events. Simple, no? ARG0
is the name of the server which sent the message. ARG1 is the text of
the message.

=back

=head2 Somewhat Less Important Events

=over

=item irc_dcc_chat

Notifies you that one line of text has been received from the
client on the other end of a DCC CHAT connection. ARG0 is the
connection's magic cookie, ARG1 is the nick of the person on the other
end, ARG2 is the port number, and ARG3 is the text they sent.

=item irc_dcc_done

You receive this event when a DCC connection terminates normally.
Abnormal terminations are reported by "irc_dcc_error", below. ARG0 is
the connection's magic cookie, ARG1 is the nick of the person on the
other end, ARG2 is the DCC type (CHAT, SEND, GET, etc.), and ARG3 is the
port number. For DCC SEND and GET connections, ARG4 will be the
filename, ARG5 will be the file size, and ARG6 will be the number of
bytes transferred. (ARG5 and ARG6 should always be the same.)

=item irc_dcc_error

You get this event whenever a DCC connection or connection attempt
terminates unexpectedly or suffers some fatal error. ARG0 will be the
connection's magic cookie, ARG1 will be a string describing the error.
ARG2 will be the nick of the person on the other end of the connection.
ARG3 is the DCC type (SEND, GET, CHAT, etc.). ARG4 is the port number of
the DCC connection, if any. For SEND and GET connections, ARG5 is the
filename, ARG6 is the expected file size, and ARG7 is the transfered size.

=item irc_dcc_get

Notifies you that another block of data has been successfully
transferred from the client on the other end of your DCC GET connection.
ARG0 is the connection's magic cookie, ARG1 is the nick of the person on
the other end, ARG2 is the port number, ARG3 is the filename, ARG4 is
the total file size, and ARG5 is the number of bytes successfully
transferred so far.

=item irc_dcc_request

You receive this event when another IRC client sends you a DCC SEND or
CHAT request out of the blue. You can examine the request and decide
whether or not to accept it here. ARG0 is the nick of the client on the
other end. ARG1 is the type of DCC request (CHAT, SEND, etc.). ARG2 is
the port number. ARG3 is a "magic cookie" argument, suitable for sending
with 'dcc_accept' events to signify that you want to accept the
connection (see the 'dcc_accept' docs). For DCC SEND and GET
connections, ARG4 will be the filename, and ARG5 will be the file size.

=item irc_dcc_send

Notifies you that another block of data has been successfully
transferred from you to the client on the other end of a DCC SEND
connection. ARG0 is the connection's magic cookie, ARG1 is the nick of
the person on the other end, ARG2 is the port number, ARG3 is the
filename, ARG4 is the total file size, and ARG5 is the number of bytes
successfully transferred so far.

=item irc_dcc_start

This event notifies you that a DCC connection has been successfully
established. ARG0 is a unique "magic cookie" argument which you can pass
to 'dcc_chat' or 'dcc_close'. ARG1 is the nick of the person on the
other end, ARG2 is the DCC type (CHAT, SEND, GET, etc.), and ARG3 is the
port number. For DCC SEND and GET connections, ARG4 will be the filename
and ARG5 will be the file size.

=item irc_snotice

A weird, non-RFC-compliant message from an IRC server. Don't worry
about it. ARG0 is the text of the server's message.

=item dcc_resume

  bboetts puny try to get dcc resume implemented in this great
  module:
  ARG0 is the well known 'magic cookie' (as in dcc_send etc.)
  ARG1 is the (eventually new) name of the file
  ARG2 is the size from which will be resumed

  usage and example:

  sub irc_dcc_request {
    my ($kernel, $nick, $type, $port, $magic, $filename, $size) =
      @_[KERNEL, ARG0 .. ARG5];

    print "DCC $type request from $nick on port $port\n";
    if($args->{type} =~ /SEND/i)
    {
      $nick = ($nick =~ /^([^!]+)/);
      $nick =~ s/\W//;
      if(my $filesize = -s "$1.$filename")
      {
	$kernel->post('test', 'dcc_resume', $magic, "$1.$filename", "$filesize" );
	#dont forget to save the cookie, it holds the address of the counterpart which won't be in the server response!!
	$args->{heap}->{cookies}->{$args->{file}} = $args->{magic};
      }#if(-s "$1.$filename")
      else
      {
	$kernel->post( 'test', 'dcc_accept', $magic, "$1.$filename" );
      }#else
    }
  elsif($args->{type} =~ /ACCEPT/i)
  {
      $kernel->post( $args->{context}, 'dcc_accept', $magic, $filename);
  }
  }
 you need a counter part in irc_dcc_request:

    if($type eq 'ACCEPT')
    {
       #the args are in wrong order and missing shift the args 1 up
       $magic->{port} = $magic->{addr};

       my $altcookie = $_[OBJECT]->{cookies}->{$filename};
       $magic->{addr} = $altcookie->{addr};
       delete $_[OBJECT]->{cookies}->{$filename};
       #TODO beware a possible memory leak here...
    }# if($type eq 'ACCEPT')

=back

=head1 BUGS

A few have turned up in the past and they are sure to again. Please use
L<http://rt.cpan.org/> to report any. Alternatively, email the current maintainer.

=head1 MAINTAINER

Chris 'BinGOs' Williams E<lt>chris@bingosnet.co.uk<gt>

=head1 AUTHOR

Dennis Taylor, E<lt>dennis@funkplanet.comE<gt>

=head1 MAD PROPS

The maddest of mad props go out to Rocco "dngor" Caputo
E<lt>troc@netrus.netE<gt>, for inventing something as mind-bogglingly
cool as POE, and to Kevin "oznoid" Lenzo E<lt>lenzo@cs.cmu.eduE<gt>,
for being the attentive parent of our precocious little infobot on
#perl.

Further props to a few of the studly bughunters who made this module not
suck: Abys <abys@web1-2-3.com>, Addi <addi@umich.edu>, ResDev
<ben@reser.org>, and Roderick <roderick@argon.org>. Woohoo!

Check out the Changes file for further contributors.

=head1 SEE ALSO

RFC 1459 L<http://www.faqs.org/rfcs/rfc1459.html>, L<http://www.irchelp.org/>,
L<http://poe.perl.org/>,
L<http://www.infobot.org/>,

Some good examples reside in the POE cookbook which has a whole section devoted to
IRC programming L<http://poe.perl.org/?POE_Cookbook>.

=cut
