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

$VERSION = '1.9';

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
  my $mapping = $irc->isupport('CASEMAPPING');
  my $nick = ( split /!/, ${ $_[0] } )[0];
  my $userhost = ( split /!/, ${ $_[0] } )[1];
  my ($user,$host) = split(/\@/,$userhost);
  my $channel = ${ $_[1] };
  my $uchan = u_irc $channel, $mapping;
  my $unick = u_irc $nick, $mapping;

  if ( $unick eq u_irc ( $self->nick_name(), $mapping ) ) {
	delete $self->{STATE}->{Chans}->{ $uchan };
	$self->{CHANNEL_SYNCH}->{ $uchan } = { MODE => 0, WHO => 0, BAN => 0, _time => time() };
        $self->{STATE}->{Chans}->{ $uchan } = { Name => $channel, Mode => '' };
        $self->yield ( 'who' => $channel );
        $self->yield ( 'mode' => $channel );
        $self->yield ( 'mode' => $channel => 'b');

  } else {
        $self->yield ( 'who' => $nick );
        $self->{STATE}->{Nicks}->{ $unick }->{Nick} = $nick;
        $self->{STATE}->{Nicks}->{ $unick }->{User} = $user;
        $self->{STATE}->{Nicks}->{ $unick }->{Host} = $host;
        $self->{STATE}->{Nicks}->{ $unick }->{CHANS}->{ $uchan } = '';
        $self->{STATE}->{Chans}->{ $uchan }->{Nicks}->{ $unick } = '';
	push @{ $self->{NICK_SYNCH}->{ $unick } }, $channel;
  }
  return PCI_EAT_NONE;
}

# Channel PART messages
sub S_part {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $nick = u_irc ( ( split /!/, ${ $_[0] } )[0], $mapping );
  my $channel = u_irc ${ $_[1] }, $mapping;

  if ( $nick eq u_irc ( $self->nick_name(), $mapping ) ) {
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
  my $mapping = $irc->isupport('CASEMAPPING');
  my $nick = ( split /!/, ${ $_[0] } )[0];
  push @{ $_[2] }, [ $self->nick_channels( $nick ) ];
  my $unick = u_irc $nick, $mapping;

  if ( $unick eq u_irc ( $self->nick_name(), $mapping ) ) {
        delete $self->{STATE};
  } else {
        foreach my $channel ( keys %{ $self->{STATE}->{Nicks}->{ $unick }->{CHANS} } ) {
                delete $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $unick };
        }
        delete $self->{STATE}->{Nicks}->{ $unick };
  }
  return PCI_EAT_NONE;
}

# Channel KICK messages
sub S_kick {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $channel = ${ $_[1] };
  my $nick = ${ $_[2] };
  my $unick = u_irc $nick, $mapping;
  my $uchan = u_irc $channel, $mapping;

  if ( $unick eq u_irc ( $self->nick_name(), $mapping ) ) {
        delete $self->{STATE}->{Nicks}->{ $unick }->{CHANS}->{ $uchan };
        delete $self->{STATE}->{Chans}->{ $uchan }->{Nicks}->{ $unick };
        foreach my $member ( keys %{ $self->{STATE}->{Chans}->{ $uchan }->{Nicks} } ) {
           delete $self->{STATE}->{Nicks}->{ $member }->{CHANS}->{ $uchan };
           if ( scalar keys %{ $self->{STATE}->{Nicks}->{ $member }->{CHANS} } <= 0 ) {
                delete $self->{STATE}->{Nicks}->{ $member };
           }
        }
	delete $self->{STATE}->{Chans}->{ $uchan };
  } else {
        delete $self->{STATE}->{Nicks}->{ $unick }->{CHANS}->{ $uchan };
        delete $self->{STATE}->{Chans}->{ $uchan }->{Nicks}->{ $unick };
        if ( scalar keys %{ $self->{STATE}->{Nicks}->{ $unick }->{CHANS} } <= 0 ) {
                delete $self->{STATE}->{Nicks}->{ $unick };
        }
  }
  return PCI_EAT_NONE;
}

