package POE::Component::IRC::Plugin::BotCommand;

use strict;
use warnings FATAL => 'all';
use Carp;
use IRC::Utils qw( parse_user strip_color strip_formatting );
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
    my ($package) = shift;
    croak "$package requires an even number of arguments" if @_ & 1;
    my %args = @_;

    $args{Method} = 'notice' if !defined $args{Method};

    for my $cmd (keys %{ $args{Commands} }) {
        if (ref $args{Commands}->{$cmd} eq 'HASH') {
            croak "$cmd: no info provided"
                if !exists $args{Commands}->{$cmd}->{info} ;
            croak "$cmd: no arguments provided"
                if !@{ $args{Commands}->{$cmd}->{args} };

        }
        $args{Commands}->{lc $cmd} = delete $args{Commands}->{$cmd};
    }
    return bless \%args, $package;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;

    $self->{Addressed}   = 1   if !defined $self->{Addressed};
    $self->{Prefix}      = '!' if !defined $self->{Prefix};
    $self->{In_channels} = 1   if !defined $self->{In_channels};
    $self->{In_private}  = 1   if !defined $self->{In_private};
    $self->{rx_cmd_args} = qr/^(\S+)(?:\s+(.+))?$/;
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

    if (!$self->{Bare_private}) {
        return PCI_EAT_NONE if $what !~ s/^\Q$self->{Prefix}\E//;
    }

    my ($cmd, $args);
    if (!(($cmd, $args) = $what =~ $self->{rx_cmd_args})) {
        return PCI_EAT_NONE;
    }

    $self->_handle_cmd($who, $where, $cmd, $args);
    return $self->{Eat} ? PCI_EAT_PLUGIN : PCI_EAT_NONE;
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
        return PCI_EAT_NONE if $what !~ s/^\Q$self->{Prefix}\E//;
    }

    my ($cmd, $args);
    if (!(($cmd, $args) = $what =~ $self->{rx_cmd_args})) {
        return PCI_EAT_NONE;
    }

    $self->_handle_cmd($who, $where, $cmd, $args);
    return $self->{Eat} ? PCI_EAT_PLUGIN : PCI_EAT_NONE;
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
    my $chantypes = join('', @{ $irc->isupport('CHANTYPES') || ['#', '&']});
    my $public = $where =~ /^[$chantypes]/ ? 1 : 0;
    $cmd = lc $cmd;

    if (defined $self->{Commands}->{$cmd}) {
        if (ref $self->{Commands}->{$cmd} eq 'HASH') {
            my @args_array = defined $args ? split /\s+/, $args : ();
            if (@args_array < @{ $self->{Commands}->{$cmd}->{args} } ||
               (!defined $self->{Commands}->{$cmd}->{variable} &&
                @args_array > @{ $self->{Commands}->{$cmd}->{args} })
            ) {
                  $irc->yield($self->{Method}, $where,
                      "Not enough or too many arguments. See help for $cmd");
                  return;
            }

            $args = {};
            for (@{ $self->{Commands}->{$cmd}->{args} }) {
                my $in_arg = shift @args_array;
                if (ref $self->{Commands}->{$cmd}->{$_} eq 'ARRAY') {
                    my @values = @{ $self->{Commands}->{$cmd}->{$_} };
                    shift @values;

                    use List::MoreUtils qw(none);
                    # Check if argument has one of possible values
                    if (none { $_ eq $in_arg} @values) {
                      $irc->yield($self->{Method}, $where,
                          "$_ can be one of ".join '|', @values);
                      return;
                    }

                }
                $args->{$_} = $in_arg;
            }

            # Process remaining arguments if variable is set
            my $arg_cnt = 0;
            if (defined $self->{Commands}->{$cmd}->{variable}) {
                for (@args_array) {
                    $args->{"opt".$arg_cnt++} = $_;
                }
            }
        }
    }

    if (ref $self->{Auth_sub} eq 'CODE') {
        my ($authed, $errors) = $self->{Auth_sub}->($self->{irc}, $who, $where, $cmd, $args);

        if (!$authed) {
            my @errors = ref $errors eq 'ARRAY'
                ? @$errors
                : 'You are not authorized to use this command.';
            for my $error (@errors) {
                $irc->yield($self->{Method}, $where, $error);
            }
            return;
        }
    }

    if (defined $self->{Commands}->{$cmd}) {
        $irc->send_event_next("irc_botcmd_$cmd" => $who, $where, $args);
    }
    elsif ($cmd =~ /^help$/i) {
        my @help = $self->_get_help($args, $public);
        $irc->yield($self->{Method} => $where => $_) for @help;
    }
    elsif (!$self->{Ignore_unknown}) {
        my @help = $self->_get_help($cmd, $public);
        $irc->yield($self->{Method} => $where => $_) for @help;
    }

    return;
}

