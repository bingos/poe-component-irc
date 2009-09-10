package POE::Component::IRC::Plugin::BotCommand;

use strict;
use warnings;
use Carp;
use POE::Component::IRC::Common qw( parse_user strip_color strip_formatting );
use POE::Component::IRC::Plugin qw( :ALL );

our $VERSION = '6.12';

sub new {
    my ($package) = shift;
    croak "$package requires an even number of arguments" if @_ & 1;
    my %args = @_;
    
    for my $cmd (keys %{ $args{Commands} }) {
        $args{Commands}->{lc $cmd} = delete $args{Commands}->{$cmd};
    }
    return bless \%args, $package;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;
    
    $self->{Addressed}     = 1 if !defined $self->{Addressed};
    $self->{Prefix}        = '!' if !defined $self->{Prefix};
    $self->{In_channels}   = 1 if !defined $self->{In_channels};
    $self->{In_private}    = 1 if !defined $self->{In_private};
    $self->{irc} = $irc;
    
    $irc->plugin_register( $self, 'SERVER', qw(msg public) );
    return 1;
}

sub PCI_unregister {
    return 1;
}

sub S_msg {
    my ($self, $irc) = splice @_, 0, 2;
    my $who   = ${ $_[0] };
    my $where = parse_user($who);
    my $what  = ${ $_[2] };
    
    return PCI_EAT_NONE if !$self->{In_private};
    $what = $self->_normalize($what);
    
    my ($cmd, $args);
    if (!(($cmd, $args) = $what =~ /^(\w+)(?:\s+(.+))?$/)) {
        return PCI_EAT_NONE;
    }
    
    my $handled = $self->_handle_cmd($who, $where, $cmd, $args);
    
    if ($self->{Eat} && $handled) {
        return PCI_EAT_PLUGIN;
    }
    return PCI_EAT_NONE;
}

sub S_public {
    my ($self, $irc) = splice @_, 0, 2;
    my $who   = ${ $_[0] };
    my $where = ${ $_[1] }->[0];
    my $what  = ${ $_[2] };
    my $me    = $irc->nick_name();

    return PCI_EAT_NONE if !$self->{In_channels};
    $what = $self->_normalize($what);

    if ($self->{Addressed}) {
        return PCI_EAT_NONE if !(($what) = $what =~ m/^\s*\Q$me\E[:,;.!?~]?\s*(.*)$/);
    }
    else {
        return PCI_EAT_NONE if $what !~ s/^$self->{Prefix}//;
    }

    my ($cmd, $args);
    if (!(($cmd, $args) = $what =~ /^(\w+)(?:\s+(.+))?$/)) {
        return PCI_EAT_NONE;
    }
 
    my $handled = $self->_handle_cmd($who, $where, $cmd, $args);
    
    if ($self->{Eat} && $handled) {
        return PCI_EAT_PLUGIN;
    }
    return PCI_EAT_NONE;
}

sub _normalize {
    my ($self, $line) = @_;
    $line = strip_color($line);
    $line = strip_formatting($line);
    return $line;
}

sub _handle_cmd {
    my ($self, $who, $where, $cmd, $args) = @_;
    my $irc = $self->{irc};
    $cmd = lc $cmd;

    if (defined $self->{Commands}->{$cmd}) {
        $irc->send_event("irc_botcmd_$cmd" => $who, $where, $args);
    }
    elsif ($cmd =~ /^help$/i) {
        my @help = $self->_get_help($args);
        $irc->yield(notice => $where => $_) for @help;
    }
    else {
        return if $self->{Ignore_unknown};
        my @help = $self->_get_help($cmd);
        $irc->yield(notice => $where => $_) for @help;
    }

    return 1;
}

sub _get_help {
    my ($self, $args) = @_;
    my $irc = $self->{irc};
    
    my @help;
    if (defined $args) {
        my $cmd = (split /\s+/, $args, 2)[0];
        if (exists $self->{Commands}->{$cmd}) {
            @help = split /\015?\012/, $self->{Commands}->{$cmd};
        }
        else {
            push @help, "Unknown command: $cmd";
            push @help, 'To get a list of commands, do: /msg '. $irc->nick_name() . ' help';
        }
    }
    else {
        if (keys %{ $self->{Commands} }) {
            push @help, 'Commands: ' . join ', ', keys %{ $self->{Commands} };
            push @help, 'You can do: /msg ' . $irc->nick_name() . ' help <command>';
        }
        else {
            push @help, 'No commands are defined';
        }
    }

    return @help;
}

sub add {
    my ($self, $cmd, $usage) = @_;
    $cmd = lc $cmd;
    return if exists $self->{Commands}->{$cmd};
    $self->{Commands}->{$cmd} = $usage;
    return 1;
}

sub remove {
    my ($self, $cmd) = @_;
    $cmd = lc $cmd;
    return if !exists $self->{Commands}->{$cmd};
    delete $self->{Commands}->{$cmd};
    return 1;
}

sub list {
    my ($self) = @_;
    return %{ $self->{Commands} };
}

1;
__END__

=head1 NAME

POE::Component::IRC::Plugin::BotCommand - A PoCo-IRC plugin which handles
commands issued to your bot