# NICK changes
sub S_nick {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $nick = ( split /!/, ${ $_[0] } )[0];
  my $new = ${ $_[1] };
  push @{ $_[2] }, [ $self->nick_channels( $nick ) ];
  my $unick = u_irc $nick, $mapping;
  my $unew = u_irc $new, $mapping;

  $self->{RealNick} = $new if $nick eq $self->{RealNick};

  if ( $unick eq $unew ) {
        # Case Change
        $self->{STATE}->{Nicks}->{ $unick }->{Nick} = $new;
  } else {
        my $record = delete $self->{STATE}->{Nicks}->{ $unick };
        $record->{Nick} = $new;
        foreach my $channel ( keys %{ $record->{CHANS} } ) {
           $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $unew } = $record->{CHANS}->{ $channel };
           delete $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $unick };
        }
        $self->{STATE}->{Nicks}->{ $unew } = $record;
  }
  return PCI_EAT_NONE;
}

sub S_chan_mode {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $who = ${ $_[0] };
  my $channel = ${ $_[1] };
  my $mynick = u_irc $self->nick_name(), $mapping;
  pop @_;
  my $mode = ${ $_[2] };
  my $arg = ${ $_[3] };
  return PCI_EAT_NONE unless $mynick = u_irc( $arg, $mapping ) and $mode =~ /\+[qoah]/;
  my $excepts = $irc->isupport('EXCEPTS');
  my $invex = $irc->isupport('INVEX');
  $irc->yield ( 'mode' => $channel => $excepts ) if $excepts;
  $irc->yield ( 'mode' => $channel => $invex ) if $invex;
  return PCI_EAT_NONE;
}

