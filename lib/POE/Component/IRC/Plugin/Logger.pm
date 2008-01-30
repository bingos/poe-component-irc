package POE::Component::IRC::Plugin::Logger;

use strict;
use warnings;
use Carp;
use Encode;
use Encode::Guess;
use IO::File;
use POE::Component::IRC::Plugin qw( :ALL );
use POE::Component::IRC::Plugin::BotTraffic;
use POE::Component::IRC::Common qw( l_irc parse_user );
use POSIX qw(strftime);

our $VERSION = '1.1';

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
    $self->{mode_strings} = {
        'b' => { '+' => 'sets ban on ',                           '-' => 'removes ban on ' },
        'e' => { '+' => 'sets exempt on ',                        '-' => 'removes exempt on ' },
        'I' => { '+' => 'sets invite on ',                        '-' => 'removes invite on ' },
        'h' => { '+' => 'gives channel half-operator status to ', '-' => 'removes channel half-operator status from ' },
        'o' => { '+' => 'gives channel operator status to ',      '-' => 'removes channel operator status from ' },
        'v' => { '+' => 'gives voice to ',                        '-' => 'removes voice from ' },
        'k' => { '+' => 'sets channel keyword to ',               '-' => 'removes channel keyword' },
        'l' => { '+' => 'sets channel user limit to ',            '-' => 'removes channel user limit' },
        'i' => { '+' => 'enables invite-only channel status',     '-' => 'disables invite-only channel status' },
        'm' => { '+' => 'enables channel moderation',             '-' => 'disables channel moderation' },
        'n' => { '+' => 'disables external messages',             '-' => 'enables external messages' },
        'p' => { '+' => 'enables private channel status',         '-' => 'disables private channel status' },
        's' => { '+' => 'enables secret channel status',          '-' => 'disables secret channel status', },
        't' => { '+' => 'enables topic protection',               '-' => 'disables topic protection' },
        'a' => { '+' => 'enables anonymous channel status',       '-' => 'disables anonymous channel status' },
        'q' => { '+' => 'enables quiet channel status',           '-' => 'disables quiet channel status' },
        'r' => { '+' => 'enables channel registered status',      '-' => 'disables channel registered status' },
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
    $self->_log_msg($chan, "---   Topic for $chan is: $topic") if !$irc->channel_list($chan);
    return PCI_EAT_NONE;
}

sub S_333 {
    my ($self, $irc) = splice @_, 0, 2;
    my ($chan, $nick, $time) = @{ ${ $_[2] } };
    my $date = localtime $time;
    # only log this if we were just joining the channel
    $self->_log_msg($chan, "---   Topic for $chan set was by $nick at $date") if !$irc->channel_list($chan);
    return PCI_EAT_NONE;
}

sub S_chan_mode {
    my ($self, $irc) = splice @_, 0, 2;
    my $nick = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my ($type, $mode) = split //, ${ $_[2] };
    my $arg = ${ $_[3] };
    $arg = '' unless defined $arg;
    
    if ($self->{mode_strings}->{$mode}) {
        $self->_log_msg($chan, "---   $nick " . $self->{mode_strings}->{$mode}->{$type} . $arg);
    }
    
    return PCI_EAT_NONE;
}

sub S_ctcp_action {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender = parse_user(${ $_[0] });
    my $recipients = ${ $_[1] };
    my $msg = ${ $_[2] };
    for my $recipient (@{ $recipients }) {
        $self->_log_msg($recipient, "* $sender $msg");
    }
    return PCI_EAT_NONE;
}

sub S_bot_ctcp_action {
    my ($self, $irc) = splice @_, 0, 2;
    my $recipients = ${ $_[0] };
    my $msg = ${ $_[1] };
    for my $recipient (@{ $recipients }) {
        $self->_log_msg($recipient, '* ' . $irc->nick_name() . " $msg");
    }
    return PCI_EAT_NONE;
}

sub S_bot_msg {
    my ($self, $irc) = splice @_, 0, 2;
    my $recipients = ${ $_[0] };
    my $msg = ${ $_[1] };
    for my $recipient (@{ $recipients }) {
        $self->_log_msg($recipient, '<' . $irc->nick_name() . "> $msg");
    }
    return PCI_EAT_NONE;
}

