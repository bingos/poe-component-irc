package POE::Component::IRC::Plugin::ISupport;

use strict;
use warnings;

use POE::Component::IRC::Plugin qw(:ALL);

our $VERSION = '0.53';

sub new {
  return bless { }, shift;
}

sub PCI_register {
  my ($self,$irc) = splice @_, 0, 2;

  $irc->plugin_register( $self => SERVER => qw(all) );
  $self->{irc} = $irc;
  return 1;
}

sub PCI_unregister {
        my( $self, $irc ) = @_;

	delete $self->{irc};
        # All done!
        return 1;
}

sub S_001 {
  my ($self,$irc) = splice @_, 0, 2;

  $self->{server} = { };
  $self->{done_005} = 0;
  return PCI_EAT_NONE;
}

sub S_005 {
  my ($self,$irc,@args) = @_;
  my @vals = @{ ${ $args[2] } };
  pop @vals;
  my $support = $self->{server};
  #(my $spec = ${ $args[1] }) =~ s/:are (?:available|supported).*//;

  #for (split ' ', $spec) {
  for (@vals) {
    if (/=/) {
      my ($key, $val) = split /=/, $_, 2;

      if ($key eq 'CASEMAPPING') {
        $support->{$key} = $val;
        #if ($val eq 'ascii') { }
        #elsif ($val eq 'rfc1459') {
        #  $self->{server}->cmp(sub { (my $s = pop) =~ tr/A-Z[]\\^/a-z{}|~/; $s });
        #}
        #elsif ($val eq 'strict-rfc1459') {
        #  $self->{server}->cmp(sub { (my $s = pop) =~ tr/A-Z[]\\/a-z{}|/; $s });
        #}
        #else {
        #  #$irc->_send_event(IRCE_UNKCMAP, 0, [$val]);
        #}
      }
      elsif ($key eq 'CHANLIMIT') {
        while ($key =~ /([^:]+):(\d+),?/g) {
          my ($k, $v) = ($1, $2);
          @{ $support->{$key} }{ split //, $k } = ($v) x length $k;
        }
      }
      elsif ($key eq 'CHANMODES') {
        $support->{$key} = [ split /,/, $val ];
      }
      elsif ($key eq 'CHANTYPES') {
        $support->{$key} = [ split //, $val ];
      }
      elsif ($key eq 'ELIST') {
        $support->{$key} = [ split //, $val ];
      }
      elsif ($key eq 'IDCHAN') {
        while ($val =~ /([^:]+):(\d+),?/g) {
          my ($k, $v) = ($1, $2);
          @{ $support->{$key} }{ split //, $k } = ($v) x length $k;
        }
      }
      elsif ($key eq 'MAXLIST') {
        while ($val =~ /([^:]+):(\d+),?/g) {
          my ($k, $v) = ($1, $2);
          @{ $support->{$key} }{ split //, $k } = ($v) x length $k;
        }
      }
      elsif ($key eq 'PREFIX') {
        if ( my ($k, $v) = $val =~ /\(([^)]+)\)(.*)/ ) {
          @{ $support->{$key} }{split //, $k} = split //, $v;
	}
      }
      elsif ($key eq 'SILENCE') {
        $support->{$key} = length($val) ? $val : 'off';
      }
      elsif ($key eq 'STATUSMSG') {
        $support->{$key} = [ split //, $val ];
      }
      elsif ($key eq 'TARGMAX') {
        while ($val =~ /([^:]+):(\d*),?/g) {
          $support->{$key}{$1} = $2;
        }
      }

      # AWAYLEN CHANNELLEN CHIDLEN EXCEPTS INVEX KICKLEN MAXBANS MAXCHANNELS
      # MAXTARGETS MODES NETWORK NICKLEN SILENCE STD TOPICLEN WATCH
      else { $support->{$key} = $val }
    }
    else {
      if ($_ eq 'EXCEPTS') { $support->{$_} = 'e' }
      elsif ($_ eq 'INVEX') { $support->{$_} = 'I' }
      elsif ($_ eq 'MODES') { $support->{$_} = '' }
      elsif ($_ eq 'SILENCE') { $support->{$_} = 'off' }

      # ACCEPT CALLERID CAPAB CNOTICE CPRIVMSG FNC KNOCK MAXNICKLEN NOQUIT
      # PENALTY RFC1812 SAFELIST USERIP VCHANS WALLCHOPS WALLVOICES WHOX
      else { $support->{$_} = "on" }
    }
  }
  return PCI_EAT_NONE;
}

sub _default {
  my ($self, $irc, $e) = @_;

  return PCI_EAT_NONE if $self->{done_005};
  if ($e =~ /^S_0*(\d+)/ and $1 > 5) {
    $irc->_send_event(irc_isupport => $self);
    $self->{done_005} = 1;
  }

  return PCI_EAT_NONE;
}

sub isupport {
  my $self = shift;
  my $value = uc ( $_[0] ) || return undef;
  
  return $self->{server}->{$value} if defined $self->{server}->{$value};
  undef;
}

sub isupport_dump_keys {
  my $self = shift;

  if ( scalar ( keys %{ $self->{server} } ) > 0 ) {
	return keys %{ $self->{server} };
  }
  return undef;
}

1;
__END__


=head1 NAME

POE::Component::IRC::Plugin::ISupport - A POE::Component::IRC plugin that handles server capabilities.

=head1 DESCRIPTION

This handles the C<irc_005> messages that come from the server.  They
define the capabilities support by the server.

=head1 CONSTRUCTOR

=over 

=item new 

Takes no arguments.

=back

=head1 METHODS

=over

=item isupport

Takes one argument. the server capability to query. Returns undef on failure or a value representing the applicable capability. A full list of capabilities is available at L<http://www.irc.org/tech_docs/005.html>.

=item isupport_dump_keys

Takes no arguments, returns a list of the available server capabilities, which can be used with isupport().

=back

=head2 Handlers

This module handles the following PoCo-IRC signals:

=over 4

=item C<irc_005> (RPL_ISUPPORT or RPL_PROTOCTL)

Denotes the capabilities of the server.

=item all

Once the next signal is received that is I<greater> than C<irc_005>,
it emits an C<irc_isupport> signal.
ck

=back

=head2 Signals Emitted

=over 4

=item C<irc_isupport>

Emitted by: the first signal received after C<irc_005>

ARG0 will be the plugin object itself for ease of use.

This is emitted when the support report has finished.

=back

=head1 AUTHOR

Jeff C<japhy> Pinyan, F<japhy@perlmonk.org>

=head1 SEE ALSO

L<POE::Component::IRC>

L<POE::Component::IRC::Plugin>

=cut