# Channel MODE
sub S_mode {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $who = ${ $_[0] };
  my $channel = ${ $_[1] };
  my $uchan = u_irc $channel, $mapping;
  pop @_;
  my @modes = map { ${ $_ } } @_[2 .. $#_];

  # CHANMODES is [$list_mode, $always_arg, $arg_when_set, $no_arg]
  # A $list_mode always has an argument
  my $statmodes = join '', keys %{ $irc->isupport('PREFIX') };
  my $chanmodes = $irc->isupport('CHANMODES');
  my $alwaysarg = join '', $statmodes,  @{ $chanmodes }[0 .. 1];

  # Do nothing if it is UMODE
  if ( $uchan ne u_irc ( $self->{RealNick}, $mapping ) ) {
     my $parsed_mode = parse_mode_line( @modes );
     while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
        my $arg;
        $arg = shift ( @{ $parsed_mode->{args} } ) if ( $mode =~ /^(.[$alwaysarg]|\+[$chanmodes->[2]])/ );

        $self->_send_event( 'irc_chan_mode', $who, $channel, $mode, $arg );

        SWITCH: {
          if ( $mode =~ /\+([$statmodes])/ ) {
                my $flag = $1;
		$arg = u_irc $arg, $mapping;
                unless ($self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan }and $self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan } =~ /$flag/) {
                      $self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan } .= $flag;
                      $self->{STATE}->{Chans}->{ $uchan }->{Nicks}->{ $arg } = $self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan };
                }
                last SWITCH;
          }
          if ( $mode =~ /-([$statmodes])/ ) {
                my $flag = $1;
		$arg = u_irc $arg, $mapping;
                if ($self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan } =~ /$flag/) {
                      $self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan } =~ s/$flag//;
                      $self->{STATE}->{Chans}->{ $uchan }->{Nicks}->{ $arg } = $self->{STATE}->{Nicks}->{ $arg }->{CHANS}->{ $uchan };
                }
                last SWITCH;
          }
          if ( $mode =~ /\+([$chanmodes->[0]])/ ) {
                my $flag = $1;
                $self->{STATE}->{Chans}->{ $uchan }->{Lists}->{ $flag }->{ $arg } = { SetBy => $who, SetAt => time() };
                last SWITCH;
          }
          if ( $mode =~ /-([$chanmodes->[0]])/ ) {
                my $flag = $1;
                delete $self->{STATE}->{Chans}->{ $uchan }->{Lists}->{ $flag }->{ $arg };
                last SWITCH;
          }

          # All unhandled modes with arguments
          if ( $mode =~ /\+([^$chanmodes->[3]])/ ) {
                my $flag = $1;
                $self->{STATE}->{Chans}->{ $uchan }->{Mode} .= $flag unless $self->{STATE}->{Chans}->{ $uchan }->{Mode} =~ /$flag/;
                $self->{STATE}->{Chans}->{ $uchan }->{ModeArgs}->{ $flag } = $arg;
                last SWITCH;
          }
          if ( $mode =~ /-([^$chanmodes->[3]])/ ) {
                my $flag = $1;
                $self->{STATE}->{Chans}->{ $uchan }->{Mode} =~ s/$flag//;
                delete $self->{STATE}->{Chans}->{ $uchan }->{ModeArgs}->{ $flag };
                last SWITCH;
          }

          # Anything else doesn't have arguments so just adjust {Mode} as necessary.
          if ( $mode =~ /^\+(.)/ ) {
                my $flag = $1;
                $self->{STATE}->{Chans}->{ $uchan }->{Mode} .= $flag unless $self->{STATE}->{Chans}->{ $uchan }->{Mode} =~ /$flag/;
                last SWITCH;
          }
          if ( $mode =~ /^-(.)/ ) {
                my $flag = $1;
                if ($self->{STATE}->{Chans}->{ $uchan }->{Mode} =~ /$flag/) {
                      $self->{STATE}->{Chans}->{ $uchan }->{Mode} =~ s/$flag//;
                }
                last SWITCH;
          }
        }
     }
     # Lets make the channel mode nice
     if ( $self->{STATE}->{Chans}->{ $uchan }->{Mode} ) {
        $self->{STATE}->{Chans}->{ $uchan }->{Mode} = join('', sort {uc $a cmp uc $b} ( split( //, $self->{STATE}->{Chans}->{ $uchan }->{Mode} ) ) );
     } else {
        delete $self->{STATE}->{Chans}->{ $uchan }->{Mode};
     }
  }
  return PCI_EAT_NONE;
}

sub S_topic {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $who = ${ $_[0] };
  my $channel = ${ $_[1] };
  my $uchan = u_irc $channel, $mapping;
  my $topic = ${ $_[2] };

  $self->{STATE}->{Chans}->{ $uchan }->{Topic} = { Value => $topic, SetBy => $who, SetAt => time() };

  return PCI_EAT_NONE;  
}

# RPL_WHOREPLY
sub S_352 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my ($channel,$user,$host,$server,$nick,$status,$second) = @{ ${ $_[2] } };
  my $real = substr($second,index($second," ")+1);
  my $unick = u_irc $nick, $mapping;
  my $uchan = u_irc $channel, $mapping;

  $self->{STATE}->{Nicks}->{ $unick }->{Nick} = $nick;
  $self->{STATE}->{Nicks}->{ $unick }->{User} = $user;
  $self->{STATE}->{Nicks}->{ $unick }->{Host} = $host;
  $self->{STATE}->{Nicks}->{ $unick }->{Real} = $real;
  $self->{STATE}->{Nicks}->{ $unick }->{Server} = $server;
  if ( $channel ne '*' ) {
    my $whatever = '';
    my $existing = $self->{STATE}->{Nicks}->{ $unick }->{CHANS}->{ $uchan } || '';    
    my $prefix = $irc->isupport('PREFIX');
    foreach my $mode ( keys %{ $prefix } ) {
      $whatever .= $mode if ( $status =~ /\Q$prefix->{$mode}/ and $existing !~ /\Q$prefix->{$mode}/ );
    }
    $existing .= $whatever unless $existing and $existing =~ /$whatever/;
    $self->{STATE}->{Nicks}->{ $unick }->{CHANS}->{ $uchan } = $existing;
    $self->{STATE}->{Chans}->{ $uchan }->{Nicks}->{ $unick } = $existing;
    $self->{STATE}->{Chans}->{ $uchan }->{Name} = $channel;
  }
  if ( $status =~ /\*/ ) {
    $self->{STATE}->{Nicks}->{ $unick }->{IRCop} = 1;
  }
  return PCI_EAT_NONE;
}

