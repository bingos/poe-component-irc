# Declare our package
package POE::Component::IRC::Plugin::State;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '0.01';

# Import the stuff from Plugin
use POE::Component::IRC::Plugin qw( PCI_EAT_NONE );

# The constructor
sub new {
	my $self = {
		'Nicks'		=>	{},
		'Chans'		=>	{},
		'irc'		=>	undef,
	};

	return bless $self, 'POE::Component::IRC::Plugin::State';
}

# Register ourself!
sub PCI_register {
	my( $self, $irc ) = @_;
	
	# Store the irc object
	$self->{irc} = $irc;

	# Register our events!
	$irc->plugin_register( $self, 'SERVER', qw( join part quit kick nick mode 352 324 ) );

	# All done!
	return 1;
}

# Unregister ourself!
sub PCI_unregister {
	my( $self, $irc ) = @_;

	# Remove the ref
	delete $self->{irc};
	
	# All done!
	return 1;
}

# Channel JOIN messages
sub S_join {
	my( $self, $irc, $whoref, $channelref ) = @_;
	my $channel = $$channelref;
	my $uchannel = u_irc( $channel );
	my( $nick, $userhost ) = ( split /!/, $$whoref )[0, 1];
	my $unick = u_irc( $nick );

	if ( $unick eq u_irc( $irc->nick_name() ) ) {
		delete $self->{Chans}->{ $uchannel };
		$irc->yield( 'who' => $channel );
		$irc->yield( 'mode' => $channel );
	} else {
		$irc->yield ( 'who' => $nick );
		my( $user, $host ) = split( /\@/, $userhost );

		$self->{Nicks}->{ $unick }->{Nick} = $nick;
		$self->{Nicks}->{ $unick }->{User} = $user;
		$self->{Nicks}->{ $unick }->{Host} = $host;
		$self->{Nicks}->{ $unick }->{CHANS}->{ $uchannel } = '';
		$self->{Chans}->{ $uchannel }->{Nicks}->{ $unick } = '';
	}

	return PCI_EAT_NONE;
}

# Channel PART messages
sub S_part {
	my( $self, $irc, $whoref, $channelref ) = @_;
	my $channel = $$channelref;
	my $uchannel = u_irc( $channel );
	my $nick = ( split /!/, $$whoref )[0];
	my $unick = u_irc( $nick );

	if ( $unick eq u_irc( $irc->nick_name() ) ) {
		delete $self->{Nicks}->{ $unick }->{CHANS}->{ $uchannel };
		delete $self->{Chans}->{ $uchannel }->{Nicks}->{ $unick };

		foreach my $member ( keys %{ $self->{Chans}->{ $uchannel }->{Nicks} } ) {
			delete $self->{Nicks}->{ u_irc( $member ) }->{CHANS}->{ $uchannel };

			if ( scalar ( keys %{ $self->{Nicks}->{ u_irc( $member ) }->{CHANS} } ) <= 0 ) {
			     delete $self->{Nicks}->{ u_irc( $member ) };
			}
		}
	} else {
		delete $self->{Nicks}->{ $unick }->{CHANS}->{ $uchannel };
		delete $self->{Chans}->{ $uchannel }->{Nicks}->{ $unick };

		if ( scalar ( keys %{ $self->{Nicks}->{ $unick }->{CHANS} } ) <= 0 ) {
			delete $self->{Nicks}->{ $unick };
		}
	}

	return PCI_EAT_NONE;
}

# QUIT messages
sub S_quit {
	my( $self, $irc, $whoref, $quitmsg ) = @_;
	my $nick = ( split /!/, $$whoref )[0];
	my $unick = u_irc( $nick );

	if ( $unick eq u_irc( $irc->nick_name() ) ) {
		delete $self->{Nicks};
		delete $self->{Chans};
	} else {
		foreach my $channel ( keys %{ $self->{Nicks}->{ $unick }->{CHANS} } ) {
			delete $self->{Chans}->{ $channel }->{Nicks}->{ $unick };
        	}

		delete $self->{Nicks}->{ $unick };
	}

	return PCI_EAT_NONE;
}

