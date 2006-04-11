package POE::Component::IRC::Plugin::NickReclaim;

use strict;
use warnings;
use POE::Component::IRC::Plugin qw(:ALL);

our $VERSION = '1.0';

sub new {
  my $package = shift;
  my %args = @_;
  $args{ lc $_ } = delete $args{$_} for keys %args;
  $args{poll} = 30 unless defined $args{poll} and $args{poll} =~ /^\d+$/;
  return bless \%args, $package;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $irc->plugin_register( $self, 'SERVER', qw(433) );
  return 1;
}

sub PCI_unregister {
  return 1;
}

sub S_433 {
  my ($self,$irc) = splice @_, 0, 2;
  my $offending = ${ $_[2] }->[0];
  my $current_nick = $irc->nick_name();
  return PCI_EAT_NONE if $irc->nick_name() eq $irc->{nick};
  $offending .= '_';
  $irc->yield( nick => $offending );
  $irc->delay( [ nick => $irc->{nick} ], $self->{poll} );
  return PCI_EAT_NONE;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Plugin::NickReclaim - a plugin for reclaiming nickname.

=head1 SYNOPSIS

  use strict;
  use warnings;
  use POE qw(Component::IRC Component::IRC::Plugin::NickReclaim);

  my $nickname = 'Flibble' . $$;
  my $ircname = 'Flibble the Sailor Bot';
  my $ircserver = 'irc.blahblahblah.irc';
  my $port = 6667;

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
    $irc->yield( register => 'all' );

    # Create and load our NickReclaim plugin, before we connect 
    $irc->plugin_add( 'NickReclaim' => 
        POE::Component::IRC::Plugin::NickReclaim->new( poll => 30 ) );

    $irc->yield( connect => { } );
    undef;
  }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::NickReclaim - A L<POE::Component::IRC> plugin automagically deals with your bot's nickname being in use and reclaims it when it becomes available again.

It registers and handles 'irc_433' events. On receiving a 433 event it will reset the nickname to the 'nick' specified with spawn() or connect(), appended with an underscore, and then poll to try and change it to the original nickname. 

=head1 CONSTRUCTOR

=over

=item new

Takes one optional argument:

  'poll', the number of seconds between nick change attempts, default is 30;

Returns a plugin object suitable for feeding to L<POE::Component::IRC>'s plugin_add() method.

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC>