#RPL_ENDOFWHO
sub S_315 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my $channel = ( split / :/, ${ $_[1] } )[0];
  my $channel = ${ $_[2] }->[0];
  my $uchan = u_irc $channel, $mapping;

  # If it begins with #, &, + or ! its a channel apparently. RFC2812.
  if ( $channel =~ /^[\x23\x2B\x21\x26]/ ) {
    if ( $self->_channel_sync($channel, 'WHO') ) {
	my $rec = delete $self->{CHANNEL_SYNCH}->{ $uchan };
	$self->_send_event( 'irc_chan_sync', $channel, time() - $rec->{_time} );
    }
  # Otherwise we assume its a nickname
  } else {
	my $chan = shift @{ $self->{NICK_SYNCH}->{ $uchan } };
	delete $self->{NICK_SYNCH}->{ $uchan } unless scalar @{ $self->{NICK_SYNCH}->{ $uchan } };
	$self->_send_event( 'irc_nick_sync', $channel, $chan );
  }
  return PCI_EAT_NONE;
}

# RPL_BANLIST
sub S_367 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;
  my ($mask, $who, $when) = @args;

  $self->{STATE}->{Chans}->{ $uchan }->{Lists}->{b}->{ $mask } = { SetBy => $who, SetAt => $when };
  return PCI_EAT_NONE;
}

# RPL_ENDOFBANLIST
sub S_368 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;

  if ( $self->_channel_sync($channel, 'BAN') ) {
	my $rec = delete $self->{CHANNEL_SYNCH}->{ $uchan };
	$self->_send_event( 'irc_chan_sync', $channel, time() - $rec->{_time} );
  }
  return PCI_EAT_NONE;
}

# RPL_INVITELIST
sub S_346 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;
  my ($mask, $who, $when) = @args;
  my $invex = $irc->isupport('INVEX');

  $self->{STATE}->{Chans}->{ $uchan }->{Lists}->{ $invex }->{ $mask } = { SetBy => $who, SetAt => $when };
  return PCI_EAT_NONE;
}

# RPL_ENDOFINVITELIST
sub S_347 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;
  $self->_send_event( 'irc_chan_sync_invex', $channel );
  return PCI_EAT_NONE;
}

# RPL_EXCEPTLIST
sub S_348 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;
  my ($mask, $who, $when) = @args;
  my $excepts = $irc->isupport('EXCEPTS');

  $self->{STATE}->{Chans}->{ $uchan }->{Lists}->{ $excepts }->{ $mask } = { SetBy => $who, SetAt => $when };
  return PCI_EAT_NONE;
}

# RPL_ENDOFEXCEPTLIST
sub S_349 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;
  $self->_send_event( 'irc_chan_sync_excepts', $channel );
  return PCI_EAT_NONE;
}

# RPL_CHANNELMODEIS
sub S_324 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my $channel = shift @args;
  my $uchan = u_irc $channel, $mapping;
  my $chanmodes = $irc->isupport('CHANMODES');

  my $parsed_mode = parse_mode_line( @args );
  while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
        $mode =~ s/\+//;
        my $arg;
        $arg = shift @{ $parsed_mode->{args} } if $mode =~ /[^$chanmodes->[3]]/; # doesn't match a mode with no args
	if ( $self->{STATE}->{Chans}->{ $uchan }->{Mode} ) {
          $self->{STATE}->{Chans}->{ $uchan }->{Mode} .= $mode unless $self->{STATE}->{Chans}->{ $uchan }->{Mode} =~ /$mode/;
	} else {
	  $self->{STATE}->{Chans}->{ $uchan }->{Mode} = $mode;
	}
        $self->{STATE}->{Chans}->{ $uchan }->{ModeArgs}->{ $mode } = $arg if defined ( $arg );
  }
  if ( $self->{STATE}->{Chans}->{ $uchan }->{Mode} ) {
        $self->{STATE}->{Chans}->{ $uchan }->{Mode} = join('', sort {uc $a cmp uc $b} split //, $self->{STATE}->{Chans}->{ $uchan }->{Mode} );
  }
  if ( $self->_channel_sync($channel, 'MODE') ) {
	my $rec = delete $self->{CHANNEL_SYNCH}->{ $uchan };
	$self->_send_event( 'irc_chan_sync', $channel, time() - $rec->{_time} );
  }
  return PCI_EAT_NONE;
}