sub S_bot_public {
    my ($self, $irc) = splice @_, 0, 2;
    my $channels = ${ $_[0] };
    my $msg = ${ $_[1] };
    for my $chan (@{ $channels }) {
        $self->_log_msg($chan, '<' . $irc->nick_name() . "> $msg");
    }
    return PCI_EAT_NONE;
}

sub S_join {
    my ($self, $irc) = splice @_, 0, 2;
    my ($joiner, $user, $host) = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    $self->_log_msg($chan, "-->   $joiner ($user\@$host) has joined $chan");
    return PCI_EAT_NONE;
}

sub S_kick {
    my ($self, $irc) = splice @_, 0, 2;
    my $kicker = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my $victim = ${ $_[2] };
    my $reason = ${ $_[3] };
        
    my $log_msg = "<--   $kicker has kicked $victim from $chan";
    $log_msg .= " ($reason)" unless $reason eq '';
    $self->_log_msg($chan, $log_msg);
    return PCI_EAT_NONE;
}

sub S_msg {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender = parse_user(${ $_[0] });
    my $msg = ${ $_[2] };
    $self->_log_msg($sender, "<$sender> $msg");
    return PCI_EAT_NONE;
}

sub S_nick {
    my ($self, $irc) = splice @_, 0, 2;
    my $old_nick = parse_user(${ $_[0] });
    my $new_nick = ${ $_[1] };
    my $channels = @{ $_[2] }[0];
    for my $chan (@{ $channels }) {
        $self->_log_msg($chan, "---   $old_nick is now known as $new_nick");
    }
    return PCI_EAT_NONE;
}

sub S_part {
    my ($self, $irc) = splice @_, 0, 2;
    my ($parter, $user, $host) = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my $reason = ${ $_[2] };
    my $log_msg = "<--   $parter ($user\@$host) has left $chan";
    $log_msg .= " ($reason)" unless $reason eq '';
    $self->_log_msg($chan, $log_msg);
    return PCI_EAT_NONE;
}

sub S_public {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender = parse_user(${ $_[0] });
    my $channels = ${ $_[1] };
    my $msg = ${ $_[2] };
    for my $chan (@{ $channels }) {
        $self->_log_msg($chan, "<$sender> $msg");
    }
    return PCI_EAT_NONE;
}

sub S_quit {
    my ($self, $irc) = splice @_, 0, 2;
    my ($quitter, $user, $host) = parse_user(${ $_[0] });
    my $reason = ${ $_[1] };
    my $channels = @{ $_[2] }[0];
    my $log_msg = "<--   $quitter ($user\@$host) has quit";
    $log_msg .= " ($reason)" unless $reason eq '';
    for my $chan (@{ $channels }) {
        $self->_log_msg($chan, $log_msg);
    }
    return PCI_EAT_NONE;
}

sub S_topic {
    my ($self, $irc) = splice @_, 0, 2;
    my $changer = parse_user(${ $_[0] });
    my $chan = ${ $_[1] };
    my $new_topic = ${ $_[2] };
    $self->_log_msg($chan, "---   $changer has changed the topic to: $new_topic");
    return PCI_EAT_NONE;
}

sub _log_msg {
    my ($self, $context, $line) = @_;
    
    return unless $context =~ /^[#&+!]/ && $self->{Public} or $context !~ /^[#&+!]/ && $self->{Private};
    $context = l_irc $context, $self->{irc}->isupport('CASEMAPPING');
    my $now = strftime '%F %T', localtime;
    
    if (!exists $self->{logs}->{$context}) {
        my $log = IO::File->new($self->{Path} . "/$context.log", '>>', 0600)
            or croak "Couldn't create file" . $self->{Path} . "/$context.log" . ": $!; aborted";
        $log->binmode(':utf8');
        $log->autoflush(1);
        print $log "***\n*** LOGGING BEGINS\n***\n";
        $self->{logs}->{$context} = $log;
    }
    
    my $decoder = guess_encoding($line, 'utf8');
    if (ref $decoder) {
        $line = $decoder->decode($line);
    }
    else {
        $line = decode('cp1252', $line);
    }
    my $log = $self->{logs}->{$context};
    print $log "$now $line\n";
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

Returns a plugin object suitable for feeding to L<POE::Component::IRC|POE::Component::IRC>'s
plugin_add() method.

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

