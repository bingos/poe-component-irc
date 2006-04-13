package POE::Component::IRC::Plugin::CTCP;

use strict;
use warnings;
use POE::Component::IRC::Plugin qw( :ALL );
use POSIX;
use vars qw($VERSION);

$VERSION = '1.0';

sub new {
  my $package = shift;
  my %args = @_;
  $args{ lc $_ } = delete $args{ $_ } for keys %args;
  $args{eat} = 1 unless defined ( $args{eat} ) and $args{eat} eq '0';
  return bless \%args, $package;
}

sub PCI_register {
  my ($self,$irc) = splice @_, 0, 2;

  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(ctcp_version ctcp_userinfo ctcp_time) );

  return 1;
}

sub PCI_unregister {
  delete $_[0]->{irc};
  return 1;
}

sub S_ctcp_version {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  
  $irc->yield( ctcpreply => $nick => 'VERSION ' . ( $self->{version} ? $self->{version} : "POE::Component::IRC-" . $POE::Component::IRC::VERSION ) );
  return PCI_EAT_CLIENT if $self->eat();
  return PCI_EAT_NONE;
}

sub S_ctcp_time {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];
  
  $irc->yield( ctcpreply => $nick => strftime( "TIME %a %h %e %T %Y %Z", localtime ) );
  return PCI_EAT_CLIENT if $self->eat();
  return PCI_EAT_NONE;
}

sub S_ctcp_userinfo {
  my ($self,$irc) = splice @_, 0, 2;
  my $nick = ( split /!/, ${ $_[0] } )[0];

  $irc->yield( ctcpreply => $nick => 'USERINFO ' . ( $self->{userinfo} ? $self->{userinfo} : 'm33p' ) );
  return PCI_EAT_CLIENT if $self->eat();
  return PCI_EAT_NONE;
}

sub eat {
  my $self = shift;
  my $value = shift;

  return $self->{eat} unless defined ( $value );
  $self->{eat} = $value;
}

1;

__END__

=head1 NAME

POE::Component::IRC::Plugin::CTCP - A POE::Component::IRC plugin that auto-responds to CTCP requests.

=head1 SYNOPSIS

  use strict;
  use warnings;
  use POE qw(Component::IRC Component::IRC::Plugin::CTCP);

  my ($nickname) = 'Flibble' . $$;
  my ($ircname) = 'Flibble the Sailor Bot';
  my ($ircserver) = 'irc.blahblahblah.irc';
  my ($port) = 6667;

  my ($irc) = POE::Component::IRC->spawn( 
        nick => $nickname,
        server => $ircserver,
        port => $port,
        ircname => $ircname,
  ) or die "Oh noooo! $!";

  POE::Session->create(
        package_states => [
                'main' => [ qw(_start) ],
        ],
  );

  $poe_kernel->run();
  exit 0;

  sub _start {
    # Create and load our CTCP plugin
    $irc->plugin_add( 'CTCP' => 
	POE::Component::IRC::Plugin::CTCP->new( version => $ircname, userinfo => $ircname ) );

    $irc->yield( register => 'all' );
    $irc->yield( connect => { } );
    undef;
  }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::CTCP is a L<POE::Component::IRC|POE::Component::IRC> plugin. It watches for 'irc_ctcp_version', 'irc_ctcp_userinfo' and 'irc_ctcp_time' events and autoresponds on your behalf.

=head1 CONSTRUCTOR

=over

=item new

Takes a number of optional arguments:

   'version', a string to send in response to 'irc_ctcp_version'. Default is PoCo-IRC and version;
   'userinfo', a string to send in response to 'irc_ctcp_userinfo'. Default is 'm33p';
   'eat', by default the plugin uses PCI_EAT_CLIENT, set this to 0 to disable this behaviour;

Returns a plugin object suitable for feeding to L<POE::Component::IRC|POE::Component::IRC>'s plugin_add() method.

=back

=head1 METHODS

=over

=item eat

With no arguments, returns true or false on whether the plugin is "eating" ctcp events that it has dealt with. An argument will set "eating" to on or off appropriately, depending on whether the value is true or false.

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

CTCP Specification L<http://www.irchelp.org/irchelp/rfc/ctcpspec.html>.