# RPL_TOPIC
sub S_332 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  my $channel = ${ $_[2] }->[0];
  my $topic = ${ $_[2] }->[1];
  my $uchan = u_irc $channel, $mapping;

  $self->{STATE}->{Chans}->{ $uchan }->{Topic}->{Value} = $topic;

  return PCI_EAT_NONE;
}

# RPL_TOPICWHOTIME
sub S_333 {
  my ($self,$irc) = splice @_, 0, 2;
  my $mapping = $irc->isupport('CASEMAPPING');
  #my @args = split / /, ${ $_[1] };
  my @args = @{ ${ $_[2] } };
  my ($channel, $who, $when) = @args;
  my $uchan = u_irc $channel, $mapping;

  $self->{STATE}->{Chans}->{ $uchan }->{Topic}->{SetBy} = $who;
  $self->{STATE}->{Chans}->{ $uchan }->{Topic}->{SetAt} = $when;

  return PCI_EAT_NONE;
}

# Methods for STATE query
# Internal methods begin with '_'
#

sub _channel_sync {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $sync = $_[1];

  return 0 unless ( $self->_channel_exists($channel) and defined ( $self->{CHANNEL_SYNCH}->{ $channel } ) );

  $self->{CHANNEL_SYNCH}->{ $channel }->{ $sync } = 1 if $sync;

  foreach my $item ( qw(BAN MODE WHO) ) {
	return 0 unless $self->{CHANNEL_SYNCH}->{ $channel }->{ $item };
  }

  return 1;
}

sub _nick_exists {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $nick = u_irc ( $_[0], $mapping ) || return 0;
  return 1 if defined $self->{STATE}->{Nicks}->{ $nick };
  return 0;
}

sub _channel_exists {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  return 1 if defined $self->{STATE}->{Chans}->{ $channel };
  return 0;
}

sub _nick_has_channel_mode {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  my $flag = ( split //, $_[2] )[0] || return 0;

  return 0 unless $self->is_channel_member($channel,$nick);

  if ( $self->{STATE}->{Nicks}->{ $nick }->{CHANS}->{ $channel } =~ /$flag/ ) {
	return 1;
  }
  return 0;
}

# Returns all the channels that the bot is on with an indication of whether it has operator, halfop or voice.
sub channels {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my %result;
  my $realnick = u_irc $self->{RealNick}, $mapping;

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
	push @result, $self->{STATE}->{Nicks}->{ $nick }->{Nick};
  }
  return @result;
}

sub nick_info {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $nick = u_irc ( $_[0], $mapping ) || return;

  return unless $self->_nick_exists($nick);

  my $record = $self->{STATE}->{Nicks}->{ $nick };

  my %result = %{ $record };

  $result{Userhost} = $result{User} . '@' . $result{Host};

  delete $result{'CHANS'};

  return \%result;
}

sub nick_long_form {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $nick = u_irc ( $_[0], $mapping ) || return;

  return unless $self->_nick_exists($nick);

  my $record = $self->{STATE}->{Nicks}->{ $nick };

  return $record->{Nick} . '!' . $record->{User} . '@' . $record->{Host};
}

sub nick_channels {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $nick = u_irc ( $_[0], $mapping ) || return;
  my @result;

  return unless $self->_nick_exists($nick);

  foreach my $channel ( keys %{ $self->{STATE}->{Nicks}->{ $nick }->{CHANS} } ) {
	push ( @result, $self->{STATE}->{Chans}->{ $channel }->{Name} );
  }
  return @result;
}

sub channel_list {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return;
  my @result;

  return unless $self->_channel_exists($channel);

  foreach my $nick ( keys %{ $self->{STATE}->{Chans}->{ $channel }->{Nicks} } ) {
	push @result, $self->{STATE}->{Nicks}->{ $nick }->{Nick};
  }

  return @result;
}

sub is_operator {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $nick = u_irc ( $_[0], $mapping ) || return;
  return unless $self->_nick_exists($nick);
  return 1 if $self->{STATE}->{Nicks}->{ $nick }->{IRCop};
  return 0;
}

sub is_channel_mode_set {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $mode = ( split //, $_[1] )[0] || return 0;

  $mode =~ s/[^A-Za-z]//g;

  return unless $self->_channel_exists($channel) or $mode;

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Mode} ) and $self->{STATE}->{Chans}->{ $channel }->{Mode} =~ /$mode/ ) {
	return 1;
  }
  return 0;
}

