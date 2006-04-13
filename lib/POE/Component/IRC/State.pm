# $Id: State.pm,v 1.4 2005/04/28 14:18:19 chris Exp $
#
# POE::Component::IRC::State, by Chris Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::IRC::State;

use strict;
use warnings;
use POE::Component::IRC::Common qw(:ALL);
use POE::Component::IRC::Plugin qw(:ALL);
use base qw(POE::Component::IRC);
use vars qw($VERSION);

$VERSION = '1.5';

# Event handlers for tracking the STATE. $self->{STATE} is used as our namespace.
# u_irc() is used to create unique keys.

# Make sure we have a clean STATE when we first join the network and if we inadvertently get disconnected
sub S_001 {
  delete $_[0]->{STATE};
  return PCI_EAT_NONE;
}

sub S_disconnected {
  my $self = shift;
  my $nickinfo = $self->nick_info( $self->{RealNick} );
  my $channels = $self->channels();
  push @{ $_[$#_] }, $nickinfo, $channels;
  delete $self->{STATE};
  return PCI_EAT_NONE;
}

sub S_error {
  my $self = shift;
  my $nickinfo = $self->nick_info( $self->{RealNick} );
  my $channels = $self->channels();
  push @{ $_[$#_] }, $nickinfo, $channels;
  delete $self->{STATE};
  return PCI_EAT_NONE;
}

sub S_socketerr {
  my $self = shift;
  my $nickinfo = $self->nick_info( $self->{RealNick} );
  my $channels = $self->channels();
  push @{ $_[$#_] }, $nickinfo, $channels;
  delete $self->{STATE};
  return PCI_EAT_NONE;
}

# Channel JOIN messages
sub S_join {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  my $userhost = ( split /!/, ${ $_[0] } )[1];
  my ($user,$host) = split(/\@/,$userhost);
  my $channel = ${ $_[1] };

  if ( u_irc ( $nick ) eq u_irc ( $self->{RealNick} ) ) {
	delete $self->{STATE}->{Chans}->{ u_irc ( $channel ) };
	$self->{CHANNEL_SYNCH}->{ u_irc ( $channel ) } = { MODE => 0, WHO => 0 };
        $self->{STATE}->{Chans}->{ u_irc $channel } = { };
        $self->yield ( 'who' => $channel );
        $self->yield ( 'mode' => $channel );
  } else {
        $self->yield ( 'who' => $nick );
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Nick} = $nick;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{User} = $user;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Host} = $host;
        $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{CHANS}->{ u_irc ( $channel ) } = '';
        $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $nick ) } = '';
  }
  return PCI_EAT_NONE;
}

# Channel PART messages
sub S_part {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = u_irc ( ( split /!/, ${ $_[0] } )[0] );
  my $channel = u_irc ${ $_[1] };

  if ( $nick eq u_irc ( $self->nick_name() ) ) {
        delete $self->{STATE}->{Nicks}->{ $nick }->{CHANS}->{ $channel };
        delete $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $nick };
        foreach my $member ( keys %{ $self->{STATE}->{Chans}->{ $channel }->{Nicks} } ) {
           delete $self->{STATE}->{Nicks}->{ $member }->{CHANS}->{ $channel };
           if ( scalar keys %{ $self->{STATE}->{Nicks}->{ $member }->{CHANS} } <= 0 ) {
                delete $self->{STATE}->{Nicks}->{ $member };
           }
        }
	delete $self->{STATE}->{Chans}->{ $channel };
  } else {
        delete $self->{STATE}->{Nicks}->{ $nick }->{CHANS}->{ $channel };
        delete $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $nick };
        if ( scalar keys %{ $self->{STATE}->{Nicks}->{ $nick }->{CHANS} } <= 0 ) {
                delete $self->{STATE}->{Nicks}->{ $nick };
        }
  }
  return PCI_EAT_NONE;
}

