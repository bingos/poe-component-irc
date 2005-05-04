# Declare our package
package POE::Component::IRC::Plugin::Whois;

# Standard stuff to catch errors
use POE;
use strict qw(subs vars refs);                          # Make sure we can't mess up
use warnings FATAL => 'all';                            # Enable warnings to catch errors

# Initialize our version
our $VERSION = '0.01';

# Import the stuff from Plugin
use POE::Component::IRC::Plugin qw( PCI_EAT_NONE );

# The constructor
sub new {
        return bless ( { }, shift );
}

# Register ourself!
sub PCI_register {
        my( $self, $irc ) = @_;

        # Register our events!
        $irc->plugin_register( $self, 'SERVER', qw(311 313 312 317 319 320 330 318 314 369) );

        # All done!
        return 1;
}

# Unregister ourself!
sub PCI_unregister {
        my( $self, $irc ) = @_;

        # All done!
        return 1;
}

# RPL_WHOISUSER
sub S_311 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($rnick,$user,$host) = ( split / /, ${ $_[1] } )[0..2];
  my ($real) = substr(${ $_[1] },index(${ $_[1] },' :')+2);
  my ($nick) = u_irc ( $rnick );

  $self->{WHOIS}->{ $nick }->{nick} = $rnick;
  $self->{WHOIS}->{ $nick }->{user} = $user;
  $self->{WHOIS}->{ $nick }->{host} = $host;
  $self->{WHOIS}->{ $nick }->{real} = $real;

  return PCI_EAT_NONE;
}

# RPL_WHOISOPERATOR
sub S_313 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($oper) = substr(${ $_[1] },index(${ $_[1] },' :')+2);
  my ($nick) = u_irc ( ( split / :/, ${ $_[1] } )[0] );

  $self->{WHOIS}->{ $nick }->{oper} = $oper;

  return PCI_EAT_NONE;
}

# RPL_WHOISSERVER
sub S_312 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick,$server) = ( split / /, ${ $_[1] } )[0..1];
  $nick = u_irc ( $nick );

  # This can be returned in reply to either a WHOIS or a WHOWAS *sigh*
  if ( defined ( $self->{WHOWAS}->{ $nick } ) ) {
        $self->{WHOWAS}->{ $nick }->{server} = $server;
  } else {
        $self->{WHOIS}->{ $nick }->{server} = $server;
  }

  return PCI_EAT_NONE;
}

# RPL_WHOISIDLE
sub S_317 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick,@args) = split (/ /, ( split / :/, ${ $_[1] } )[0] );
  $nick = u_irc ( $nick );

  $self->{WHOIS}->{ $nick }->{idle} = $args[0];
  $self->{WHOIS}->{ $nick }->{signon} = $args[1];

  return PCI_EAT_NONE;
}

# RPL_WHOISCHANNELS
sub S_319 {
  my ($self,$irc) = splice @_, 0, 2;
  my (@args) = split(/ /, ${ $_[1] } );
  my ($nick) = u_irc ( shift @args );
  $args[0] =~ s/^://;

  if ( not defined ( $self->{WHOIS}->{ $nick }->{channels} ) ) {
        $self->{WHOIS}->{ $nick }->{channels} = [ @args ];
  } else {
        push( @{ $self->{WHOIS}->{ $nick }->{channels} }, @args );
  }

  return PCI_EAT_NONE;
}

# RPL_WHOISIDENTIFIED ( Freenode hack )
sub S_320 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick, $ident) = ( split / :/, ${ $_[1] } )[0..1];

  $self->{WHOIS}->{ u_irc ( $nick ) }->{identified} = $ident;

  return PCI_EAT_NONE;
}

# RPL_WHOISAUTHEDAS?
sub S_330 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick,$account) = ( split / /, ${ $_[1] } )[0..1];

  $self->{WHOIS}->{ u_irc ( $nick ) }->{account} = $account;

  return PCI_EAT_NONE;
}


# RPL_ENDOFWHOIS
sub S_318 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick) = u_irc ( ( split / :/, ${ $_[1] } )[0] );

  my ($whois) = delete ( $self->{WHOIS}->{ $nick } );

  if ( defined ( $whois ) ) {
        $irc->_send_event( 'irc_whois', $whois );
  }

  return PCI_EAT_NONE;
}

# RPL_WHOWASUSER
sub S_314 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($rnick,$user,$host) = ( split / /, ${ $_[1] } )[0..2];
  my ($real) = substr(${ $_[1] },index(${ $_[1] },' :')+2);
  my ($nick) = u_irc ( $rnick );

  $self->{WHOWAS}->{ $nick }->{nick} = $rnick;
  $self->{WHOWAS}->{ $nick }->{user} = $user;
  $self->{WHOWAS}->{ $nick }->{host} = $host;
  $self->{WHOWAS}->{ $nick }->{real} = $real;

  return PCI_EAT_NONE;
}

# RPL_ENDOFWHOWAS
sub S_369 {
  my ($self,$irc) = splice @_, 0, 2;
  my ($nick) = u_irc ( ( split / :/, ${ $_[1] } )[0] );

  my ($whowas) = delete ( $self->{WHOWAS}->{ $nick } );

  if ( defined ( $whowas ) ) {
        $irc->_send_event( 'irc_whowas', $whowas );
  }

  return PCI_EAT_NONE;
}

sub u_irc {
  my ($value) = shift || return undef;

  $value =~ tr/a-z{}|^/A-Z[]\\~/;
  return $value;
}

1;

__END__

=head1 NAME

POE::Component::IRC::Plugin::Whois - A PoCo-IRC plugin that implements 'irc_whois' and 'irc_whowas' events.

=head1 DESCRIPTION

POE::Component::IRC::Plugin::Whois is the reimplementation of the 'irc_whois' and 'irc_whowas' code from
L<POE::Component::IRC|POE::Component::IRC> as a plugin. It is used internally by L<POE::Component::IRC|POE::Component::IRC>
so there is no need to use this plugin yourself.

=head1 AUTHOR

Chris "BinGOs" Williams

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>
L<POE::Component::IRC::Plugin|POE::Component::IRC::Plugin>

=cut

