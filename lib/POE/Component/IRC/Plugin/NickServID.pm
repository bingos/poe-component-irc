package POE::Component::IRC::Plugin::NickServID;

use strict;
use warnings;
use Carp;
use POE::Component::IRC::Plugin qw( :ALL );
use POE::Component::IRC::Common qw( u_irc );

our $VERSION = '1.0';

sub new {
    my ($package, %self) = @_;
    croak "$package requires a Password" unless defined $self{Password};
    return bless \%self, $package;
}

sub PCI_register {
    my ($self, $irc) = @_;
    $self->{Nickname} = $irc->nick_name() unless $self->{Nickname};
    $self->{Nickname} = u_irc $self->{Nickname};
    $irc->plugin_register($self, 'SERVER', qw(001 nick));
    return 1;
}

sub PCI_unregister {
    return 1;
}

sub S_001 {
    my ($self, $irc) = splice @_, 0, 2;
    if (u_irc $irc->nick_name() eq $self->{Nickname}) {
        $irc->yield(privmsg => nickserv => 'IDENTIFY ' . $self->{Password});
    }
    return PCI_EAT_NONE;
}

sub S_nick {
    my ($self, $irc) = splice @_, 0, 2;
    my $new_nick = u_irc ${ $_[1] };
    if ($new_nick eq u_irc $irc->nick_name() && $new_nick eq $self->{Nickname}) {
        $irc->yield(privmsg => nickserv => 'IDENTIFY ' . $self->{Password});
    }
    return PCI_EAT_NONE;
}

1;

=head1 NAME

POE::Component::IRC::Plugin::NickServID - A PoCo-IRC plugin
which identifies with FreeNode's NickServ when needed.

=head1 SYNOPSIS

 use POE::Component::IRC::Plugin::NickServID;

 $irc->plugin_add( 'NickServID', POE::Component::IRC::Plugin::NickServID->new( Password => 'opensesame' ));

=head1 DESCRIPTION

POE::Component::IRC::Plugin::NickServID is a L<POE::Component::IRC|POE::Component::IRC> plugin.
It identifies with NickServ on connect and when you change your nick, if your nickname matches
the supplied password.

=head1 METHODS

=over

=item new

Arguments:

 'Nickname', the nickname that is associated with the password. Defaults to the nick returned
 by $irc->nick_name() at the time of plugin registration.
 'Password', the NickServ password.

Returns a plugin object suitable for feeding to L<POE::Component::IRC|POE::Component::IRC>'s
plugin_add() method.

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