# QUIT messages
sub S_quit {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  push @{ $_[2] }, [ $self->nick_channels( $nick ) ];

  if ( u_irc ( $nick ) eq u_irc ( $self->{RealNick} ) ) {
        delete $self->{STATE};
  } else {
        foreach my $channel ( keys %{ $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{CHANS} } ) {
                delete $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ u_irc ( $nick ) };
        }
        delete $self->{STATE}->{Nicks}->{ u_irc ( $nick ) };
  }
  return PCI_EAT_NONE;
}

# Channel KICK messages
sub S_kick {
  my ($self,$irc) = splice @_, 0, 2;
  my $channel = ${ $_[1] };
  my $nick = ${ $_[2] };

  if ( u_irc ( $nick ) eq u_irc ( $self->{RealNick} ) ) {
        delete $self->{STATE}->{Nicks}->{ u_irc $nick }->{CHANS}->{ u_irc $channel };
        delete $self->{STATE}->{Chans}->{ u_irc $channel }->{Nicks}->{ u_irc $nick };
        foreach my $member ( keys %{ $self->{STATE}->{Chans}->{ u_irc $channel }->{Nicks} } ) {
           delete $self->{STATE}->{Nicks}->{ u_irc $member }->{CHANS}->{ u_irc $channel };
           if ( scalar keys %{ $self->{STATE}->{Nicks}->{ u_irc $member }->{CHANS} } <= 0 ) {
                delete $self->{STATE}->{Nicks}->{ u_irc $member };
           }
        }
	delete $self->{STATE}->{Chans}->{ u_irc $channel };
  } else {
        delete $self->{STATE}->{Nicks}->{ u_irc $nick }->{CHANS}->{ u_irc $channel };
        delete $self->{STATE}->{Chans}->{ u_irc $channel }->{Nicks}->{ u_irc $nick };
        if ( scalar keys %{ $self->{STATE}->{Nicks}->{ u_irc $nick }->{CHANS} } <= 0 ) {
                delete $self->{STATE}->{Nicks}->{ u_irc $nick };
        }
  }
  return PCI_EAT_NONE;
}

# NICK changes
sub S_nick {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  my $new = ${ $_[1] };
  push @{ $_[2] }, [ $self->nick_channels( $nick ) ];

  if ( $nick eq $self->{RealNick} ) {
	$self->{RealNick} = $new;
  }

  if ( u_irc ( $nick ) eq u_irc ( $new ) ) {
        # Case Change
        $self->{STATE}->{Nicks}->{ u_irc $nick }->{Nick} = $new;
  } else {
        my $record = delete $self->{STATE}->{Nicks}->{ u_irc $nick };
        $record->{Nick} = $new;
        foreach my $channel ( keys %{ $record->{CHANS} } ) {
           $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ u_irc $new } = $record->{CHANS}->{ $channel };
           delete $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ u_irc $nick };
        }
        $self->{STATE}->{Nicks}->{ u_irc $new } = $record;
  }
  return PCI_EAT_NONE;
}

# Channel MODE
sub S_mode {
  my ($self,$irc) = splice @_, 0, 2;
  my $who = ${ $_[0] };
  my $channel = ${ $_[1] };
  pop @_;
  my @modes = map { ${ $_ } } @_[2 .. $#_];

  # Do nothing if it is UMODE
  if ( u_irc ( $channel ) ne u_irc ( $self->{RealNick} ) ) {
     my $parsed_mode = parse_mode_line( @modes );
     while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
        my $arg;
        $arg = shift ( @{ $parsed_mode->{args} } ) if ( $mode =~ /^(\+[hovklbIeaqfL]|-[hovbIeaq])/ );
        SWITCH: {
          if ( $mode =~ /\+([ohvaq])/ ) {
                my $flag = $1;
                unless ($self->{STATE}->{Nicks}->{ u_irc $arg }->{CHANS}->{ u_irc $channel }and $self->{STATE}->{Nicks}->{ u_irc $arg }->{CHANS}->{ u_irc $channel } =~ /$flag/) {
                      $self->{STATE}->{Nicks}->{ u_irc $arg }->{CHANS}->{ u_irc $channel } .= $flag;
                      $self->{STATE}->{Chans}->{ u_irc $channel }->{Nicks}->{ u_irc $arg } = $self->{STATE}->{Nicks}->{ u_irc $arg }->{CHANS}->{ u_irc $channel };
                }
                last SWITCH;
          }
          if ( $mode =~ /-([ohvaq])/ ) {
                my ($flag) = $1;
                if ($self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) } =~ /$flag/) {
                      $self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) } =~ s/$flag//;
                      $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Nicks}->{ u_irc ( $arg ) } = $self->{STATE}->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ u_irc ( $channel ) };
                }
                last SWITCH;
          }
          if ( $mode =~ /[bIefL]/ ) {
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
                $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} .= $flag unless $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} =~ /$flag/;
                last SWITCH;
          }
          if ( $mode =~ /^-(.)/ ) {
                my ($flag) = $1;
                if ($self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ /$flag/) {
                      $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} =~ s/$flag//;
                }
                last SWITCH;
          }
        }
     }
     # Lets make the channel mode nice
     if ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} ) {
        $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} = join('', sort {uc $a cmp uc $b} ( split( //, $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} ) ) );
     } else {
        delete ( $self->{STATE}->{Chans}->{ u_irc ( $channel ) }->{Mode} );
     }
  }
  return PCI_EAT_NONE;
}

