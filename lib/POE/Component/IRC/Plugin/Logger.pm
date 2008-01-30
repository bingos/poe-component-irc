package POE::Component::IRC::Plugin::Logger;

use strict;
use warnings;
use Carp;
use Encode;
use Encode::Guess;
use Fcntl;
use POE::Component::IRC::Plugin qw( :ALL );
use POE::Component::IRC::Plugin::BotTraffic;
use POE::Component::IRC::Common qw( l_irc parse_user );
use POSIX qw(strftime);

my $VERSION = '1.1';

sub new {
    my ($package, %self) = @_;
    if (!$self{Path}) {
        croak "$package requires a Path";
    }
    return bless \%self, $package;
}

sub PCI_register {
    my ($self, $irc) = @_;
    
    if (!$irc->isa('POE::Component::IRC::State')) {
        croak __PACKAGE__ . ' requires PoCo::IRC::State or a subclass thereof';
    }
    
    if ( !grep { $_->isa('POE::Component::IRC::Plugin::BotTraffic') } @{ $irc->pipeline->{PIPELINE} } ) {
        $irc->plugin_add('BotTraffic', POE::Component::IRC::Plugin::BotTraffic->new());
    }

    if (! -d $self->{Path}) {
        mkdir $self->{Path}, oct 700 or croak 'Cannot create directory ' . $self->{Path} . ": $!; aborted";
    }
    
    $self->{irc} = $irc;
    $self->{logs} = { };
    $self->{Private} = 1 unless exists $self->{Private};
    $self->{Public} = 1 unless exists $self->{Public};
    $self->{last_entry} = { } if exists $self->{SortByDate};
    $self->{format} = {
        privmsg      => '<%s> %s',
        action       => '* %s %s',
        join         => '--> %s (%s@%s) has joined %s',
        part         => '<-- %s (%s@%s) has left %s (%s)',
        quit         => '<-- %s (%s@%s) has quit (%s)',
        kick         => '<-- %s has kicked %s from %s (%s)',
        nick_change  => '--- %s is now known as %s',
        topic_is     => '--- Topic for %s is: %s',
        topic_set_by => '--- Topic for %s set was by %s at %s',
        topic_change => '--- %s has changed the topic to: %s',
        '+b' => '--- %s sets ban on %s',                           '-b' => '--- %s removes ban on %s',
        '+e' => '--- %s sets exempt on %s',                        '-e' => '--- %s removes exempt on %s',
        '+I' => '--- %s sets invite on %s',                        '-I' => '--- %s removes invite on %s',
        '+h' => '--- %s gives channel half-operator status to %s', '-h' => '--- %s removes channel half-operator status from %s',
        '+o' => '--- %s gives channel operator status to %s',      '-o' => '--- %s removes channel operator status from %s',
        '+v' => '--- %s gives voice to %s',                        '-v' => '--- %s removes voice from %s',
        '+k' => '--- %s sets channel keyword to %s',               '-k' => '--- %s removes channel keyword',
        '+l' => '--- %s sets channel user limit to %s',            '-l' => '--- %s removes channel user limit',
        '+i' => '--- %s enables invite-only channel status',       '-i' => '--- %s disables invite-only channel status',
        '+m' => '--- %s enables channel moderation',               '-m' => '--- %s disables channel moderation',
        '+n' => '--- %s disables external messages',               '-n' => '--- %s enables external messages',
        '+p' => '--- %s enables private channel status',           '-p' => '--- %s disables private channel status',
        '+s' => '--- %s enables secret channel status',            '-s' => '--- %s disables secret channel status',
        '+t' => '--- %s enables topic protection',                 '-t' => '--- %s disables topic protection',
        '+a' => '--- %s enables anonymous channel status',         '-a' => '--- %s disables anonymous channel status',
        '+q' => '--- %s enables quiet channel status',             '-q' => '--- %s disables quiet channel status',
        '+r' => '--- %s enables channel registered status',        '-r' => '--- %s disables channel registered status',
    };

    $irc->plugin_register($self, 'SERVER', qw(332 333 chan_mode ctcp_action bot_ctcp_action bot_msg bot_public join kick msg nick part public quit topic));
    return 1;
}

sub PCI_unregister {
    return 1;
}