# Channel KICK messages
sub S_kick {
	my( $self, $irc, $kickref, $channelref, $nickref, $reason ) = @_;
	my $uchannel = u_irc( $$channelref );
	my $unick = u_irc( $$nickref );

	if ( $unick eq u_irc( $irc->nick_name() ) ) {
		delete $self->{Nicks}->{ $unick }->{CHANS}->{ $uchannel };
		delete $self->{Chans}->{ $uchannel }->{Nicks}->{ $unick };

		foreach my $member ( keys %{ $self->{Chans}->{ $uchannel }->{Nicks} } ) {
			delete $self->{Nicks}->{ u_irc( $member ) }->{CHANS}->{ $uchannel };

			if ( scalar ( keys %{ $self->{Nicks}->{ u_irc( $member ) }->{CHANS} } ) <= 0 ) {
				delete $self->{Nicks}->{ u_irc( $member ) };
			}
		}
	} else {
		delete $self->{Nicks}->{ $unick }->{CHANS}->{ $uchannel };
		delete $self->{Chans}->{ $uchannel }->{Nicks}->{ $unick };

		if ( scalar ( keys %{ $self->{Nicks}->{ $unick }->{CHANS} } ) <= 0 ) {
			delete $self->{Nicks}->{ $unick };
		}
	}

	return PCI_EAT_NONE;
}

# NICK changes
sub S_nick {
	my( $self, $irc, $whoref, $newref ) = @_;
	my $nick = ( split /!/, $$whoref )[0];
	my $unick = u_irc( $nick );
	my $unew = u_irc( $$newref );

	if ( $unick eq u_irc( $$newref ) ) {
		# Case Change
		$self->{Nicks}->{ $unick }->{Nick} = $$newref;
	} else {
		my $record = delete $self->{Nicks}->{ $unick };
		$record->{Nick} = $$newref;

		foreach my $channel ( keys %{ $record->{CHANS} } ) {
			$self->{Chans}->{ $channel }->{Nicks}->{ $unew } = $record->{CHANS}->{ $channel };
			delete $self->{Chans}->{ $channel }->{Nicks}->{ $unick };
		}

		$self->{Nicks}->{ $unew } = $record;
	}

	return PCI_EAT_NONE;
}