# RPL_WHOREPLY
sub S_352 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($first,$second) = split(/ :/,${ $_[1] } );
  my ($channel,$user,$host,$server,$nick,$status) = split(/ /,$first);
  my $real = substr($second,index($second," ")+1);

  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Nick} = $nick;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{User} = $user;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Host} = $host;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Real} = $real;
  $self->{STATE}->{Nicks}->{ u_irc ( $nick ) }->{Server} = $server;
  if ( $channel ne '*' ) {
    my ($whatever) = '';
    if ( $status =~ /\@/ ) { $whatever = 'o'; }
    if ( $status =~ /\+/ ) { $whatever = 'v'; }
    if ( $status =~ /\%/ ) { $whatever = 'h'; }
    if ( $status =~ /\&/ ) { $whatever = 'a'; }
    if ( $status =~ /\~/ ) { $whatever = 'q'; }
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
	$self->_send_event( 'irc_nick_sync', $channel );
  }
  return PCI_EAT_NONE;
}

# RPL_CHANNELMODEIS
sub S_324 {
  my ($self,$irc) = splice @_, 0, 2;
  my @args = split / /, ${ $_[1] };
  my $channel = shift @args;

  my $parsed_mode = parse_mode_line( @args );
  while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
        $mode =~ s/\+//;
        my $arg;
        $arg = shift @{ $parsed_mode->{args} } if $mode =~ /[kl]/;
	if ( $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} ) {
          $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} .= $mode unless $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} =~ /$mode/;
	} else {
	  $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} = $mode;
	}
        if ( $mode eq 'l' and defined ( $arg ) ) {
           $self->{STATE}->{Chans}->{ u_irc $channel }->{ChanLimit} = $arg;
        }
        if ( $mode eq 'k' and defined ( $arg ) ) {
           $self->{STATE}->{Chans}->{ u_irc $channel }->{ChanKey} = $arg;
        }
  }
  if ( $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} ) {
        $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} = join('', sort {uc $a cmp uc $b} split //, $self->{STATE}->{Chans}->{ u_irc $channel }->{Mode} );
  }
  $self->_channel_sync_mode($channel);
  if ( $self->_channel_sync($channel) ) {
	delete $self->{CHANNEL_SYNCH}->{ u_irc $channel };
	$self->_send_event( 'irc_chan_sync', $channel );
  }
  return PCI_EAT_NONE;
}

# Methods for STATE query
# Internal methods begin with '_'
#

sub _channel_sync {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;

  unless ( $self->_channel_exists($channel) ) {
	return 0;
  }

  if ( defined ( $self->{CHANNEL_SYNCH}->{ $channel } ) ) {
	if ( $self->{CHANNEL_SYNCH}->{ $channel }->{MODE} and $self->{CHANNEL_SYNCH}->{ $channel }->{WHO} ) {
		return 1;
	}
  }
  return 0;
}