sub channel_limit {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;

  return unless $self->_channel_exists($channel);

  if ( $self->is_channel_mode_set($channel,'l') and defined ( $self->{STATE}->{Chans}->{ $channel }->{ModeArgs}->{l} ) ) {
	return $self->{STATE}->{Chans}->{ $channel }->{ModeArgs}->{l};
  }
  return undef;
}

sub channel_key {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;

  return unless $self->_channel_exists($channel);

  if ( $self->is_channel_mode_set($channel,'k') and defined ( $self->{STATE}->{Chans}->{ $channel }->{ModeArgs}->{k} ) ) {
	return $self->{STATE}->{Chans}->{ $channel }->{ModeArgs}->{k};
  }
  return undef;
}

sub channel_modes {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;

  return unless $self->_channel_exists($channel);

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Mode} ) ) {
	return $self->{STATE}->{Chans}->{ $channel }->{Mode};
  }
  return undef;
}

sub is_channel_member {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  return unless $self->_channel_exists($channel) and $self->_nick_exists($nick);
  return 1 if defined $self->{STATE}->{Chans}->{ $channel }->{Nicks}->{ $nick };
  return 0;
}

sub is_channel_operator {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  return 0 unless $self->_nick_has_channel_mode($channel,$nick,'o');
  return 1;
}

sub has_channel_voice {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  return 0 unless $self->_nick_has_channel_mode($channel,$nick,'v');
  return 1;
}

sub is_channel_halfop {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  return 0 unless $self->_nick_has_channel_mode($channel,$nick,'h');
  return 1;
}

sub is_channel_owner {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  return 0 unless $self->_nick_has_channel_mode($channel,$nick,'q');
  return 1;
}

sub is_channel_admin {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return 0;
  my $nick = u_irc ( $_[1], $mapping ) || return 0;
  return 0 unless $self->_nick_has_channel_mode($channel,$nick,'a');
  return 1;
}

sub ban_mask {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return undef;
  my $mask = parse_ban_mask ( $_[1] ) || return undef;
  my @result;

  return unless $self->_channel_exists($channel);

  # Convert the mask from IRC to regex.
  $mask = u_irc ( $mask, $mapping );
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

sub channel_ban_list {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return undef;
  my %result;

  return undef unless $self->_channel_exists($channel);

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Lists}->{b} ) ) {
    %result = %{ $self->{STATE}->{Chans}->{ $channel }->{Lists}->{b} };
  }

  return \%result;
}

sub channel_except_list {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return undef;
  my $excepts = $self->isupport('EXCEPTS');
  my %result;

  return undef unless $self->_channel_exists($channel);

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Lists}->{ $excepts } ) ) {
    %result = %{ $self->{STATE}->{Chans}->{ $channel }->{Lists}->{ $excepts } };
  }

  return \%result;
}

sub channel_invex_list {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return undef;
  my $invex = $self->isupport('INVEX');
  my %result;

  return undef unless $self->_channel_exists($channel);

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Lists}->{ $invex } ) ) {
    %result = %{ $self->{STATE}->{Chans}->{ $channel }->{Lists}->{ $invex } };
  }

  return \%result;
}

sub channel_topic {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return undef;
  my %result;

  return undef unless $self->_channel_exists($channel);

  if ( defined ( $self->{STATE}->{Chans}->{ $channel }->{Topic} ) ) {
    %result = %{ $self->{STATE}->{Chans}->{ $channel }->{Topic} };
  }

  return \%result;
}