# Channel MODE
sub S_mode {
	my( $self, $irc, $whoref, $channelref, @rest ) = @_;
	my $uchannel = u_irc( $$channelref );

	# Make the modeline
	my @modeline = ();
	foreach my $e ( @rest ) {
		push( @modeline, $$e );
	}

	# Do nothing if it is UMODE
	if ( $uchannel ne u_irc( $irc->nick_name() ) ) {
		my $parsed_mode = parse_mode_line( @modeline );
		while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
			my $arg = shift ( @{ $parsed_mode->{args} } ) if ( $mode =~ /^(\+[hovklbIeaqfL]|-[hovbeIaq])/ );

			# Stupidly long pseudo-switch
			if ( $mode =~ /\+([ohvaq])/ ) {
				my $flag = $1;
				unless ( $self->{Nicks}->{ u_irc( $arg ) }->{CHANS}->{ $uchannel } =~ /$flag/ ) {
				      $self->{Nicks}->{ u_irc( $arg ) }->{CHANS}->{ $uchannel } .= $flag;
				      $self->{Chans}->{ $uchannel }->{Nicks}->{ u_irc( $arg ) } = $self->{Nicks}->{ u_irc( $arg ) }->{CHANS}->{ $uchannel };
				}
			} elsif ( $mode =~ /-([ohvaq])/ ) {
				my $flag = $1;
				if ( $self->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ $uchannel } =~ /$flag/ ) {
				      $self->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ $uchannel } =~ s/$flag//;
				      $self->{Chans}->{ $uchannel }->{Nicks}->{ u_irc ( $arg ) } = $self->{Nicks}->{ u_irc ( $arg ) }->{CHANS}->{ $uchannel };
				}
			} elsif ( $mode eq '+b' and defined $arg ) {
				# Add to banlist
				$self->{Chans}->{ $uchannel }->{BanList}->{ $arg } = 1;
			} elsif ( $mode eq '-b' and defined $arg ) {
				# Remove from banlist
				if ( exists $self->{Chans}->{ $uchannel }->{BanList}->{ $arg } ) {
					delete $self->{Chans}->{ $uchannel }->{BanList}->{ $arg };
				}
			} elsif ( $mode =~ /[IefL]/ ) {
				# Do nothing?
			} elsif ( $mode eq '+l' and defined ( $arg ) ) {
				$self->{Chans}->{ $uchannel }->{Mode} .= 'l' unless ( $self->{Chans}->{ $uchannel }->{Mode} =~ /l/ );
				$self->{Chans}->{ $uchannel }->{ChanLimit} = $arg;
			} elsif ( $mode eq '+k' and defined ( $arg ) ) {
				$self->{Chans}->{ $uchannel }->{Mode} .= 'k' unless ( $self->{Chans}->{ $uchannel }->{Mode} =~ /k/ );
				$self->{Chans}->{ $uchannel }->{ChanKey} = $arg;
			} elsif ( $mode eq '-l' ) {
				$self->{Chans}->{ $uchannel }->{Mode} =~ s/l//;
				$self->{Chans}->{ $uchannel }->{ChanLimit} = 0;
			} elsif ( $mode eq '-k' ) {
				$self->{Chans}->{ $uchannel }->{Mode} =~ s/k//;
				$self->{Chans}->{ $uchannel }->{ChanKey} = undef;
			} elsif ( $mode =~ /^\+(.)/ ) {
				my $flag = $1;
				$self->{Chans}->{ $uchannel }->{Mode} .= $flag unless ( $self->{Chans}->{ $uchannel }->{Mode} =~ /$flag/ );
			} elsif ( $mode =~ /^-(.)/ ) {
				my $flag = $1;
				$self->{Chans}->{ $uchannel }->{Mode} =~ s/$flag//;
			}
		}

		# Lets make the channel mode nice
		if ( $self->{Chans}->{ $uchannel }->{Mode} ) {
			$self->{Chans}->{ $uchannel }->{Mode} = join('', sort( split( //, $self->{Chans}->{ $uchannel }->{Mode} ) ) );
		} else {
			delete ( $self->{Chans}->{ $uchannel }->{Mode} );
		}
	}

	return PCI_EAT_NONE;
}

# RPL_WHOREPLY
sub S_352 {
	my( $self, $irc, $servernam, $lineref ) = @_;
	my( $first, $second ) = split( / :/, $$lineref );
	my( $channel, $user, $host, $server, $nick, $status ) = split( / /, $first );
	my $real = substr( $second, index( $second, " " ) + 1 );
	my $unick = u_irc( $nick );

	$self->{Nicks}->{ $unick }->{Nick} = $nick;
	$self->{Nicks}->{ $unick }->{User} = $user;
	$self->{Nicks}->{ $unick }->{Host} = $host;
	$self->{Nicks}->{ $unick }->{Real} = $real;
	$self->{Nicks}->{ $unick }->{Server} = $server;

	if ( $channel ne '*' ) {
		my $whatever = '';
		my $uchannel = u_irc( $channel );
		if ( $status =~ /\@/ ) { $whatever = 'o'; }
		if ( $status =~ /\+/ ) { $whatever = 'v'; }
		if ( $status =~ /\%/ ) { $whatever = 'h'; }
		$self->{Nicks}->{ $unick }->{CHANS}->{ $uchannel } = $whatever;
		$self->{Chans}->{ $uchannel }->{Name} = $channel;
		$self->{Chans}->{ $uchannel }->{Nicks}->{ $unick } = $whatever;
	}

	if ( $status =~ /\*/ ) {
		$self->{Nicks}->{ $unick }->{IRCop} = 1;
	}

	return PCI_EAT_NONE;
}

# RPL_CHANNELMODEIS
sub S_324 {
	my( $self, $irc, $server, $lineref ) = @_;
	my @args = split( / /, $$lineref );
	my $channel = shift @args;
	my $uchannel = u_irc( $channel );
	
	# Make sure we have something...
	if ( ! defined $self->{Chans}->{ $uchannel }->{Mode} ) {
		$self->{Chans}->{ $uchannel }->{Mode} = '';
	}

	my $parsed_mode = parse_mode_line( @args );
	while ( my $mode = shift ( @{ $parsed_mode->{modes} } ) ) {
		$mode =~ s/\+//;
		my $arg = shift ( @{ $parsed_mode->{args} } ) if ( $mode =~ /[kl]/ );
		$self->{Chans}->{ $uchannel }->{Mode} .= $mode unless ( $self->{Chans}->{ $uchannel }->{Mode} =~ /$mode/ );

		if ( $mode eq 'l' and defined ( $arg ) ) {
			$self->{Chans}->{ $uchannel }->{ChanLimit} = $arg;
		} elsif ( $mode eq 'k' and defined ( $arg ) ) {
			$self->{Chans}->{ $uchannel }->{ChanKey} = $arg;
		}
	}

	if ( $self->{Chans}->{ $uchannel }->{Mode} ) {
		$self->{Chans}->{ $uchannel }->{Mode} = join('', sort( split( //, $self->{Chans}->{ $uchannel }->{Mode} ) ) );
	}

	return PCI_EAT_NONE;
}

# Miscellaneous internal functions
# Returns IRC uppercase keys given a nickname or channel. {}|^ are lowercase []\~ as per RFC2812
sub u_irc {
	my ($value) = shift || return undef;

	$value =~ tr/a-z{}|^/A-Z[]\\~/;
	return $value;
}

# Given mode arguments as @_ this function returns a hashref, which contains the split up modes and args.
# Given @_ = ( '+ovb', 'lamebot', 'nickname', '*!*@*' )
# Returns { modes => [ '+o', '+v', '+b' ], args => [ 'lamebot', 'nickname', '*!*@*' ] }
sub parse_mode_line {
  my ($hashref) = { };

  my ($count) = 0;
  foreach my $arg ( @_ ) {
        if ( $arg =~ /^(\+|-)/ or $count == 0 ) {
           my ($action) = '+';
           foreach my $char ( split (//,$arg) ) {
                if ( $char eq '+' or $char eq '-' ) {
                   $action = $char;
                } else {
                   push ( @{ $hashref->{modes} }, $action . $char );
                }
           }
         } else {
                push ( @{ $hashref->{args} }, $arg );
         }
         $count++;
  }
  return $hashref;
}

sub parse_ban_mask {
  my ($arg) = shift || return undef;

  $arg =~ s/\x2a{2,}/\x2a/g;
  my (@ban); my ($remainder);
  if ( $arg !~ /\x21/ and $arg =~ /\x40/ ) {
     $remainder = $arg;
  } else {
     ($ban[0],$remainder) = split (/\x21/,$arg,2);
  }
  $remainder =~ s/\x21//g if ( defined ( $remainder ) );
  @ban[1..2] = split (/\x40/,$remainder,2) if ( defined ( $remainder ) );
  $ban[2] =~ s/\x40//g if ( defined ( $ban[2] ) );
  for ( my $i = 0; $i <= 2; $i++ ) {
    if ( ( not defined ( $ban[$i] ) ) or $ban[$i] eq '' ) {
       $ban[$i] = '*';
    }
  }
  return $ban[0] . '!' . $ban[1] . '@' . $ban[2];
}

# Methods for STATE query
# Internal methods begin with '_'
#

sub _nick_exists {
  my ($self) = shift;
  my ($nick) = u_irc ( $_[0] ) || return 0;

  if ( defined ( $self->{Nicks}->{ $nick } ) ) {
	return 1;
  }
  return 0;
}

sub _channel_exists {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;

  if ( defined ( $self->{Chans}->{ $channel } ) ) {
	return 1;
  }
  return 0;
}

sub _nick_has_channel_mode {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;
  my ($flag) = ( split //, $_[2] )[0] || return 0;

  unless ( $self->is_channel_member($channel,$nick) ) {
	return 0;
  }

  if ( $self->{Nicks}->{ $nick }->{CHANS}->{ $channel } =~ /$flag/ ) {
	return 1;
  }
  return 0;
}

# Returns all the channels that the bot is on with an indication of whether it has operator, halfop or voice.
sub channels {
  my ($self) = shift;
  my (%result);
  my ($realnick) = u_irc ( $self->{irc}->nick_name() );

  if ( $self->_nick_exists($realnick) ) {
	foreach my $channel ( keys %{ $self->{Nicks}->{ $realnick }->{CHANS} } ) {
	  $result{ $self->{Chans}->{ $channel }->{Name} } = $self->{Nicks}->{ $realnick }->{CHANS}->{ $channel };
	}
  }
  return \%result;
}

sub nicks {
  my ($self) = shift;
  my (@result);

  foreach my $nick ( keys %{ $self->{Nicks} } ) {
	push ( @result, $self->{Nicks}->{ $nick }->{Nick} );
  }
  return @result;
}

sub nick_info {
  my ($self) = shift;
  my ($nick) = u_irc ( $_[0] ) || return undef;

  unless ( $self->_nick_exists($nick) ) {
	return undef;
  }

  my ($record) = $self->{Nicks}->{ $nick };

  my (%result) = %{ $record };

  delete ( $result{'CHANS'} );

  return \%result;
}

sub nick_long_form {
  my ($self) = shift;
  my ($nick) = u_irc ( $_[0] ) || return undef;

  unless ( $self->_nick_exists($nick) ) {
	return undef;
  }

  my ($record) = $self->{Nicks}->{ $nick };

  return $record->{Nick} . '!' . $record->{User} . '@' . $record->{Host};
}

sub nick_channels {
  my ($self) = shift;
  my ($nick) = u_irc ( $_[0] ) || return ();
  my (@result);

  unless ( $self->_nick_exists($nick) ) {
	return @result;
  }

  foreach my $channel ( keys %{ $self->{Nicks}->{ $nick }->{CHANS} } ) {
	push ( @result, $self->{Chans}->{ $channel }->{Name} );
  }
  return @result;
}

sub channel_list {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return undef;
  my (@result);

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  foreach my $nick ( keys %{ $self->{Chans}->{ $channel }->{Nicks} } ) {
	push( @result, $self->{Nicks}->{ $nick }->{Nick} );
  }

  return @result;
}

sub is_operator {
  my ($self) = shift;
  my ($nick) = u_irc ( $_[0] ) || return 0;

  unless ( $self->_nick_exists($nick) ) {
	return 0;
  }

  if ( $self->{Nicks}->{ $nick }->{IRCop} ) {
	return 1;
  }
  return 0;
}

sub is_channel_mode_set {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($mode) = ( split //, $_[1] )[0] || return 0;

  $mode =~ s/[^A-Za-z]//g;

  unless ( $self->_channel_exists($channel) or $mode ) {
	return 0;
  }

  if ( defined ( $self->{Chans}->{ $channel }->{Mode} ) and $self->{Chans}->{ $channel }->{Mode} =~ /$mode/ ) {
	return 1;
  }
  return 0;
}

sub channel_limit {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return undef;

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  if ( $self->is_channel_mode_set($channel,'l') and defined ( $self->{Chans}->{ $channel }->{ChanLimit} ) ) {
	return $self->{Chans}->{ $channel }->{ChanLimit};
  }
  return undef;
}

sub channel_key {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return undef;

  unless ( $self->_channel_exists($channel) ) {
	return undef;
  }

  if ( $self->is_channel_mode_set($channel,'k') and defined ( $self->{Chans}->{ $channel }->{ChanKey} ) ) {
	return $self->{Chans}->{ $channel }->{ChanKey};
  }
  return undef;
}

sub is_channel_member {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;

  unless ( $self->_channel_exists($channel) and $self->_nick_exists($nick) ) {
	return 0;
  }

  if ( defined ( $self->{Chans}->{ $channel }->{Nicks}->{ $nick } ) ) {
	return 1;
  }
  return 0;
}

sub is_channel_operator {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'o') ) {
	return 0;
  }
  return 1;
}

sub has_channel_voice {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'v') ) {
	return 0;
  }
  return 1;
}

sub is_channel_halfop {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'h') ) {
	return 0;
  }
  return 1;
}

sub is_channel_owner {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'q') ) {
        return 0;
  }
  return 1;
}