sub _channel_sync_mode {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;

  unless ( $self->_channel_exists($channel) ) {
	return 0;
  }

  if ( defined ( $self->{CHANNEL_SYNCH}->{ $channel } ) ) {
	$self->{CHANNEL_SYNCH}->{ $channel }->{MODE} = 1;
	return 1;
  }
  return 0;
}

sub _channel_sync_who {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;

  unless ( $self->_channel_exists($channel) ) {
	return 0;
  }

  if ( defined ( $self->{CHANNEL_SYNCH}->{ $channel } ) ) {
	$self->{CHANNEL_SYNCH}->{ $channel }->{WHO} = 1;
	return 1;
  }
  return 0;
}

sub _nick_exists {
  my $self = shift;
  my $nick = u_irc ( $_[0] ) || return 0;

  if ( defined ( $self->{STATE}->{Nicks}->{ $nick } ) ) {
	return 1;
  }
  return 0;
}

sub _channel_exists {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;

  if ( defined ( $self->{STATE}->{Chans}->{ $channel } ) ) {
	return 1;
  }
  return 0;
}

sub _nick_has_channel_mode {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;
  my $flag = ( split //, $_[2] )[0] || return 0;

  unless ( $self->is_channel_member($channel,$nick) ) {
	return 0;
  }

  if ( $self->{STATE}->{Nicks}->{ $nick }->{CHANS}->{ $channel } =~ /$flag/ ) {
	return 1;
  }
  return 0;
}

# Returns all the channels that the bot is on with an indication of whether it has operator, halfop or voice.
sub channels {
  my $self = shift;
  my %result;
  my $realnick = u_irc $self->{RealNick};

  if ( $self->_nick_exists($realnick) ) {
	foreach my $channel ( keys %{ $self->{STATE}->{Nicks}->{ $realnick }->{CHANS} } ) {
	  $result{ $self->{STATE}->{Chans}->{ $channel }->{Name} } = $self->{STATE}->{Nicks}->{ $realnick }->{CHANS}->{ $channel };
	}
  }
  return \%result;
}

sub nicks {
  my $self = shift;
  my @result;

  foreach my $nick ( keys %{ $self->{STATE}->{Nicks} } ) {
	push ( @result, $self->{STATE}->{Nicks}->{ $nick }->{Nick} );
  }
  return @result;
}

sub nick_info {
  my $self = shift;
  my $nick = u_irc ( $_[0] ) || return undef;

  unless ( $self->_nick_exists($nick) ) {
	return undef;
  }

  my ($record) = $self->{STATE}->{Nicks}->{ $nick };

  my (%result) = %{ $record };

  $result{Userhost} = $result{User} . '@' . $result{Host};

  delete ( $result{'CHANS'} );

  return \%result;
}

sub nick_long_form {
  my $self = shift;
  my $nick = u_irc ( $_[0] ) || return undef;

  unless ( $self->_nick_exists($nick) ) {
	return undef;
  }

  my ($record) = $self->{STATE}->{Nicks}->{ $nick };

  return $record->{Nick} . '!' . $record->{User} . '@' . $record->{Host};
}

sub nick_channels {
  my $self = shift;
  my $nick = u_irc ( $_[0] ) || return ();
  my @result;

  unless ( $self->_nick_exists($nick) ) {
	return @result;
  }

  foreach my $channel ( keys %{ $self->{STATE}->{Nicks}->{ $nick }->{CHANS} } ) {
	push ( @result, $self->{STATE}->{Chans}->{ $channel }->{Name} );
  }
  return @result;
}

sub channel_list {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return undef;
  my @result;

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  foreach my $nick ( keys %{ $self->{STATE}->{Chans}->{ $channel }->{Nicks} } ) {
	push( @result, $self->{STATE}->{Nicks}->{ $nick }->{Nick} );
  }

  return @result;
}

sub is_operator {
  my $self = shift;
  my $nick = u_irc ( $_[0] ) || return 0;

  unless ( $self->_nick_exists($nick) ) {
	return 0;
  }

  if ( $self->{STATE}->{Nicks}->{ $nick }->{IRCop} ) {
	return 1;
  }
  return 0;
}

sub is_channel_mode_set {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $mode = ( split //, $_[1] )[0] || return 0;

  $mode =~ s/[^A-Za-z]//g;

  unless ( $self->_channel_exists($channel) or $mode ) {
	return 0;
  }

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Mode} ) and $self->{STATE}->{Chans}->{ $channel }->{Mode} =~ /$mode/ ) {
	return 1;
  }
  return 0;
}