sub _get_help {
    my ($self, $args, $public) = @_;
    my $irc = $self->{irc};
    my $p = $self->{Addressed} && $public
        ? $irc->nick_name().': '
        : $self->{Prefix};

    my @help;
    if (defined $args) {
        my $cmd = (split /\s+/, $args, 2)[0];
        if (exists $self->{Commands}->{$cmd}) {
            if (ref $self->{Commands}->{$cmd} eq 'HASH') {
                push @help, "Syntax: $p$cmd ".
                    (join ' ', @{ $self->{Commands}->{$cmd}->{args} }).
                    (defined $self->{Commands}->{$cmd}->{variable} ?
                        " ..."  : "");
                push @help, split /\015?\012/,
                    "Description: ".$self->{Commands}->{$cmd}->{info};
                push @help, "Arguments:";

                for my $arg (@{ $self->{Commands}->{$cmd}->{args} }) {
                    next if not defined $self->{Commands}->{$cmd}->{$arg};
                    if (ref $self->{Commands}->{$cmd}->{$arg} eq 'ARRAY') {
                        my @arg_usage = @{$self->{Commands}->{$cmd}->{$arg}};
                        push @help, "    $arg: ".$arg_usage[0].
                        " (".(join '|', @arg_usage[1..$#arg_usage]).")"
                    }
                    else {
                        push @help, "    $arg: ".
                            $self->{Commands}->{$cmd}->{$arg};
                    }
                }
            }
            else {
                @help = split /\015?\012/, $self->{Commands}->{$cmd};
            }
        }
        else {
            push @help, "Unknown command: $cmd";
            push @help, "To get a list of commands, use: ${p}help";
        }
    }
    else {
        if (keys %{ $self->{Commands} }) {
            push @help, 'Commands: ' . join ', ', sort keys %{ $self->{Commands} };
            push @help, "For more details, use: ${p}help <command>";
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

    if (ref $usage eq 'HASH') {
        return if !exists $usage->{info} || !@{ $usage->{args} };
    }

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

=encoding utf8

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

B<'Commands'>, a hash reference, with your commands as keys, and usage
information as values. If the usage string contains newlines, the plugin
will send one message for each line.

If a command's value is a HASH ref like this:

     $irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
         Commands => {
             slap   => {
                info => 'Slap someone',
                args => [qw(nickname)],
                nickname => 'nickname to slap'
             }
         }
     ));

The args array reference is than used to validate number of arguments required
and to name arguments passed to event handler. Help is than generated from
C<info> and other hash keys which represent arguments (they are optional).

=head3 Accepting commands

B<'In_channels'>, a boolean value indicating whether to accept commands in
channels. Default is true.

B<'In_private'>, a boolean value indicating whether to accept commands in
private. Default is true.

B<'Addressed'>, requires users to address the bot by name in order
to issue commands. Default is true.

B<'Prefix'>, a string which all commands must be prefixed with (except in
channels when B<'Addressed'> is true). Default is '!'. You can set it to ''
to allow bare commands.

B<'Bare_private'>, a boolean value indicating whether bare commands (without
the prefix) are allowed in private messages. Default is false.

=head3 Authorization

B<'Auth_sub'>, a subroutine reference which, if provided, will be called
for every command. The subroutine will be called in list context. If the
first value returned is true, the command will be processed as normal. If
the value is false, then no events will be generated, and an error message
will possibly be sent back to the user.

You can override the default error message by returning a second value, an
array reference of (zero or more) strings. Each string will be sent as a
message to the user.

Your subroutine will be called with the following arguments:

=over 4

=item 1. The IRC component object

=item 2. The nick!user@host of the user

=item 3. The place where the command was issued (the nickname of the user if
it was in private)

=item 4. The name of the command

=item 5. The command argument string

=back

B<'Ignore_unauthorized'>, if true, the plugin will ignore unauthorized
commands, rather than printing an error message upon receiving them. This is
only relevant if B<'Auth_sub'> is also supplied. Default is false.

=head3 Miscellaneous

B<'Ignore_unknown'>, if true, the plugin will ignore undefined commands,
rather than printing a help message upon receiving them. Default is false.

B<'Method'>, how you want help messages to be delivered. Valid options are
'notice' (the default) and 'privmsg'.

B<'Eat'>, set to true to make the plugin hide
L<C<irc_public>|POE::Component::IRC/irc_public> events from other plugins
when they look like commands. Probably only useful when a B<'Prefix'> is
defined. Default is false.

Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s C<plugin_add> method.

=head2 C<add>

Adds a new command. Takes two arguments, the name of the command, and a string
or hash reference containing its usage information (see C<new>). Returns false
if the command has already been defined or no info or arguments are provided,
true otherwise.

=head2 C<remove>

Removes a command. Takes one argument, the name of the command. Returns false
if the command wasn't defined to begin with, true otherwise.

=head2 C<list>

Takes no arguments. Returns a list of key/value pairs, the keys being the
command names and the values being the usage strings or hash references.

=head1 OUTPUT EVENTS

=head2 C<irc_botcmd_*>

You will receive an event like this for every valid command issued. E.g. if
'slap' were a valid command, you would receive an C<irc_botcmd_slap> event
every time someone issued that command. It receives the following arguments:

=over 4

=item * C<ARG0>: the nick!hostmask of the user who issued the command.

=item * C<ARG1> is the name of the channel in which the command was issued,
or the sender's nickname if this was a private message.

=item * C<ARG2>: a string of arguments to the command, or hash reference with
arguments in case you defined command along with arguments, or undef if there
were no arguments

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

=cut
