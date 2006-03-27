package POE::Component::IRC::Plugin::PlugMan;

use strict;
use warnings;
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
  my $package = shift;
  my %parms = @_;
  $parms{ lc $_ } = delete $parms{ $_ } for keys %parms;
  return bless \%parms, $package;
}

##########################
# Plugin related methods #
##########################

sub PCI_register {
  my ($self,$irc) = @_;

  die "This plugin must be loaded into POE::Component::IRC::State or subclasses\n" 
	unless $irc->isa('POE::Component::IRC::State');

  $self->{irc} = $irc;

  $irc->plugin_register( $self, 'SERVER', qw(public msg) );

  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = @_;
  delete $self->{irc};
  return 1;
}

sub S_public {
  my ($self,$irc) = splice @_, 0 , 2;
  my ($nick,$userhost) = ( split /!/, ${ $_[0] } )[0..1];
  return PCI_EAT_NONE unless $self->_bot_owner( $nick );
  my $channel = ${ $_[1] }->[0];
  my $what = ${ $_[2] };
  
  my $mynick = $irc->nick_name();
  my ($command) = $what =~ m/^\s*\Q$mynick\E[\:\,\;\.]?\s*(.*)$/i;
  return PCI_EAT_NONE unless $command;


  my (@cmd) = split(/ +/,$command);

  SWITCH: {
	my $cmd = uc ( shift @cmd );
	if ( $cmd eq 'PLUGIN_ADD' ) {
	  if ( $self->load( @cmd ) ) {
		$irc->yield( privmsg => $channel => 'Done.' );
	  } else {
		$irc->yield( privmsg => $channel => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_DEL' ) {
	  if ( $self->unload( @cmd ) ) {
		$irc->yield( privmsg => $channel => 'Done.' );
	  } else {
		$irc->yield( privmsg => $channel => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LIST' ) {
          my @aliases = keys %{ $irc->plugin_list() };
          if ( @aliases ) {
                $irc->yield( privmsg => $channel => 'Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( privmsg => $channel => 'No plugins loaded.' );
          }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_RELOAD' ) {
	  if ( $self->reload( @cmd ) ) {
		$irc->yield( privmsg => $channel => 'Done.' );
	  } else {
		$irc->yield( privmsg => $channel => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LOADED' ) {
          my @aliases = $self->loaded();
          if ( @aliases ) {
                $irc->yield( privmsg => $channel => 'Managed Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( privmsg => $channel => 'No managed plugins loaded.' );
          }
	  last SWITCH;
	}
  }

  return PCI_EAT_NONE;
}

sub S_msg {
  my ($self,$irc) = splice @_, 0 , 2;
  my ($nick,$userhost) = ( split /!/, ${ $_[0] } )[0..1];
  return PCI_EAT_NONE unless $self->_bot_owner( $nick );
  my $channel = ${ $_[1] }->[0];
  my $command = ${ $_[2] };
  
  my (@cmd) = split(/ +/,$command);
  SWITCH: {
	my $cmd = uc ( shift @cmd );
	if ( $cmd eq 'PLUGIN_ADD' ) {
	  if ( $self->load( @cmd ) ) {
		$irc->yield( notice => $nick => 'Done.' );
	  } else {
		$irc->yield( notice => $nick => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_DEL' ) {
	  if ( $self->unload( @cmd ) ) {
		$irc->yield( notice => $nick => 'Done.' );
	  } else {
		$irc->yield( notice => $nick => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LIST' ) {
          my @aliases = keys %{ $irc->plugin_list() };
          if ( @aliases ) {
                $irc->yield( notice => $nick => 'Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( notice => $nick => 'No plugins loaded.' );
          }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_RELOAD' ) {
	  if ( $self->reload( @cmd ) ) {
		$irc->yield( notice => $nick => 'Done.' );
	  } else {
		$irc->yield( notice => $nick => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LOADED' ) {
          my @aliases = $self->loaded();
          if ( @aliases ) {
                $irc->yield( notice => $nick => 'Managed Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( notice => $nick => 'No managed plugins loaded.' );
          }
	  last SWITCH;
	}
  }

  return PCI_EAT_NONE;
}

#########################
# Trust related methods #
#########################

sub _bot_owner {
  my $self = shift;
  my $who = $_[0] || return 0;
  my ($nick,$userhost);

  return unless $self->{botowner};

  if ( $who =~ /!/ ) {
	($nick,$userhost) = ( split /!/, $who )[0..1];
  } else {
	($nick,$userhost) = ( split /!/, $self->{irc}->nick_long_form($who) )[0..1];
  }

  return unless $nick and $userhost;

  $who = l_irc ( $nick ) . '!' . l_irc ( $userhost );

  if ( $self->{botowner} =~ /[\x2A\x3F]/ ) {
	my ($owner) = l_irc ( $self->{botowner} );
	$owner =~ s/\x2A/[\x01-\xFF]{0,}/g;
	$owner =~ s/\x3F/[\x01-\xFF]{1,1}/g;
	if ( $who =~ /$owner/ ) {
		return 1;
	}
  } elsif ( $who eq l_irc ( $self->{botowner} ) ) {
	return 1;
  }

  return 0;
}

###############################
# Plugin manipulation methods #
###############################

sub load {
  my ($self,$desc,$plugin) = splice @_, 0, 3;

  my $loaded = 0;

  $plugin .= '.pm' unless ( $plugin =~ /\.pm$/ );
  $plugin =~ s/::/\//g;

  eval { 
	require $plugin;
	$loaded = 1;
  };

  return 0 unless $loaded;

  $plugin =~ s/\.pm$//;
  $plugin =~ s/\//::/g;

  my $module = $plugin;

  my $object = $plugin->new( @_ );

  return 0 unless $object;
  
  my ($args) = [ @_ ];

  $self->{plugins}->{ $desc }->{module} = $module;

  my $return = $self->{irc}->plugin_add( $desc, $object );
  if ( $return ) {
	# Stash away arguments for use later by _reload.
	$self->{plugins}->{ $desc }->{args} = $args;
  } else {
	# Cleanup
	delete ( $self->{plugins}->{ $desc } );
  }
  return $return;
}

sub unload {
  my ($self,$desc) = splice @_, 0, 2;

  my $plugin = $self->{irc}->plugin_del( $desc );
  return 0 unless $plugin;
  my $module = $self->{plugins}->{ $desc }->{module};
  delete $INC{$module};
  delete $self->{plugins}->{ $desc };
  return 1;
}

sub reload {
  my ($self,$desc) = splice @_, 0, 2;

  my $plugin_state = $self->{plugins}->{ $desc };
  return 0 unless $plugin_state;
  print STDERR "Unloading plugin $desc\n" if $self->{debug};
  return 0 unless $self->unload( $desc );

  print STDERR "Loading plugin $desc " . $plugin_state->{module} . " [ " . join(', ',@{ $plugin_state->{args} }) . " ]\n" if $self->{debug};
  return 0 unless $self->load( $desc, $plugin_state->{module}, @{ $plugin_state->{args} } );
  return 1;
}

sub loaded {
  my $self = shift;
  return keys %{ $self->{plugins} };
}

###########################
# Miscellaneous functions #
###########################

sub u_irc {
  my $value = shift || return;
  $value =~ tr/a-z{}|/A-Z[]\\/;
  return $value;
}

sub l_irc {
  my $value = shift || return;
  $value =~ tr/A-Z[]\\/a-z{}|/;
  return $value;
}

1;