sub channel_limit {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return undef;

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  if ( $self->is_channel_mode_set($channel,'l') and defined ( $self->{STATE}->{Chans}->{ $channel }->{ChanLimit} ) ) {
	return $self->{STATE}->{Chans}->{ $channel }->{ChanLimit};
  }
  return undef;
}

sub channel_key {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return undef;

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  if ( $self->is_channel_mode_set($channel,'k') and defined ( $self->{STATE}->{Chans}->{ $channel }->{ChanKey} ) ) {
	return $self->{STATE}->{Chans}->{ $channel }->{ChanKey};
  }
  return undef;
}

sub channel_modes {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return undef;

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Mode} ) ) {
	return $self->{STATE}->{Chans}->{ $channel }->{Mode};
  }
  return undef;
}

sub is_channel_member {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;

  unless ( $self->_channel_exists($channel) and $self->_nick_exists($nick) ) {
	return 0;
  }

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $nick } ) ) {
	return 1;
  }
  return 0;
}

sub is_channel_operator {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'o') ) {
	return 0;
  }
  return 1;
}

sub has_channel_voice {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'v') ) {
	return 0;
  }
  return 1;
}

sub is_channel_halfop {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'h') ) {
	return 0;
  }
  return 1;
}

sub is_channel_owner {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'q') ) {
        return 0;
  }
  return 1;
}

sub is_channel_admin {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return 0;
  my $nick = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'a') ) {
        return 0;
  }
  return 1;
}

sub ban_mask {
  my $self = shift;
  my $channel = u_irc ( $_[0] ) || return undef;
  my $mask = parse_ban_mask ( $_[1] ) || return undef;
  my @result;

  unless ( $self->_channel_exists($channel) ) {
	return @result;
  }

  # Convert the mask from IRC to regex.
  $mask = u_irc ( $mask );
  $mask = quotemeta $mask;
  $mask =~ s/\\\*/[\x01-\xFF]{0,}/g;
  $mask =~ s/\\\?/[\x01-\xFF]{1,1}/g;

  foreach my $nick ( $self->channel_list($channel) ) {
	if ( u_irc ( $self->nick_long_form($nick) ) =~ /^$mask$/ ) {
		push ( @result, $nick );
	}
  }

  return @result;
}

1;

=head1 NAME

POE::Component::IRC::State - a fully event-driven IRC client module with channel/nick tracking.

