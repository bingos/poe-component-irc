# $Id: CTCP.pm,v 1.1 2005/04/14 19:23:17 chris Exp $
#
# POE::Filter::CTCP, by Dennis Taylor <dennis@funkplanet.com>
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Filter::CTCP;

use strict;
use warnings;
use Carp;
use File::Basename ();
use POE::Filter::IRC;
use vars qw($VERSION);

$VERSION = '5.2';

# Create a new, empty POE::Filter::CTCP object.
sub new {
    my ($package, %args) = @_;
    $args{lc $_} = delete $args{$_} for keys %args;
    $args{irc_filter} = POE::Filter::IRC->new() unless $args{irc_filter};
    return bless \%args, $package;
}

# Set/clear the 'debug' flag.
sub debug {
    my ($self, $flag) = @_;
    $self->{debug} = $flag if defined $flag;
    return $self->{debug};
}

# For each line of raw CTCP input data that we're fed, spit back the
# appropriate CTCP and normal message events.
sub get {
    my ($self, $lineref) = @_;
    my ($who, $type, $where, $ctcp, $text, $name, $args);
    my $events = [];

    LINE: for my $line (@$lineref) {
        ($who, $type, $where, $ctcp, $text) = _ctcp_dequote( $line );

        for my $string (@$ctcp) {
            if (!(($name, $args) = $string =~ /^(\w+)(?: (.*))?/)) {
                warn "Received malformed CTCP message: '$_'\n" if $self->{debug};
                next LINE;
            }
            
            if (lc $name eq 'dcc') {
                my ($type, $file, $addr, $port, $size);
                if (!(($type, $file, $addr, $port, $size)
                    = $args =~ /^(\w+) (".+"|\S+) (\d+) (\d+)(?: (\d+))?$/)) {
                    warn "Received malformed DCC request: '$args'\n" if $self->{debug};
                    next LINE;
                }
                $file =~ s/^"|"$//g;
                $file = File::Basename::fileparse($file);
                
                push @$events, {
                    name => 'dcc_request',
                    args => [
                        $who,
                        uc $type,
                        $port,
                        {
                            open => undef,
                            nick => $who,
                            type => uc $type,
                            file => $file,
                            size => $size,
                            done => 0,
                            addr => $addr,
                            port => $port,
                        },
                        $file,
                        $size,
                    ],
                    raw_line => $line,
                };
            }
            else {
                push @$events, {
                    name => $type . '_' . lc $name,
                    args => [
                        $who,
                        [split /,/, $where],
                        (defined $args ? $args : ''),
                    ],
                    raw_line => $line,
                };
            }
        }

        if ($text && scalar @$text) {
            my $what;
            ($what) = $line =~ /^(:\S+ +\w+ +\S+ +)/
                or warn "What the heck? '$line'\n" if $self->{debug};
            $text = (defined $what ? $what : '') . ':' . join '', @$text;
            $text =~ s/\cP/^P/g;
            warn "CTCP: $text\n" if $self->{debug};
            push @$events, @{$self->{irc_filter}->get( [$text] )};
        }
    }

    return $events;
}

# For each line of text we're fed, spit back a CTCP-quoted version of
# that line.
sub put {
    my ($self, $lineref) = @_;
    my $quoted = [ ];

    for my $line (@$lineref) {
        push @$quoted, _ctcp_quote($line);
    }

    return $quoted;
}

# Quotes a string in a low-level, protocol-safe, utterly brain-dead
# fashion. Returns the quoted string.
sub _low_quote {
    my ($line) = @_;
    my %enquote = ("\012" => 'n', "\015" => 'r', "\0" => '0', "\cP" => "\cP");

    if (!defined $line) {
        croak 'Not enough arguments to POE::Filter::CTCP->_low_quote';
    }

    if ($line =~ tr/[\012\015\0\cP]//) { # quote \n, \r, ^P, and \0.
        $line =~ s/([\012\015\0\cP])/\cP$enquote{$1}/g;
    }

    return $line;
}

# Does low-level dequoting on CTCP messages. I hate this protocol.
# Yes, I copied this whole section out of Net::IRC.
sub _low_dequote {
    my ($line) = @_;
    my %dequote = (n => "\012", r => "\015", 0 => "\0", "\cP" => "\cP");

    if (!defined $line) {
        croak 'Not enough arguments to POE::Filter::CTCP->_low_dequote';
    }

    # dequote \n, \r, ^P, and \0.
    # Thanks to Abigail (abigail@foad.org) for this clever bit.
    if ($line =~ tr/\cP//) {
        $line =~ s/\cP([nr0\cP])/$dequote{$1}/g;
    }

    return $line;
}