sub is_channel_admin {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return 0;
  my ($nick) = u_irc ( $_[1] ) || return 0;

  unless ( $self->_nick_has_channel_mode($channel,$nick,'a') ) {
        return 0;
  }
  return 1;
}

sub ban_mask {
  my ($self) = shift;
  my ($channel) = u_irc ( $_[0] ) || return undef;
  my ($mask) = parse_ban_mask ( $_[1] ) || return undef;
  my (@result);

  unless ( $self->_channel_exists($channel) ) {
	return @result;
  }

  # Convert the mask from IRC to regex.
  $mask = u_irc ( $mask );
  $mask =~ s/\*/[\x01-\xFF]{0,}/g;
  $mask =~ s/\?/[\x01-\xFF]{1,1}/g;
  $mask =~ s/\@/\x40/g;

  foreach my $nick ( $self->channel_list($channel) ) {
	if ( $self->nick_long_form($nick) =~ /^$mask$/ ) {
		push ( @result, $nick );
	}
  }

  return @result;
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::IRC::Plugin::State - Perl extension for blah blah blah

=head1 SYNOPSIS

  use POE::Component::IRC::Plugin::State;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for POE::Component::IRC::Plugin::State, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.


=head1 HISTORY

=over 8

=item 0.01

Original version; created by h2xs 1.23 with options

  -ACX
	--use-new-tests
	--skip-ppport
	-n
	POE::Component::IRC::Plugin::State

=back



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

A. U. Thor, E<lt>apoc@attbi.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by A. U. Thor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