sub S_332 {
    my ($self, $irc) = splice @_, 0, 2;
    my ($chan, $topic) = @{ ${ $_[2] } };
    # only log this if we were just joining the channel
    $self->_log_entry($chan, topic_is => $chan, $topic) if !$irc->channel_list($chan);
    return PCI_EAT_NONE;
}

sub S_333 {
    my ($self, $irc) = splice @_, 0, 2;
    my ($chan, $nick, $time) = @{ ${ $_[2] } };
    my $date = localtime $time;
    # only log this if we were just joining the channel
    $self->_log_entry($chan, topic_set_by => $chan, $nick, $date) if !$irc->channel_list($chan);
    return PCI_EAT_NONE;
}

sub S_chan_mode {
    my ($self, $irc) = splice @_, 0, 2;
    my $nick = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my ($mode) = ${ $_[2] };
    my $arg = ${ $_[3] };
    $self->_log_entry($chan, $mode => $nick, $arg);
    return PCI_EAT_NONE;
}

sub S_ctcp_action {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender = parse_user(${ $_[0] });
    my $recipients = ${ $_[1] };
    my $msg = ${ $_[2] };
    for my $recipient (@{ $recipients }) {
        $self->_log_entry($recipient, action => $sender, $msg);
    }
    return PCI_EAT_NONE;
}

sub S_bot_ctcp_action {
    my ($self, $irc) = splice @_, 0, 2;
    my $recipients = ${ $_[0] };
    my $msg = ${ $_[1] };
    for my $recipient (@{ $recipients }) {
        $self->_log_entry($recipient, action => $irc->nick_name(), $msg);
    }
    return PCI_EAT_NONE;
}

sub S_bot_msg {
    my ($self, $irc) = splice @_, 0, 2;
    my $recipients = ${ $_[0] };
    my $msg = ${ $_[1] };
    for my $recipient (@{ $recipients }) {
        $self->_log_entry($recipient, privmsg => $irc->nick_name(), $msg);
    }
    return PCI_EAT_NONE;
}

sub S_bot_public {
    my ($self, $irc) = splice @_, 0, 2;
    my $channels = ${ $_[0] };
    my $msg = ${ $_[1] };
    for my $chan (@{ $channels }) {
        $self->_log_entry($chan, privmsg => $irc->nick_name(), $msg);
    }
    return PCI_EAT_NONE;
}

sub S_join {
    my ($self, $irc) = splice @_, 0, 2;
    my ($joiner, $user, $host) = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    $self->_log_entry($chan, join => $joiner, $user, $host, $chan);
    return PCI_EAT_NONE;
}

sub S_kick {
    my ($self, $irc) = splice @_, 0, 2;
    my $kicker = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my $victim = ${ $_[2] };
    my $reason = ${ $_[3] };
    $self->_log_entry($chan, kick => $kicker, $victim, $chan, $reason);
    return PCI_EAT_NONE;
}

sub S_msg {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender = parse_user(${ $_[0] });
    my $msg = ${ $_[2] };
    $self->_log_entry($sender, privmsg => $sender, $msg);
    return PCI_EAT_NONE;
}

sub S_nick {
    my ($self, $irc) = splice @_, 0, 2;
    my $old_nick = parse_user(${ $_[0] });
    my $new_nick = ${ $_[1] };
    my $channels = @{ $_[2] }[0];
    for my $chan (@{ $channels }) {
        $self->_log_entry($chan, nick_change => $old_nick, $new_nick);
    }
    return PCI_EAT_NONE;
}

sub S_part {
    my ($self, $irc) = splice @_, 0, 2;
    my ($parter, $user, $host) = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my $reason = ${ $_[2] };
    $self->_log_entry($chan, part => $parter, $user, $host, $chan, $reason);
    return PCI_EAT_NONE;
}

sub S_public {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender = parse_user(${ $_[0] });
    my $channels = ${ $_[1] };
    my $msg = ${ $_[2] };
    for my $chan (@{ $channels }) {
        $self->_log_entry($chan, privmsg => $sender, $msg);
    }
    return PCI_EAT_NONE;
}