=head1 SYNOPSIS

  # A simple Rot13 'encryption' bot

  use strict;
  use warnings;
  use POE qw(Component::IRC::State);

  my $nickname = 'Flibble' . $$;
  my $ircname = 'Flibble the Sailor Bot';
  my $ircserver = 'irc.blahblahblah.irc';
  my $port = 6667;

  my @channels = ( '#Blah', '#Foo', '#Bar' );

  # We create a new PoCo-IRC object and component.
  my $irc = POE::Component::IRC::State->spawn( 
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

    # In any irc_* events SENDER will be the PoCo-IRC session
    $kernel->post( $sender => join => $_ ) for @channels;
    undef;
  }

  sub irc_public {
    my ($kernel,$sender,$who,$where,$what) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    my $poco_object = $sender->get_heap();

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

POE::Component::IRC::State is a sub-class of L<POE::Component::IRC|POE::Component::IRC>
which tracks IRC state entities such as nicks and channels. See the documentation for
L<POE::Component::IRC|POE::Component::IRC> for general usage. This document covers the
extra methods that POE::Component::IRC::State provides.

The component tracks channels and nicks, so that it always has a current snapshot of what
channels it is on and who else is on those channels. The returned object provides methods
to query the collected state.

=head1 METHODS

All of the L<POE::Component::IRC|POE::Component::IRC> methods are supported, plus the following:

=over

=item channels

Takes no parameters. Returns a hashref, keyed on channel name and whether the bot is operator, halfop or 
has voice on that channel.

	foreach my $channel ( keys %{ $irc->channels() } ) {
		$irc->yield( 'privmsg' => $channel => 'm00!' );
	}

If the component happens to not be on any channels an empty hashref is returned.

=item nicks

Takes no parameters. Returns a list of all the nicks, including itself, that it knows about. If the component
happens to be on no channels then an empty list is returned.

=item channel_list

Expects a channel as parameter. Returns a list of all nicks on the specified channel. If the component happens
to not be on that channel an empty list will be returned.

=item is_operator

Expects a nick as parameter. Returns 1 if the specified nick is an IRC operator or 0 otherwise. If the nick does
not exist in the state then a 0 will be returned.

=item is_channel_mode_set

Expects a channel and a single mode flag [A-Za-z]. Returns 1 if that mode is set on the channel, 0 otherwise.

=item channel_modes

Expects a channel as parameter. Returns channel modes or undef.

=item channel_limit

Expects a channel as parameter. Returns the channel limit or undef.

=item channel_key

Expects a channel as parameter. Returns the channel key or undef.

=item is_channel_member

Expects a channel and a nickname as parameters. Returns 1 if the specified nick is on the specified channel or 0
otherwise. If either channel or nick does not exist in the state then a 0 will be returned.

=item is_channel_operator

Expects a channel and a nickname as parameters. Returns 1 if the specified nick is an operator on the specified channel or 0
otherwise. If either channel or nick does not exist in the state then a 0 will be returned.

=item is_channel_halfop

Expects a channel and a nickname as parameters. Returns 1 if the specified nick is a half-op on the specified channel or 0
otherwise. If either channel or nick does not exist in the state then a 0 will be returned.

=item has_channel_voice

Expects a channel and a nickname as parameters. Returns 1 if the specified nick has voice on the specified channel or 0
otherwise. If either channel or nick does not exist in the state then a 0 will be returned.

=item nick_long_form

Expects a nickname. Returns the long form of that nickname, ie. <nick>!<user>@<host> or undef if the nick is not in the state.

=item nick_channels

Expects a nickname. Returns a list of the channels that that nickname and the component are on. An empty list
will be returned if the nickname does not exist in the state.

=item nick_info

Expects a nickname. Returns a hashref containing similar information to that returned by WHOIS. Returns an undef
if the nickname doesn't exist in the state. The hashref contains the following keys: 'Nick', 'User', 'Host', 'Userhost', 'Server' and, if applicable, 'IRCop'.

=item ban_mask

Expects a channel and a ban mask, as passed to MODE +b-b. Returns a list of nicks on that channel that match the specified
ban mask or an empty list if the channel doesn't exist in the state or there are no matches.

=back

=head1 OUTPUT

As well as all the usual L<POE::Component::IRC|POE::Component::IRC> 'irc_*' events, there are the following events you can register for:

=over

=item irc_chan_sync

Sent whenever the component has completed synchronising a channel that it has joined. ARG0 is the channel name.

=item irc_nick_sync

Sent whenever the component has completed synchronising a user who has joined a channel the component is on.
ARG0 is the user's nickname.

=back

The following two 'irc_*' events are the same as their L<POE::Component::IRC|POE::Component::IRC> counterparts,
with the additional parameters:

=over

=item irc_quit

ARG2 contains an arrayref of channel names that are common to the quitting client and the component.

=item irc_nick

ARG2 contains an arrayref of channel names that are common to the nick changing client and the component.

=back

=head1 CAVEATS

The component gathers information by registering for 'irc_quit', 'irc_nick', 'irc_join', 'irc_part', 'irc_mode', 'irc_kick' and
various numeric replies. When the component is asked to join a channel, when it joins it will issue a 'WHO #channel' and a 'MODE #channel'. These will solicit between them the numerics, 'irc_352' and 'irc_324'.
You may want to ignore these. When someones joins a channel the bot is on, it issues a 'WHO nick'.

=head1 AUTHOR

Chris Williams <chris@bingosnet.co.uk>

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>