sub nick_channel_modes {
  my $self = shift;
  my $mapping = $self->isupport('CASEMAPPING');
  my $channel = u_irc ( $_[0], $mapping ) || return undef;
  my $nick = u_irc ( $_[1], $mapping ) || return undef;

  return undef unless $self->is_channel_member($channel, $nick);

  return $self->{STATE}->{Nicks}->{ $nick }->{CHANS}->{ $channel };
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

All of the L<POE::Component::IRC> methods are supported, plus the following:

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

=item is_channel_owner

Expects a channel and a nickname as parameters. Returns 1 if the specified nick is an owner on the specified channel or 0
otherwise. If either channel or nick does not exist in the state then a 0 will be returned.

=item is_channel_admin

Expects a channel and a nickname as parameters. Returns 1 if the specified nick is an admin on the specified channel or 0
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
if the nickname doesn't exist in the state. The hashref contains the following keys: 'Nick', 'User', 'Host', 'Userhost', 'Real', 'Server' and, if applicable, 'IRCop'.

=item ban_mask

Expects a channel and a ban mask, as passed to MODE +b-b. Returns a list of nicks on that channel that match the specified
ban mask or an empty list if the channel doesn't exist in the state or there are no matches.

=item channel_ban_list

Expects a channel as a parameter. Returns a hashref containing the banlist if the channel is in the state, undef if not.
The hashref keys are the entries on the list, each with the keys 'SetBy' and 'SetAt'. These keys will hold the nick!hostmask of
the user who set the entry (or just the nick if it's all the ircd gives us), and the time at which it was set respectively.

=item channel_invex_list

Expects a channel as a parameter. Returns a hashref containing the invite exception list if the channel is in the state, undef if not.
The hashref keys are the entries on the list, each with the keys 'SetBy' and 'SetAt'. These keys will hold the nick!hostmask of
the user who set the entry (or just the nick if it's all the ircd gives us), and the time at which it was set respectively.

=item channel_except_list                                             

Expects a channel as a parameter. Returns a hashref containing the ban exception list if the channel is in the state, undef if not.
The hashref keys are the entries on the list, each with the keys 'SetBy' and 'SetAt'. These keys will hold the nick!hostmask of
the user who set the entry (or just the nick if it's all the ircd gives us), and the time at which it was set respectively.

=item channel_topic

Expects a channel as a parameter. Returns a hashref containing topic information if the channel is in the state, undef if not.
The hashref contains the following keys: 'Value', 'SetBy', 'SetAt'. These keys will hold the topic itself, the nick!hostmask of
the user who set it (or just the nick if it's all the ircd gives us), and the time at which it was set respectively.

=item nick_channel_modes

Expects a channel and a nickname as parameters. Returns the modes of the specified nick on the specified channel (ie. qaohv).
If the nick is not on the channel in the state, undef will be returned.

=back

=head1 OUTPUT

As well as all the usual L<POE::Component::IRC> 'irc_*' events, there are the following events you can register for:

=over

=item irc_chan_sync

Sent whenever the component has completed synchronising a channel that it has joined. ARG0 is the channel name and ARG1 is the time in seconds that the channel took to synchronise.

=item irc_chan_sync_invex

Sent whenever the component has completed synchronising a channel's INVEX ( invite list ). Usually triggered by the component being opped on a channel. ARG0 is the channel.

=item irc_chan_sync_excepts

Sent whenever the component has completed synchronising a channel's EXCEPTS ( ban exemption list ). Usually triggered by the component being opped on a channel. ARG0 is the channel.

=item irc_nick_sync

Sent whenever the component has completed synchronising a user who has joined a channel the component is on.
ARG0 is the user's nickname and ARG1 the channel they have joined.

=item irc_chan_mode

This is almost identical to irc_mode, except that it's sent once for each individual mode with it's respective
argument if it has one (ie. the banmask if it's +b or -b). However, this event is only sent for channel modes.

=back

The following two 'irc_*' events are the same as their L<POE::Component::IRC> counterparts,
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

Currently, whenever the component sees a topic or channel list change, it will use time() for the SetAt value and the full address of the user who set it for the SetBy value. When an ircd gives us it's record 
of such changes, it will use it's own time (obviously) and may only give us the nickname of the user, rather than their full address. Thus, if our time() and the ircd's time do not match, or the ircd uses the
nickname only, ugly inconsistencies can develop. This leaves the SetAt and SetBy values at best, inaccurate, and you should use them with this in mind (for now, at least).

=head1 AUTHOR

Chris Williams <chris@bingosnet.co.uk>

With contributions from the Kinky Black Goat.

=head1 LICENCE

This module may be used, modified, and distributed under the same
terms as Perl itself. Please see the license that came with your Perl
distribution for details.

=head1 SEE ALSO

L<POE::Component::IRC>
