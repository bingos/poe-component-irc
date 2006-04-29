package POE::Component::IRC::Plugin::BotAddressed;

use strict;
use warnings;
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
  my $package = shift;
  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;
  return bless \%args, $package;
}

sub PCI_register {
  my ($self,$irc) = splice @_, 0, 2;

  $irc->plugin_register( $self, 'SERVER', qw(public) );
  return 1;
}

sub PCI_unregister {
  return 1;
}

sub S_public {
  my ($self,$irc) = splice @_, 0, 2;
  my $who = ${ $_[0] };
  my $channel = ${ $_[1] }->[0];
  my $what = ${ $_[2] };
  my $mynick = $irc->nick_name();
  my ($cmd) = $what =~ m/^\s*\Q$mynick\E[\:\,\;\.]?\s*(.*)$/i;
  return PCI_EAT_NONE unless $cmd;

  $irc->_send_event( ( $self->{event} || 'irc_bot_addressed' ) => $who => [ $channel ] => $cmd );
  return $self->{eat} ? PCI_EAT_ALL : PCI_EAT_NONE;
}

1;

__END__

=head1 NAME

POE::Component::IRC::Plugin::BotAddressed - A POE::Component::IRC plugin that generates 'irc_bot_addressed' events whenever someone addresses your bot by name in a channel.

=head1 SYNOPSIS

  use POE::Component::IRC::Plugin::BotAddressed;

  $irc->plugin_add( 'BotAddressed', POE::Component::IRC::Plugin::BotAddressed->new() );

  sub irc_bot_addressed {
    my ($kernel,$heap) = @_[KERNEL,HEAP];
    my ($nick) = ( split /!/, $_[ARG0] )[0];
    my ($channel) = $_[ARG1]->[0];
    my ($what) = $_[ARG2];

    print "$nick addressed me in channel $channel with the message '$what'\n";
  }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::BotAddressed is a L<POE::Component::IRC|POE::Component::IRC> plugin. It watches for
public channel traffic ( ie. 'irc_public' ) and will generate an 'irc_bot_addressed' event if someone on a channel
issues a message which 'addresses' the bot.

It uses L<POE::Component::IRC|POE::Component::IRC>'s nick_name() method to work out it's current nickname.

=head1 METHODS

=over

=item new

Two optional arguments:

  'eat', set to true to make the plugin eat the 'irc_public' event and only generate 
         the 'irc_bot_addressed' event, default is 0;
  'event', change the default event name from 'irc_bot_addressed';

Returns a plugin object suitable for feeding to L<POE::Component::IRC|POE::Component::IRC>'s plugin_add() method.

=back

=head1 OUTPUT

=over

=item irc_bot_addressed

Has the same parameters passed as 'irc_public'. ARG2 contains the message with the addressed nickname removed, ie. 
Assuming that your bot is called LameBOT, and someone says 'LameBOT: dance for me', you will actually get 'dance for me'.

=back 

=head1 AUTHOR

Chris 'BinGOs' Williams E<lt>chris@bingosnet.co.uk<gt>