sub S_quit {
    my ($self, $irc) = splice @_, 0, 2;
    my ($quitter, $user, $host) = parse_user(${ $_[0] });
    my $reason = ${ $_[1] };
    my $channels = @{ $_[2] }[0];
    for my $chan (@{ $channels }) {
        $self->_log_entry($chan, quit => $quitter, $user, $host, $reason);
    }
    return PCI_EAT_NONE;
}

sub S_topic {
    my ($self, $irc) = splice @_, 0, 2;
    my $changer = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my $new_topic = ${ $_[2] };
    $self->_log_entry($chan, topic_change => $changer, $new_topic);
    return PCI_EAT_NONE;
}

sub _log_entry {
    my ($self, $context, $type, @args) = @_;
    $context = l_irc $context, $self->{irc}->isupport('CASEMAPPING');
    return unless $context =~ /^[#&+!]/ && $self->{Public} or $context !~ /^[#&+!]/ && $self->{Private};
    return unless exists $self->{format}->{$type};
    
    my $date = strftime '%F', localtime;
    if ($self->{SortByDate}) {
        if (! -d $self->{Path} . "/$context") {
            mkdir $self->{Path} . "/$context", oct 700 or croak "Couldn't create directory " . $self->{Path} . "/$context: $!; aborted";
        }

        if (!exists $self->{logs}->{$context}) {
            $self->{logs}->{$context} = $self->_open_log($self->{Path} . "/$context/$date.log");
            print {$self->{logs}->{$context}} "***\n*** LOGGING BEGINS\n***\n";
        }
        elsif ($self->{last_entry}->{$context} ne $date) {
            $self->{logs}->{$context} = $self->_open_log($self->{Path} . "/$context/$date.log");
        }
    }
    elsif (!exists $self->{logs}->{$context}) {
        $self->{logs}->{$context} = $self->_open_log($self->{Path} . "/$context.log");
        print {$self->{logs}->{$context}} "***\n*** LOGGING BEGINS\n***\n";
    }

    my $line = strftime('%F %T ', localtime) . sprintf($self->{format}->{$type}, @args);
    my $decoder = guess_encoding($line, 'utf8');
    if (ref $decoder) {
        $line = $decoder->decode($line);
    }
    else {
        $line = decode('cp1252', $line);
    }
    print {$self->{logs}->{$context}} "$line\n";
    $self->{last_entry}->{$context} = $date if $self->{SortByDate};
}

sub _open_log {
    my ($self, $file_name) = @_;
    sysopen(my $log, $file_name, O_WRONLY|O_APPEND|O_CREAT, 0600) or croak "Couldn't create file $file_name: $!; aborted";
    binmode($log, ':utf8');
    $log->autoflush(1);
    return $log;
}

1;

=head1 NAME

POE::Component::IRC::Plugin::Logger - A PoCo-IRC plugin which
logs public and private messages to disk.

=head1 SYNOPSIS

 use POE::Component::IRC::Plugin::Logger;

 $irc->plugin_add('Logger', POE::Component::IRC::Plugin::Logger->new(
     Path    => '/home/me/irclogs',
     Private => 0,
     Public  => 1,
 ));

=head1 DESCRIPTION

POE::Component::IRC::Plugin::Logger is a L<POE::Component::IRC|POE::Component::IRC> plugin.
It logs messages and CTCP ACTIONs to either #some_channel.log or some_nickname.log in the supplied path.
It tries to detect UTF-8 encoding of every message or else falls back to
CP1252 (like irssi does by default). The log format is similar to xchat's, except that it's sane and parsable.

This plugin requires the IRC component to be L<POE::Component::IRC::State|POE::Component::IRC::State>
or a subclass thereof. It also requires a L<POE::Component::IRC::Plugin::BotTraffic|POE::Component::IRC::Plugin::BotTraffic>
to be in the plugin pipeline. It will be added automatically if it is not present.

=head1 METHODS

=over

=item new

Arguments:

 'Path', the place where you want the logs saved.
 'Private', whether or not to log private messages. Defaults to 1.
 'Public', whether or not to log public messages. Defaults to 1.
 'SortByDate, whether or not to split log files by date. I.e. C<$channel/$date.log>
 instead of C<$channel.log>. Defaults to 0.

Returns a plugin object suitable for feeding to L<POE::Component::IRC|POE::Component::IRC>'s
plugin_add() method.

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