=head1 SYNOPSIS

 use POE;
 use POE::Component::Client::DNS;
 use POE::Component::IRC;
 use POE::Component::IRC::Plugin::BotCommand;

 my @channels = ('#channel1', '#channel2');
 my $dns = POE::Component::Client::DNS->spawn();
 my $irc = POE::Component::IRC->spawn(
     nick   => 'YourBot',
     server => 'some.irc.server',
 );

 POE::Session->create(
     package_states => [
         main => [ qw(_start irc_001 irc_botcmd_slap irc_botcmd_lookup dns_response) ],
     ],
 );

 $poe_kernel->run();

 sub _start {
     $irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
         Commands => {
             slap   => 'Takes one argument: a nickname to slap.',
             lookup => 'Takes two arguments: a record type (optional), and a host.',
         }
     ));
     $irc->yield(register => qw(001 botcmd_slap botcmd_lookup));
     $irc->yield(connect => { });
 }

 # join some channels
 sub irc_001 {
     $irc->yield(join => $_) for @channels;
     return;
 }

 # the good old slap
 sub irc_botcmd_slap {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $irc->yield(ctcp => $where, "ACTION slaps $arg");
     return;
 }

 # non-blocking dns lookup
 sub irc_botcmd_lookup {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my ($type, $host) = $arg =~ /^(?:(\w+) )?(\S+)/;
     
     my $res = $dns->resolve(
         event => 'dns_response',
         host => $host,
         type => $type,
         context => {
             where => $where,
             nick  => $nick,
         },
     );
     $poe_kernel->yield(dns_response => $res) if $res;
     return;
 }

 sub dns_response {
     my $res = $_[ARG0];
     my @answers = map { $_->rdatastr } $res->{response}->answer() if $res->{response};
     
     $irc->yield(
         'notice',
         $res->{context}->{where},
         $res->{context}->{nick} . (@answers
             ? ": @answers"
             : ': no answers for "' . $res->{host} . '"')
     );

     return;
 }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::BotCommand is a
L<POE::Component::IRC|POE::Component::IRC> plugin. It provides you with a
standard interface to define bot commands and lets you know when they are
issued. Commands are accepted as channel or private messages.

The plugin will respond to the 'help' command by default, listing available
commands and information on how to use them. However, if you add a help
command yourself, that one will be used instead.

=head1 METHODS

=head2 C<new>

Four optional arguments:

B<'Commands'>, a hash reference, with your commands as keys, and usage
information as values. If the usage string contains newlines, the component
will send one message for each line.

B<'In_channels'>, a boolean value indicating whether to accept commands in
channels. Default is true.

B<'In_private'>, a boolean value indicating whether to accept commands in
private. Default is true.

B<'Addressed'>, requires users to address the bot by name in order
to issue commands. Default is true.

B<'Prefix'>, if B<'Addressed'> is false, all channel commands must be prefixed
with this string. Default is '!'. You can set it to '' to allow bare channel
commands.

B<'Ignore_unknown'>, if true, the plugin will ignore undefined commands,
rather than printing a help message upon receiving them. Default is false.

B<'Eat'>, set to true to make the plugin hide
L<C<irc_public>|POE::Component::IRC/"irc_public"> events from other plugins if
they contain a valid command. Default is false.

Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s C<plugin_add> method.

=head2 C<add>

Adds a new command. Takes two arguments, the name of the command, and a string
containing its usage information. Returns false if the command has already been
defined, true otherwise.

=head2 C<remove>

Removes a command. Takes one argument, the name of the command. Returns false
if the command wasn't defined to begin with, true otherwise.

=head2 C<list>

Takes no arguments. Returns a list of key/value pairs, the keys being the
command names and the values being the usage strings.

=head1 OUTPUT

=head2 C<irc_botcmd_*>

You will receive an event like this for every valid command issued. E.g. if
'slap' were a valid command, you would receive an C<irc_botcmd_slap> event
every time someone issued that command. C<ARG0> is the nick!hostmask of the
user who issued the command. C<ARG1> is the name of the channel in which the
command was issued, or the sender's nickname if this was a private message.
If the command was followed by any arguments, C<ARG2> will be a string
containing them, otherwise it will be undefined.

=head1 TODO

Add permissions/authorization. E.g. allow the user to specify if commands are
only available ops, or only to users matching some IRC masks, etc.

It would have to support permissions/auth on a per-command level, so that
a bot can get by with a single BotCommand plugin, with respect to easily
listing the available commands in a help message. Maybe augmenting the
C<add()> method to accept an optional hash reference argument detailing
authorization requirements is appropriate here. I suppose plugins that call
C<add()> to add new commands should accept a hash reference like that as an
B<'auth'> argument to their constructor.

I considered having the auth settings apply to all commands, and using
multiple BotCommand plugins to group commands by who is allowed to issue them,
but this approach is more complex if we want the bot to complain about
undefined commands, or when someone wants a list of all commands. Plugins
which define new commands would accept a B<'botcmd'> parameter to choose which
BotCommand plugin they should call C<add()>/C<remove()> on.

Some prior art to consider:

=over 4

=item L<POE::Component::IRC::Plugin::BaseWrap|POE::Component::IRC::PluginBaseWrap>

=item L<Bot::BasicBot::Pluggable::Module::Auth|Bot::BasicBot::Pluggable::Module::Auth> 

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

=cut