# Properly CTCP-quotes a message. Whoop.
sub _ctcp_quote {
    my ($line) = @_;

    $line = _low_quote( $line );
    #$line =~ s/\\/\\\\/g;
    $line =~ s/\001/\\a/g;

    return "\001$line\001";
}

# Splits a message into CTCP and text chunks. This is gross. Most of
# this is also stolen from Net::IRC, but I wrote that too, so it's
# used with permission. ;-)
sub _ctcp_dequote {
    my ($line) = @_;
    my (@chunks, $ctcp, $text, $who, $type, $where, $msg);

    # CHUNG! CHUNG! CHUNG!

    if (!defined $line) {
        croak 'Not enough arguments to POE::Filter::CTCP->_ctcp_dequote';
    }

    # Strip out any low-level quoting in the text.
    $line = _low_dequote( $line );

    # Filter misplaced \001s before processing... (Thanks, tchrist!)
    substr($line, rindex($line, "\001"), 1, '\\a')
        if ($line =~ tr/\001//) % 2 != 0;

    return if $line !~ tr/\001//;

    ($who, $type, $where, $msg) = ($line =~ /^:(\S+) +(\w+) +(\S+) +:?(.*)$/)
        or return;
    
    @chunks = split /\001/, $msg;
    shift @chunks if !length $chunks[0]; # FIXME: Is this safe?

    for (@chunks) {
        # Dequote unnecessarily quoted chars, and convert escaped \'s and ^A's.
        s/\\([^\\a])/$1/g;
        s/\\\\/\\/g;
        s/\\a/\001/g;
    }

    # If the line begins with a control-A, the first chunk is a CTCP
    # message. Otherwise, it starts with text and alternates with CTCP
    # messages. Really stupid protocol.
    if ($msg =~ /^\001/) {
        push @$ctcp, shift @chunks;
    }

    while (@chunks) {
        push @$text, shift @chunks;
        push @$ctcp, shift @chunks if @chunks;
    }

    # Is this a CTCP request or reply?
    $type = $type eq 'PRIVMSG' ? 'ctcp' : 'ctcpreply';

    return ($who, $type, $where, $ctcp, $text);
}

1;
__END__

=head1 NAME

POE::Filter::CTCP - A POE-based parser for the IRC protocol (CTCP).

=head1 SYNOPSIS

 my $filter = POE::Filter::CTCP->new();
 my @events = @{ $filter->get( [ @lines ] ) };
 my @msgs = @{ $filter->put( [ @messages ] ) };

=head1 DESCRIPTION

POE::Filter::CTCP converts normal text into thoroughly CTCP-quoted
messages, and transmogrifies CTCP-quoted messages into their normal,
sane components. Rather what you'd expect a filter to do.

A note: the CTCP protocol sucks bollocks. If I ever meet the fellow who
came up with it, I'll shave their head and tattoo obscenities on it.
Just read the "specification" at
http://cs-pub.bu.edu/pub/irc/support/ctcp.spec and you'll hopefully see
what I mean. Quote this, quote that, quote this again, all in different
and weird ways... and who the hell needs to send mixed CTCP and text
messages? WTF? It looks like it's practically complexity for
complexity's sake -- and don't even get me started on the design of the
DCC protocol! Anyhow, enough ranting. Onto the rest of the docs...

=head1 CONSTRUCTOR

=over

=item C<new>

Creates a new POE::Filter::CTCP object. Duh. :-)   Takes no arguments.

=back

=head1 METHODS

=over

=item C<get>

Takes an array reference containing one or more lines of CTCP-quoted
text. Returns an array reference of processed, pasteurized events.

=item C<put>

Takes an array reference of CTCP messages to be properly quoted. This
doesn't support CTCPs embedded in normal messages, which is a
brain-dead hack in the protocol, so do it yourself if you really need
it. Returns an array reference of the quoted lines for sending.

=item C<debug>

Takes a true/false value which enables/disbles debugging accordingly.
Returns the debug status.

=back

=head1 AUTHOR

Dennis "fimmtiu" Taylor, <dennis@funkplanet.com>.

=head1 SEE ALSO

The documentation for L<POE|POE> and L<POE::Component::IRC|POE::Component::IRC>.

=cut
