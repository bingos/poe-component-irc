package POE::Component::IRC;

use strict;
use warnings FATAL => 'all';
use Carp;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Driver::SysRW
           Filter::Line Filter::Stream Filter::Stackable);
use POE::Filter::IRCD;
use POE::Filter::IRC::Compat;
use POE::Component::IRC::Constants qw(:ALL);
use POE::Component::IRC::Plugin qw(:ALL);
use POE::Component::IRC::Plugin::DCC;
use POE::Component::IRC::Plugin::ISupport;
use POE::Component::IRC::Plugin::Whois;
use Socket qw(AF_INET SOCK_STREAM unpack_sockaddr_in inet_ntoa inet_aton);
use base qw(POE::Component::Syndicator);

our ($GOT_SSL, $GOT_CLIENT_DNS, $GOT_SOCKET6, $GOT_ZLIB);

BEGIN {
    eval {
        require POE::Component::SSLify;
        import POE::Component::SSLify qw( Client_SSLify SSLify_ContextCreate );
        $GOT_SSL = 1;
    };
    eval {
        require POE::Component::Client::DNS;
        $GOT_CLIENT_DNS = 1 if $POE::Component::Client::DNS::VERSION >= 0.99;
    };
    eval {
        require POE::Filter::Zlib::Stream;
        $GOT_ZLIB = 1 if $POE::Filter::Zlib::Stream::VERSION >= 1.96;
    };
    # Socket6 provides AF_INET6 where earlier Perls' Socket don't.
    eval {
        Socket->import(qw(AF_INET6 unpack_sockaddr_in6 inet_ntop));
        $GOT_SOCKET6 = 1;
    };
    if (!$GOT_SOCKET6) {
        eval {
            require Socket6;
            Socket6->import(qw(AF_INET6 unpack_sockaddr_in6 inet_ntop));
            $GOT_SOCKET6 = 1;
        };
        if (!$GOT_SOCKET6) {
            # provide a dummy sub so code compiles
            *AF_INET6 = sub { ~0 };
        }
    }
}

# BINGOS: I have bundled up all the stuff that needs changing
# for inherited classes into _create. This gets called from 'spawn'.
# $self->{OBJECT_STATES_ARRAYREF} contains event mappings to methods that have
# the same name, gets passed to POE::Session->create as $self => [ ];
# $self->{OBJECT_STATES_HASHREF} contains event mappings to methods, where the
# event and the method have diferent names.
# $self->{IRC_CMDS} contains the traditional %irc_commands, mapping commands
# to events and the priority that the command has.
sub _create {
    my ($self) = @_;

    $self->{IRC_CMDS} = {
        rehash    => [ PRI_HIGH,     'noargs',        ],
        die       => [ PRI_HIGH,     'noargs',        ],
        restart   => [ PRI_HIGH,     'noargs',        ],
        quit      => [ PRI_NORMAL,   'oneoptarg',     ],
        version   => [ PRI_HIGH,     'oneoptarg',     ],
        time      => [ PRI_HIGH,     'oneoptarg',     ],
        trace     => [ PRI_HIGH,     'oneoptarg',     ],
        admin     => [ PRI_HIGH,     'oneoptarg',     ],
        info      => [ PRI_HIGH,     'oneoptarg',     ],
        away      => [ PRI_HIGH,     'oneoptarg',     ],
        users     => [ PRI_HIGH,     'oneoptarg',     ],
        lusers    => [ PRI_HIGH,     'oneoptarg',     ],
        locops    => [ PRI_HIGH,     'oneoptarg',     ],
        operwall  => [ PRI_HIGH,     'oneoptarg',     ],
        wallops   => [ PRI_HIGH,     'oneoptarg',     ],
        motd      => [ PRI_HIGH,     'oneoptarg',     ],
        who       => [ PRI_HIGH,     'oneoptarg',     ],
        nick      => [ PRI_HIGH,     'onlyonearg',    ],
        oper      => [ PRI_HIGH,     'onlytwoargs',   ],
        invite    => [ PRI_HIGH,     'onlytwoargs',   ],
        squit     => [ PRI_HIGH,     'onlytwoargs',   ],
        kill      => [ PRI_HIGH,     'onlytwoargs',   ],
        privmsg   => [ PRI_NORMAL,   'privandnotice', ],
        privmsglo => [ PRI_NORMAL+1, 'privandnotice', ],
        privmsghi => [ PRI_NORMAL-1, 'privandnotice', ],
        notice    => [ PRI_NORMAL,   'privandnotice', ],
        noticelo  => [ PRI_NORMAL+1, 'privandnotice', ],
        noticehi  => [ PRI_NORMAL-1, 'privandnotice', ],
        squery    => [ PRI_NORMAL,   'privandnotice', ],
        join      => [ PRI_HIGH,     'oneortwo',      ],
        summon    => [ PRI_HIGH,     'oneortwo',      ],
        sconnect  => [ PRI_HIGH,     'oneandtwoopt',  ],
        whowas    => [ PRI_HIGH,     'oneandtwoopt',  ],
        stats     => [ PRI_HIGH,     'spacesep',      ],
        links     => [ PRI_HIGH,     'spacesep',      ],
        mode      => [ PRI_HIGH,     'spacesep',      ],
        servlist  => [ PRI_HIGH,     'spacesep',      ],
        cap       => [ PRI_HIGH,     'spacesep',      ],
        part      => [ PRI_HIGH,     'commasep',      ],
        names     => [ PRI_HIGH,     'commasep',      ],
        list      => [ PRI_HIGH,     'commasep',      ],
        whois     => [ PRI_HIGH,     'commasep',      ],
        ctcp      => [ PRI_HIGH,     'ctcp',          ],
        ctcpreply => [ PRI_HIGH,     'ctcp',          ],
        ping      => [ PRI_HIGH,     'oneortwo',      ],
        pong      => [ PRI_HIGH,     'oneortwo',      ],
    };

    my %event_map = map {($_ => $self->{IRC_CMDS}->{$_}->[CMD_SUB])}
        keys %{ $self->{IRC_CMDS} };

    $self->{OBJECT_STATES_HASHREF} = {
        %event_map,
        quote => 'sl',
    };

    $self->{OBJECT_STATES_ARRAYREF} = [qw(
        syndicator_started
        _parseline
        _sock_down
        _sock_failed
        _sock_up
        _socks_proxy_connect
        _socks_proxy_response
        debug
        connect
        _resolve_addresses
        _do_connect
        _quit_timeout
        _send_login
        _got_dns_response
        ison
        kick
        remove
        nickserv
        shutdown
        sl
        sl_login
        sl_high
        sl_delayed
        sl_prioritized
        topic
        userhost
    )];

    return;
}

# BINGOS: the component can now configure itself via _configure() from
# either spawn() or connect()
## no critic (Subroutines::ProhibitExcessComplexity)
sub _configure {
    my ($self, $args) = @_;
    my $spawned = 0;

    if (ref $args eq 'HASH' && keys %{ $args }) {
        $spawned = delete $args->{spawned};
        $self->{use_localaddr} = delete $args->{localaddr};
        @{ $self }{ keys %{ $args } } = values %{ $args };
    }

    if ($ENV{POCOIRC_DEBUG}) {
        $self->{debug} = 1;
        $self->{plugin_debug} = 1;
    }

    if ($self->{debug}) {
        $self->{ircd_filter}->debug(1);
        $self->{ircd_compat}->debug(1);
    }

    if ($self->{useipv6} && !$GOT_SOCKET6) {
        warn "'useipv6' option specified, but Socket6 was not found\n";
    }

    if ($self->{usessl} && !$GOT_SSL) {
        warn "'usessl' option specified, but POE::Component::SSLify was not found\n";
    }

    $self->{dcc}->nataddr($self->{nataddr}) if exists $self->{nataddr};
    $self->{dcc}->dccports($self->{dccports}) if exists $self->{dccports};

    $self->{port} = 6667 if !$self->{port};
    $self->{msg_length} = 450 if !defined $self->{msg_length};

    if ($self->{use_localaddr}) {
        $self->{localaddr} = $self->{use_localaddr}
            . ($self->{localport} ? (':'.$self->{localport}) : '');
    }

    # Make sure that we have reasonable defaults for all the attributes.
    # The "IRC*" variables are ircII environment variables.
    if (!defined $self->{nick}) {
        $self->{nick} = $ENV{IRCNICK} || eval { scalar getpwuid($>) }
            || $ENV{USER} || $ENV{LOGNAME} || 'WankerBot';
    }

    if (!defined $self->{username}) {
        $self->{username} = eval { scalar getpwuid($>) } || $ENV{USER}
            || $ENV{LOGNAME} || 'foolio';
    }

    if (!defined $self->{ircname}) {
        $self->{ircname} = $ENV{IRCNAME} || eval { (getpwuid $>)[6] }
            || 'Just Another Perl Hacker';
    }

    if (!defined $self->{server} && !$spawned) {
        die "No IRC server specified\n" if !$ENV{IRCSERVER};
        $self->{server} = $ENV{IRCSERVER};
    }

    if (defined $self->{webirc}) {
        if (!ref $self->{webirc} ne 'HASH') {
            die "webirc param expects a hashref";
        }
        for my $expect_key (qw(pass user host ip)) {
            if (!exists $self->{webirc}{$expect_key}) {
                die "webirc value is missing key '$expect_key'";
            }
        }
    }

    return;
}

sub debug {
    my ($self, $switch) = @_[OBJECT, ARG0];

    $self->{debug} = $switch;
    $self->{ircd_filter}->debug( $switch );
    $self->{ircd_compat}->debug( $switch );
    return;
}

# Parse a message from the IRC server and generate the appropriate
# event(s) for listening sessions.
sub _parseline {
    my ($session, $self, $ev) = @_[SESSION, OBJECT, ARG0];

    return if !$ev->{name};
    $self->send_event(irc_raw => $ev->{raw_line} ) if $self->{raw};

    # record our nickname
    if ( $ev->{name} eq '001' ) {
        $self->{INFO}{RealNick} = ( split / /, $ev->{raw_line} )[2];
    }

    $ev->{name} = 'irc_' . $ev->{name};
    $self->send_event( $ev->{name}, @{$ev->{args}} );

    if ($ev->{name} =~ /^irc_ctcp_(.+)$/) {
        $self->send_event(irc_ctcp => $1 => @{$ev->{args}});
    }

    return;
}

# Internal function called when a socket is closed.
sub _sock_down {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    # Destroy the RW wheel for the socket.
    delete $self->{socket};
    delete $self->{localaddr};
    $self->{connected} = 0;

    # Stop any delayed sends.
    $self->{send_queue} = [ ];
    $self->{send_time}  = 0;
    $kernel->delay( sl_delayed => undef );

    # Reset the filters if necessary
    $self->_compress_uplink( 0 );
    $self->_compress_downlink( 0 );
    $self->{ircd_compat}->chantypes( [ '#', '&' ] );
    $self->{ircd_compat}->identifymsg(0);

    # post a 'irc_disconnected' to each session that cares
    $self->send_event(irc_disconnected => $self->{server} );
    return;
}

sub disconnect {
    my ($self) = @_;
    $self->yield('_sock_down');
    return;
}

# Internal function called when a socket fails to be properly opened.
sub _sock_failed {
    my ($self, $op, $errno, $errstr) = @_[OBJECT, ARG0..ARG2];

    delete $self->{socketfactory};
    $self->send_event(irc_socketerr => "$op error $errno: $errstr" );
    return;
}

# Internal function called when a connection is established.
sub _sock_up {
    my ($kernel, $self, $session, $socket) = @_[KERNEL, OBJECT, SESSION, ARG0];

    # We no longer need the SocketFactory wheel. Scrap it.
    delete $self->{socketfactory};

    # Remember what IP address we're connected through, for multihomed boxes.
    my $localaddr;
    if ($GOT_SOCKET6) {
        eval {
                $localaddr = (unpack_sockaddr_in6( getsockname $socket ))[1];
                $localaddr = inet_ntop( AF_INET6, $localaddr );
        };
    }

    if ( !$localaddr ) {
        $localaddr = (unpack_sockaddr_in( getsockname $socket ))[1];
        $localaddr = inet_ntoa($localaddr);
    }

    $self->{localaddr} = $localaddr;

    if ( $self->{socks_proxy} ) {
        $self->{socket} = POE::Wheel::ReadWrite->new(
            Handle       => $socket,
            Driver       => POE::Driver::SysRW->new(),
            Filter       => POE::Filter::Stream->new(),
            InputEvent   => '_socks_proxy_response',
            ErrorEvent   => '_sock_down',
        );

        if ( !$self->{socket} ) {
            $self->send_event(irc_socketerr =>
                "Couldn't create ReadWrite wheel for SOCKS socket" );
            return;
        }

        my $packet;
        if ( _ip_is_ipv4( $self->{server} ) ) {
            # SOCKS 4
            $packet = pack ('CCn', 4, 1, $self->{port}) .
            inet_aton($self->{server}) . ($self->{socks_id} || '') . (pack 'x');
        }
        else {
            # SOCKS 4a
            $packet = pack ('CCn', 4, 1, $self->{port}) .
            inet_aton('0.0.0.1') . ($self->{socks_id} || '') . (pack 'x') .
            $self->{server} . (pack 'x');
        }

        $self->{socket}->put( $packet );
        return;
    }

    # ssl!
    if ($GOT_SSL and $self->{usessl}) {
        eval {
            my ($ctx);

            if( $self->{sslctx} )
            {
                $ctx = $self->{sslctx};
            }
            elsif( $self->{sslkey} && $self->{sslcert} )
            {
                $ctx = SSLify_ContextCreate( $self->{sslkey}, $self->{sslcert} );
            }
            else
            {
                $ctx = undef;
            }

            $socket = Client_SSLify($socket, undef, undef, $ctx);
        };

        if ($@) {
         	chomp $@;
            warn "Couldn't use an SSL socket: $@\n";
            $self->{usessl} = 0;
        }
    }

    if ( $self->{compress} ) {
        $self->_compress_uplink(1);
        $self->_compress_downlink(1);
    }

    # Create a new ReadWrite wheel for the connected socket.
    $self->{socket} = POE::Wheel::ReadWrite->new(
        Handle       => $socket,
        Driver       => POE::Driver::SysRW->new(),
        InputFilter  => $self->{srv_filter},
        OutputFilter => $self->{out_filter},
        InputEvent   => '_parseline',
        ErrorEvent   => '_sock_down',
    );

    if ($self->{socket}) {
        $self->{connected} = 1;
    }
    else {
        $self->send_event(irc_socketerr => "Couldn't create ReadWrite wheel for IRC socket");
        return;
    }

    # Post a 'irc_connected' event to each session that cares
    $self->send_event(irc_connected => $self->{server} );

    # CONNECT if we're using a proxy
    if ($self->{proxy}) {
        # The original proxy code, AFAIK, did not actually work
        # with an HTTP proxy.
        $self->call(
            'sl_login',
            'CONNECT ' . $self->{server} . ':' . $self->{port} . " HTTP/1.0\n\n",
        );

        # KLUDGE: Also, the original proxy code assumes the connection
        # is instantaneous Since this is not always the case, mess with
        # the queueing so that the sent text is delayed...
        $self->{send_time} = time() + 10;
    }

    $kernel->yield('_send_login');
    return;
}

sub _socks_proxy_response {
    my ($kernel, $self, $session, $input) = @_[KERNEL, OBJECT, SESSION, ARG0];

    if (length $input != 8) {
        $self->send_event(
            'irc_socks_failed',
            'Mangled response from SOCKS proxy',
            $input,
        );
        $self->disconnect();
        return;
    }

    my @resp = unpack 'CCnN', $input;
    if (@resp != 4 || $resp[0] ne '0' || $resp[1] !~ /^(?:90|91|92|93)$/) {
        $self->send_event(
            'irc_socks_failed',
            'Mangled response from SOCKS proxy',
            $input,
        );
        $self->disconnect();
        return;
    }

    if ( $resp[1] eq '90' ) {
        $kernel->call($session => '_socks_proxy_connect');
        $self->{connected} = 1;
        $self->send_event( 'irc_connected', $self->{server} );
        $kernel->yield('_send_login');
    }
    else {
        $self->send_event(
            'irc_socks_rejected',
            $resp[1],
            $self->{socks_proxy},
            $self->{socks_port},
            $self->{socks_id},
        );
        $self->disconnect();
    }

    return;
}

sub _socks_proxy_connect {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    $self->{socket}->event( InputEvent => '_parseline' );
    $self->{socket}->set_input_filter( $self->{srv_filter} );
    $self->{socket}->set_output_filter( $self->{out_filter} );
    return;
}

sub _send_login {
    my ($kernel, $self, $session) = @_[KERNEL, OBJECT, SESSION];

    # Now that we're connected, attempt to log into the server.

    # for servers which support CAP, it's customary to start with that
    $kernel->call($session, 'sl_login', 'CAP REQ :identify-msg');
    $kernel->call($session, 'sl_login', 'CAP REQ :multi-prefix');
    $kernel->call($session, 'sl_login', 'CAP LS');
    $kernel->call($session, 'sl_login', 'CAP END');

    # If we were told to use WEBIRC to spoof our host/IP, do so:
    if (defined $self->{webirc}) {
        $kernel->call($session => sl_login => 'WEBIRC '
            . join " ", @{$self->{webirc}}{qw(pass user ip host)}
        );
    }

    if (defined $self->{password}) {
        $kernel->call($session => sl_login => 'PASS ' . $self->{password});
    }
    $kernel->call($session => sl_login => 'NICK ' . $self->{nick});
    $kernel->call(
        $session,
        'sl_login',
        'USER ' .
        join(' ', $self->{username},
            (defined $self->{bitmode} ? $self->{bitmode} : 8),
            '*',
            ':' . $self->{ircname}
        ),
    );

    # If we have queued data waiting, its flush loop has stopped
    # while we were disconnected.  Start that up again.
    $kernel->delay(sl_delayed => 0);

    return;
}

# Set up the component's IRC session.
sub syndicator_started {
    my ($kernel, $session, $sender, $self, $alias)
        = @_[KERNEL, SESSION, SENDER, OBJECT, ARG0, ARG1 .. $#_];

    # Send queue is used to hold pending lines so we don't flood off.
    # The count is used to track the number of lines sent at any time.
    $self->{send_queue} = [ ];
    $self->{send_time}  = 0;

    $self->{ircd_filter} = POE::Filter::IRCD->new(debug => $self->{debug});
    $self->{ircd_compat} = POE::Filter::IRC::Compat->new(debug => $self->{debug});

    my $srv_filters = [
        POE::Filter::Line->new(
            InputRegexp => '\015?\012',
            OutputLiteral => '\015\012',
        ),
        $self->{ircd_filter},
        $self->{ircd_compat},
    ];

    $self->{srv_filter} = POE::Filter::Stackable->new(Filters => $srv_filters);
    $self->{out_filter} = POE::Filter::Stackable->new(Filters => [
        POE::Filter::Line->new( OutputLiteral => "\015\012" ),
    ]);

    # Plugin 'irc_whois' and 'irc_whowas' support
    $self->plugin_add('Whois_' . $self->session_id(),
        POE::Component::IRC::Plugin::Whois->new()
    );

    $self->{isupport} = POE::Component::IRC::Plugin::ISupport->new();
    $self->plugin_add('ISupport_' . $self->session_id(), $self->{isupport});
    $self->{dcc} = POE::Component::IRC::Plugin::DCC->new();
    $self->plugin_add('DCC_' . $self->session_id(), $self->{dcc});

    return 1;
}

# The handler for commands which have N arguments, separated by commas.
sub commasep {
    my ($kernel, $self, $state, @args) = @_[KERNEL, OBJECT, STATE, ARG0 .. $#_];
    my $args;

    if ($state eq 'whois' and @args > 1 ) {
        $args = shift @args;
        $args .= ' ' . join ',', @args;
    }
    elsif ( $state eq 'part' and @args > 1 ) {
        my $chantypes = join('', @{ $self->isupport('CHANTYPES') || ['#', '&']});
        my $message;
        if ($args[-1] =~ / +/ || $args[-1] !~ /^[$chantypes]/) {
            $message = pop @args;
        }
        $args = join(',', @args);
        $args .= " :$message" if defined $message;
    }
    else {
        $args = join ',', @args;
    }

    my $pri = $self->{IRC_CMDS}->{$state}->[CMD_PRI];
    $state = uc $state;
    $state .= " $args" if defined $args;
    $kernel->yield(sl_prioritized => $pri, $state );

    return;
}

# Get variables in order for openning a connection
sub connect {
    my ($kernel, $self, $session, $sender, $args)
        = @_[KERNEL, OBJECT, SESSION, SENDER, ARG0];

    if ($args) {
        my %arg;
        %arg = @{ $args } if ref $args eq 'ARRAY';
        %arg = %{ $args } if ref $args eq 'HASH';
        $arg{ lc $_ } = delete $arg{$_} for keys %arg;
        $self->_configure( \%arg );
    }

    if ( $self->{resolver} && $self->{res_addresses}
        && @{ $self->{res_addresses} } ) {
        push @{ $self->{res_addresses} }, $self->{server};
        $self->{resolved_server} = shift @{ $self->{res_addresses} };
    }

    # try and use non-blocking resolver if needed
    if ( $self->{resolver} && !_ip_get_version( $self->{server} )
        && !$self->{nodns} ) {
        $kernel->yield(
            '_resolve_addresses',
             $self->{server},
             ( $self->{useipv6} && $GOT_SOCKET6 ? 'AAAA' : 'A' ),
        );
    }
    else {
        $kernel->yield('_do_connect');
    }

    $self->{INFO}{RealNick} = $self->{nick};
    return;
}

sub _resolve_addresses {
    my ($kernel, $self, $hostname, $type) = @_[KERNEL, OBJECT, ARG0 .. ARG1];

    my $response = $self->{resolver}->resolve(
        event => '_got_dns_response',
        host => $hostname,
        type => $type,
        context => { },
    );

    $kernel->yield(_got_dns_response => $response) if $response;
    return;
}

# open the connection
sub _do_connect {
    my ($kernel, $self, $session) = @_[KERNEL, OBJECT, SESSION];
    my $domain = AF_INET;

    # Disconnect if we're already logged into a server.
    $kernel->call($session => 'quit') if $self->{socket};

    if ($self->{socks_proxy} && !$self->{socks_port}) {
        $self->{socks_port} = 1080;
    }

    for my $address (qw(socks_proxy proxy server resolved_server use_localaddr)) {
        next if !$self->{$address} || !_ip_is_ipv6( $self->{$address} );
        if (!$GOT_SOCKET6) {
            warn "IPv6 address specified for '$address' but Socket6 not found\n";
            return;
        }
        $domain = AF_INET6;
    }

    $self->{socketfactory} = POE::Wheel::SocketFactory->new(
        SocketDomain   => $domain,
        SocketType     => SOCK_STREAM,
        SocketProtocol => 'tcp',
        RemoteAddress  => $self->{socks_proxy} || $self->{proxy} || $self->{resolved_server} || $self->{server},
        RemotePort     => $self->{socks_port} || $self->{proxyport} || $self->{port},
        SuccessEvent   => '_sock_up',
        FailureEvent   => '_sock_failed',
        ($self->{use_localaddr} ? (BindAddress => $self->{use_localaddr}) : ()),
    );

    return;
}

# got response from POE::Component::Client::DNS
sub _got_dns_response {
    my ($kernel, $self, $response) = @_[KERNEL, OBJECT, ARG0];

    my $type = uc $response->{type};
    my $net_dns_packet = $response->{response};
    my $net_dns_errorstring = $response->{error};
    $self->{res_addresses} = [ ];

    if (!defined $net_dns_packet) {
        $self->send_event(irc_socketerr => $net_dns_errorstring );
        return;
    }

    my @net_dns_answers = $net_dns_packet->answer;

    for my $net_dns_answer (@net_dns_answers) {
        next if $net_dns_answer->type !~ /^A/;
        push @{ $self->{res_addresses} }, $net_dns_answer->rdatastr;
    }

    if ( !@{ $self->{res_addresses} } && $type eq 'AAAA') {
        $kernel->yield(_resolve_addresses => $self->{server}, 'A');
        return;
    }

    if ( !@{ $self->{res_addresses} } ) {
        $self->send_event(irc_socketerr => 'Unable to resolve ' . $self->{server});
        return;
      }

    if ( my $address = shift @{ $self->{res_addresses} } ) {
        $self->{resolved_server} = $address;
        $kernel->yield('_do_connect');
        return;
    }

    $self->send_event(irc_socketerr => 'Unable to resolve ' . $self->{server});
    return;
}

# Send a CTCP query or reply, with the same syntax as a PRIVMSG event.
sub ctcp {
    my ($kernel, $state, $self, $to) = @_[KERNEL, STATE, OBJECT, ARG0];
    my $message = join ' ', @_[ARG1 .. $#_];

    if (!defined $to || !defined $message) {
        warn "The '$state' event requires two arguments\n";
        return;
    }

    # CTCP-quote the message text.
    ($message) = @{$self->{ircd_compat}->put([ $message ])};

    # Should we send this as a CTCP request or reply?
    $state = $state eq 'ctcpreply' ? 'notice' : 'privmsg';

    $kernel->yield($state, $to, $message);
    return;
}

# The way /notify is implemented in IRC clients.
sub ison {
    my ($kernel, @nicks) = @_[KERNEL, ARG0 .. $#_];
    my $tmp = 'ISON';

    if (!@nicks) {
        warn "The 'ison' event requires one or more nicknames\n";
        return;
    }

    # We can pass as many nicks as we want, as long as it's shorter than
    # the maximum command length (510). If the list we get is too long,
    # w'll break it into multiple ISON commands.
    while (@nicks) {
        my $nick = shift @nicks;
        if (length($tmp) + length($nick) >= 509) {
            $kernel->yield(sl_high => $tmp);
            $tmp = 'ISON';
        }
        $tmp .= " $nick";
    }

    $kernel->yield(sl_high => $tmp);
    return;
}

# Tell the IRC server to forcibly remove a user from a channel.
sub kick {
    my ($kernel, $chan, $nick) = @_[KERNEL, ARG0, ARG1];
    my $message = join '', @_[ARG2 .. $#_];

    if (!defined $chan || !defined $nick) {
        warn "The 'kick' event requires at least two arguments\n";
        return;
    }

    $nick .= " :$message" if defined $message;
    $kernel->yield(sl_high => "KICK $chan $nick");
    return;
}

# Tell the IRC server to forcibly remove a user from a channel. Freenode extension
sub remove {
    my ($kernel, $chan, $nick) = @_[KERNEL, ARG0, ARG1];
    my $message = join '', @_[ARG2 .. $#_];

    if (!defined $chan || !defined $nick) {
        warn "The 'remove' event requires at least two arguments\n";
        return;
    }

    $nick .= " :$message" if defined $message;
    $kernel->yield(sl_high => "REMOVE $chan $nick");
    return;
}

# Interact with NickServ
sub nickserv {
    my ($kernel, $self, $state) = @_[KERNEL, OBJECT, STATE];
    my $args = join ' ', @_[ARG0 .. $#_];

    my $command = 'NICKSERV';
    my $version = $self->server_version();
    $command = 'NS' if defined $version && $version =~ /ratbox/i;
    $command .= " $args" if defined $args;

    $kernel->yield(sl_high => $command);
    return;
}

# Set up a new IRC component. Deprecated.
sub new {
    my ($package, $alias) = splice @_, 0, 2;
    croak "$package options should be an even-sized list" if @_ & 1;
    my %options = @_;

    if (!defined $alias) {
        croak 'Not enough arguments to POE::Component::IRC::new()';
    }

    carp "Use of ${package}->new() is deprecated, please use spawn()";

    my $self = $package->spawn ( alias => $alias, options => \%options );
    return $self;
}

# Set up a new IRC component. New interface.
sub spawn {
    my ($package) = shift;
    croak "$package requires an even number of arguments" if @_ & 1;
    my %params = @_;

    $params{ lc $_ } = delete $params{$_} for keys %params;
    delete $params{options} if ref $params{options} ne 'HASH';

    my $self = bless { }, $package;
    $self->_create();

    if ($ENV{POCOIRC_DEBUG}) {
        $params{debug} = 1;
        $params{plugin_debug} = 1;
    }

    my $options      = delete $params{options};
    my $alias        = delete $params{alias};
    my $plugin_debug = delete $params{plugin_debug};

    $self->_syndicator_init(
        prefix          => 'irc_',
        reg_prefix      => 'PCI_',
        types           => [SERVER => 'S', USER => 'U'],
        alias           => $alias,
        register_signal => 'POCOIRC_REGISTER',
        shutdown_signal => 'POCOIRC_SHUTDOWN',
        object_states   => [
            $self => delete $self->{OBJECT_STATES_HASHREF},
            $self => delete $self->{OBJECT_STATES_ARRAYREF},
        ],
        ($plugin_debug ? (debug => 1) : () ),
        (ref $options eq 'HASH' ? ( options => $options ) : ()),
    );

    $params{spawned} = 1;
    $self->_configure(\%params);

    if (!$params{nodns} && $GOT_CLIENT_DNS && !$self->{resolver}) {
        $self->{resolver} = POE::Component::Client::DNS->spawn(
            Alias => 'resolver' . $self->session_id()
        );
        $self->{mydns} = 1;
    }

    return $self;
}

# The handler for all IRC commands that take no arguments.
sub noargs {
    my ($kernel, $state, $arg) = @_[KERNEL, STATE, ARG0];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    if (defined $arg) {
        warn "The '$state' event takes no arguments\n";
        return;
    }

    $state = uc $state;
    $kernel->yield(sl_prioritized => $pri, $state);
    return;
}

# The handler for commands that take one required and two optional arguments.
sub oneandtwoopt {
    my ($kernel, $state) = @_[KERNEL, STATE];
    my $arg = join '', @_[ARG0 .. $#_];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    $state = 'connect' if $state eq 'sconnect';
    $state = uc $state;
    if (defined $arg) {
        $arg = ':' . $arg if $arg =~ /\x20/;
        $state .= " $arg";
    }

    $kernel->yield(sl_prioritized => $pri, $state);
    return;
}

# The handler for commands that take at least one optional argument.
sub oneoptarg {
    my ($kernel, $state) = @_[KERNEL, STATE];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];
    $state = uc $state;

    if (defined $_[ARG0]) {
        my $arg = join '', @_[ARG0 .. $#_];
        $arg = ':' . $arg if $arg =~ /\x20/;
        $state .= " $arg";
    }

    $kernel->yield(sl_prioritized => $pri, $state);
    return;
}

# The handler for commands which take one required and one optional argument.
sub oneortwo {
    my ($kernel, $state, $one) = @_[KERNEL, STATE, ARG0];
    my $two = join '', @_[ARG1 .. $#_];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    if (!defined $one) {
        warn "The '$state' event requires at least one argument\n";
        return;
    }

    $state = uc( $state ) . " $one";
    $state .= " $two" if defined $two;
    $kernel->yield(sl_prioritized => $pri, $state);
    return;
}

# Handler for commands that take exactly one argument.
sub onlyonearg {
    my ($kernel, $state) = @_[KERNEL, STATE];
    my $arg = join '', @_[ARG0 .. $#_];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    if (!defined $arg) {
        warn "The '$state' event requires one argument\n";
        return;
    }

    $state = uc $state;
    $arg = ':' . $arg if $arg =~ /\x20/;
    $state .= " $arg";
    $kernel->yield(sl_prioritized => $pri, $state);
    return;
}

# Handler for commands that take exactly two arguments.
sub onlytwoargs {
    my ($kernel, $state, $one) = @_[KERNEL, STATE, ARG0];
    my ($two) = join '', @_[ARG1 .. $#_];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    if (!defined $one || !defined $two) {
        warn "The '$state' event requires two arguments\n";
        return;
    }

    $state = uc $state;
    $two = ':' . $two if $two =~ /\x20/;
    $state .= " $one $two";
    $kernel->yield(sl_prioritized => $pri, $state);
    return;
}

# Handler for privmsg or notice events.
sub privandnotice {
    my ($kernel, $state, $to, $msg) = @_[KERNEL, STATE, ARG0, ARG1];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    $state =~ s/privmsglo/privmsg/;
    $state =~ s/privmsghi/privmsg/;
    $state =~ s/noticelo/notice/;
    $state =~ s/noticehi/notice/;

    if (!defined $to || !defined $msg) {
        warn "The '$state' event requires two arguments\n";
        return;
    }

    $to = join ',', @$to if ref $to eq 'ARRAY';
    $state = uc $state;

    $kernel->yield(sl_prioritized => $pri, "$state $to :$msg");
    return;
}

# Tell the IRC session to go away.
sub shutdown {
    my ($kernel, $self, $sender, $session) = @_[KERNEL, OBJECT, SENDER, SESSION];
    return if $self->{_shutdown};
    $self->{_shutdown} = $sender->ID();

    if ($self->logged_in()) {
        my ($msg, $timeout) = @_[ARG0, ARG1];
        $msg = '' if !defined $msg;
        $timeout = 5 if !defined $timeout;
        $msg = ":$msg" if $msg =~ /\x20/;
        my $cmd = "QUIT $msg";
        $kernel->call($session => sl_high => $cmd);
        $kernel->delay('_quit_timeout', $timeout);
        $self->{_waiting} = 1;
    }
    elsif ($self->connected()) {
        $self->disconnect();
    }
    else {
        $self->_shutdown();
    }

    return;
}

sub _quit_timeout {
    my ($self) = $_[OBJECT];
    $self->disconnect();
    return;
}

sub _shutdown {
    my ($self) = @_;

    $self->_syndicator_destroy($self->{_shutdown});
    delete $self->{$_} for qw(socketfactory dcc wheelmap);
    $self->{resolver}->shutdown() if $self->{resolver} && $self->{mydns};
    return;
}

# Send a line of login-priority IRC output.  These are things which
# must go first.
sub sl_login {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    my $arg = join ' ', @_[ARG0 .. $#_];
    $kernel->yield(sl_prioritized => PRI_LOGIN, $arg );
    return;
}

# Send a line of high-priority IRC output.  Things like channel/user
# modes, kick messages, and whatever.
sub sl_high {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    my $arg = join ' ', @_[ARG0 .. $#_];
    $kernel->yield(sl_prioritized => PRI_HIGH, $arg );
    return;
}

# Send a line of normal-priority IRC output to the server.  PRIVMSG
# and other random chatter.  Uses sl() for compatibility with existing
# code.
sub sl {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    my $arg = join ' ', @_[ARG0 .. $#_];
    $kernel->yield(sl_prioritized => PRI_NORMAL, $arg );
    return;
}

# Prioritized sl().  This keeps the queue ordered by priority, low to
# high in the UNIX tradition.  It also throttles transmission
# following the hybrid ircd's algorithm, so you can't accidentally
# flood yourself off.  Thanks to Raistlin for explaining how ircd
# throttles messages.
sub sl_prioritized {
    my ($kernel, $self, $priority, @args) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if (my ($event) = $args[0] =~ /^(\w+)/ ) {
        # Let the plugin system process this
        return 1 if $self->send_user_event($event, \@args) == PCI_EAT_ALL;
    }
    else {
        warn "Unable to extract the event name from '$args[0]'\n";
    }

    my $msg = $args[0];
    my $now = time();
    $self->{send_time} = $now if $self->{send_time} < $now;

    # if we find a newline in the message, take that to be the end of it
    $msg =~ s/[\015\012].*//s;

    if (bytes::length($msg) > $self->{msg_length} - bytes::length($self->nick_name())) {
        $msg = bytes::substr($msg, 0, $self->{msg_length} - bytes::length($self->nick_name()));
    }

    if (!$self->{flood} && @{ $self->{send_queue} }) {
        my $i = @{ $self->{send_queue} };
        $i-- while ($i && $priority < $self->{send_queue}->[$i-1]->[MSG_PRI]);
        splice( @{ $self->{send_queue} }, $i, 0, [ $priority, $msg ] );
    }
    elsif ( !$self->{flood} && $self->{send_time} - $now >= 10
        || !defined $self->{socket} ) {
        push( @{$self->{send_queue}}, [ $priority, $msg ] );
        $kernel->delay( sl_delayed => $self->{send_time} - $now - 10 );
    }
    else {
        warn ">>> $msg\n" if $self->{debug};
        $self->send_event(irc_raw_out => $msg) if $self->{raw};
        $self->{send_time} += 2 + length($msg) / 120;
        $self->{socket}->put($msg);
    }

    return;
}

# Send delayed lines to the ircd.  We manage a virtual "send time"
# that progresses into the future based on hybrid ircd's rules every
# time a message is sent.  Once we find it ten or more seconds into
# the future, we wait for the realtime clock to catch up.
sub sl_delayed {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    return if !defined $self->{socket};

    my $now = time();
    $self->{send_time} = $now if $self->{send_time} < $now;

    while (@{ $self->{send_queue} } && ($self->{send_time} - $now < 10)) {
        my $arg = (shift @{$self->{send_queue}})->[MSG_TEXT];
        warn ">>> $arg\n" if $self->{debug};
        $self->send_event(irc_raw_out => $arg) if $self->{raw};
        $self->{send_time} += 2 + length($arg) / 120;
        $self->{socket}->put($arg);
    }

    if (@{ $self->{send_queue} }) {
        $kernel->delay( sl_delayed => $self->{send_time} - $now - 10 );
    }

    return;
}

# The handler for commands which have N arguments, separated by spaces.
sub spacesep {
    my ($kernel, $state) = @_[KERNEL, STATE];
    my $args = join ' ', @_[ARG0 .. $#_];
    my $pri = $_[OBJECT]->{IRC_CMDS}->{$state}->[CMD_PRI];

    $state = uc $state;
    $state .= " $args" if defined $args;
    $kernel->yield(sl_prioritized => $pri, $state );
    return;
}

# Set or query the current topic on a channel.
sub topic {
    my ($kernel, $chan, @args) = @_[KERNEL, ARG0..$#_];
    my $topic;
    $topic = join '', @args if @args;

    if (defined $topic) {
        $chan .= " :";
        $chan .= $topic if length $topic;
    }

    $kernel->yield(sl_prioritized => PRI_NORMAL, "TOPIC $chan");
    return;
}

# Asks the IRC server for some random information about particular nicks.
sub userhost {
    my ($kernel, @nicks) = @_[KERNEL, ARG0 .. $#_];

    if (!@nicks) {
        warn "The 'userhost' event requires at least one nickname\n";
        return;
    }

    # According to the RFC, you can only send 5 nicks at a time.
    while (@nicks) {
        $kernel->yield(
            'sl_prioritized',
            PRI_HIGH,
            'USERHOST ' . join(' ', splice(@nicks, 0, 5)),
        );
    }

    return;
}

# Non-event methods

sub server {
    my ($self) = @_;
    return $self->{server};
}

sub port {
    my ($self) = @_;
    return $self->{port};
}

sub server_name {
    my ($self) = @_;
    return $self->{INFO}{ServerName};
}

sub server_version {
    my ($self) = @_;
    return $self->{INFO}{ServerVersion};
}

sub localaddr {
    my ($self) = @_;
    return $self->{localaddr};
}

sub nick_name {
    my ($self) = @_;
    return $self->{INFO}{RealNick};
}

sub send_queue {
    my ($self) = @_;

    if (defined $self->{send_queue} && ref $self->{send_queue} eq 'ARRAY' ) {
        return scalar @{ $self->{send_queue} };
    }
    return;
}

sub raw_events {
    my ($self, $value) = @_;
    return $self->{raw} if !defined $value;
    $self->{raw} = $value;
    return;
}

sub connected {
    my ($self) = @_;
    return $self->{connected};
}

sub logged_in {
    my ($self) = @_;
    return 1 if $self->{INFO}{LoggedIn};
    return;
}

sub _compress_uplink {
    my ($self, $value) = @_;

    return if !$GOT_ZLIB;
    return $self->{uplink} if !defined $value;

    if ($value) {
        $self->{out_filter}->unshift( POE::Filter::Zlib::Stream->new() ) if !$self->{uplink};
        $self->{uplink} = 1;
    }
    else {
        $self->{out_filter}->shift() if $self->{uplink};
        $self->{uplink} = 0;
    }

    return $self->{uplink};
}

sub _compress_downlink {
    my ($self, $value) = @_;

    return if !$GOT_ZLIB;
    return $self->{downlink} if !defined $value;

    if ($value) {
        $self->{srv_filter}->unshift( POE::Filter::Zlib::Stream->new() ) if !$self->{downlink};
        $self->{downlink} = 1;
    }
    else {
        $self->{srv_filter}->shift() if $self->{uplink};
        $self->{downlink} = 0;
    }

    return $self->{downlink};
}

sub S_001 {
    my ($self, $irc) = splice @_, 0, 2;
    $self->{INFO}{ServerName} = ${ $_[0] };
    $self->{INFO}{LoggedIn}   = 1;
    return PCI_EAT_NONE;
}

sub S_004 {
    my ($self, $irc) = splice @_, 0, 2;
    my $args = ${ $_[2] };
    $self->{INFO}{ServerVersion} = $args->[1];
    return PCI_EAT_NONE;
}

sub S_error {
    my ($self, $irc) = splice @_, 0, 2;
    $self->{INFO}{LoggedIn} = 0;
    return PCI_EAT_NONE;
}

sub S_disconnected {
    my ($self, $irc) = splice @_, 0, 2;
    $self->{INFO}{LoggedIn} = 0;

    if ($self->{_waiting}) {
        $poe_kernel->delay('_quit_timeout');
        delete $self->{_waiting};
    }

    $self->_shutdown() if $self->{_shutdown};
    return PCI_EAT_NONE;
}

sub S_shutdown {
    my ($self, $irc) = splice @_, 0, 2;
    $self->{INFO}{LoggedIn} = 0;
    return PCI_EAT_NONE;
}

# Automatically replies to a PING from the server. Do not confuse this
# with CTCP PINGs, which are a wholly different animal that evolved
# much later on the technological timeline.
sub S_ping {
    my ($self, $irc) = splice @_, 0, 2;
    my $arg = ${ $_[0] };
    $irc->yield(sl_login => "PONG :$arg");
    return PCI_EAT_NONE;
}

# NICK messages for the purposes of determining our current nickname
sub S_nick {
    my ($self, $irc) = splice @_, 0, 2;
    my $nick = ( split /!/, ${ $_[0] } )[0];
    my $new = ${ $_[1] };
    $self->{INFO}{RealNick} = $new if ( $nick eq $self->{INFO}{RealNick} );
    return PCI_EAT_NONE;
}

# tell POE::Filter::IRC::Compat to handle IDENTIFY-MSG
sub S_290 {
    my ($self, $irc) = splice @_, 0, 2;
    my $text = ${ $_[1] };
    $self->{ircd_compat}->identifymsg(1) if $text eq 'IDENTIFY-MSG';
    return PCI_EAT_NONE;
}

sub S_cap {
    my ($self, $irc) = splice @_, 0, 2;
    my $cmd = ${ $_[0] };

    if ($cmd eq 'ACK') {
        my $list = ${ $_[1] } eq '*' ? ${ $_[2] } : ${ $_[1] };
        my @enabled = split / /, $list;

        if (grep { $_ =~ /^=?identify-msg$/ } @enabled) {
            $self->{ircd_compat}->identifymsg(1);
        }
        if (grep { $_ =~ /^-identify-msg$/ } @enabled) {
            $self->{ircd_compat}->identifymsg(0);
        }
    }
    return PCI_EAT_NONE;
}

sub S_isupport {
    my ($self, $irc) = splice @_, 0, 2;
    my $isupport = ${ $_[0] };
    $self->{ircd_compat}->chantypes( $isupport->isupport('CHANTYPES') || [ '#', '&' ] );
    $irc->yield(sl_login => 'CAPAB IDENTIFY-MSG') if $isupport->isupport('CAPAB');
    $irc->yield(sl_login => 'PROTOCTL NAMESX') if $isupport->isupport('NAMESX');
    $irc->yield(sl_login => 'PROTOCTL UHNAMES') if $isupport->isupport('UHNAMES');
    return PCI_EAT_NONE;
}

# accesses the ISupport plugin
sub isupport {
    my ($self, @args) = @_;
    return $self->{isupport}->isupport(@args);
}

sub isupport_dump_keys {
    return $_[0]->{isupport}->isupport_dump_keys();
}

sub resolver {
    return $_[0]->{resolver};
}

sub _ip_get_version {
    my ($ip) = @_;
    return if !defined $ip;

    # If the address does not contain any ':', maybe it's IPv4
    return 4 if $ip !~ /:/ && _ip_is_ipv4($ip);

    # Is it IPv6 ?
    return 6 if _ip_is_ipv6($ip);

    return;
}

sub _ip_is_ipv4 {
    my ($ip) = @_;
    return if !defined $ip;

    # Check for invalid chars
    return if $ip !~ /^[\d\.]+$/;
    return if $ip =~ /^\./;
    return if $ip =~ /\.$/;

    # Single Numbers are considered to be IPv4
    return 1 if $ip =~ /^(\d+)$/ && $1 < 256;

    # Count quads
    my $n = ($ip =~ tr/\./\./);

    # IPv4 must have from 1 to 4 quads
    return if $n <= 0 || $n > 4;

    # Check for empty quads
    return if $ip =~ /\.\./;

    for my $quad (split /\./, $ip) {
        # Check for invalid quads
        return if $quad < 0 || $quad >= 256;
    }
    return 1;
}

sub _ip_is_ipv6 {
    my ($ip) = @_;
    return if !defined $ip;

    # Count octets
    my $n = ($ip =~ tr/:/:/);
    return if ($n <= 0 || $n >= 8);

    # $k is a counter
    my $k;

    for my $octet (split /:/, $ip) {
        $k++;

        # Empty octet ?
        next if $octet eq '';

        # Normal v6 octet ?
        next if $octet =~ /^[a-f\d]{1,4}$/i;

        # Last octet - is it IPv4 ?
        if ($k == $n + 1) {
            next if (ip_is_ipv4($octet));
        }

        return;
    }

    # Does the IP address start with : ?
    return if $ip =~ m/^:[^:]/;

    # Does the IP address finish with : ?
    return if $ip =~ m/[^:]:$/;

    # Does the IP address have more than one '::' pattern ?
    return if $ip =~ s/:(?=:)//g > 1;

    return 1;
}

1;

=encoding utf8

=head1 NAME

POE::Component::IRC - A fully event-driven IRC client module

=head1 SYNOPSIS

 # A simple Rot13 'encryption' bot

 use strict;
 use warnings;
 use POE qw(Component::IRC);

 my $nickname = 'Flibble' . $$;
 my $ircname  = 'Flibble the Sailor Bot';
 my $server   = 'irc.perl.org';

 my @channels = ('#Blah', '#Foo', '#Bar');

 # We create a new PoCo-IRC object
 my $irc = POE::Component::IRC->spawn(
    nick => $nickname,
    ircname => $ircname,
    server  => $server,
 ) or die "Oh noooo! $!";

 POE::Session->create(
     package_states => [
         main => [ qw(_default _start irc_001 irc_public) ],
     ],
     heap => { irc => $irc },
 );

 $poe_kernel->run();

 sub _start {
     my $heap = $_[HEAP];

     # retrieve our component's object from the heap where we stashed it
     my $irc = $heap->{irc};

     $irc->yield( register => 'all' );
     $irc->yield( connect => { } );
     return;
 }

 sub irc_001 {
     my $sender = $_[SENDER];

     # Since this is an irc_* event, we can get the component's object by
     # accessing the heap of the sender. Then we register and connect to the
     # specified server.
     my $irc = $sender->get_heap();

     print "Connected to ", $irc->server_name(), "\n";

     # we join our channels
     $irc->yield( join => $_ ) for @channels;
     return;
 }

 sub irc_public {
     my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
     my $nick = ( split /!/, $who )[0];
     my $channel = $where->[0];

     if ( my ($rot13) = $what =~ /^rot13 (.+)/ ) {
         $rot13 =~ tr[a-zA-Z][n-za-mN-ZA-M];
         $irc->yield( privmsg => $channel => "$nick: $rot13" );
     }
     return;
 }

 # We registered for all events, this will produce some debug info.
 sub _default {
     my ($event, $args) = @_[ARG0 .. $#_];
     my @output = ( "$event: " );

     for my $arg (@$args) {
         if ( ref $arg eq 'ARRAY' ) {
             push( @output, '[' . join(', ', @$arg ) . ']' );
         }
         else {
             push ( @output, "'$arg'" );
         }
     }
     print join ' ', @output, "\n";
     return;
 }

=head1 DESCRIPTION

POE::Component::IRC is a POE component (who'd have guessed?) which
acts as an easily controllable IRC client for your other POE
components and sessions. You create an IRC component and tell it what
events your session cares about and where to connect to, and it sends
back interesting IRC events when they happen. You make the client do
things by sending it events. That's all there is to it. Cool, no?

[Note that using this module requires some familiarity with the
details of the IRC protocol. I'd advise you to read up on the gory
details of RFC 1459 (L<http://www.faqs.org/rfcs/rfc1459.html>) before you
get started. Keep the list of server numeric codes handy while you
program. Needless to say, you'll also need a good working knowledge of
POE, or this document will be of very little use to you.]

The POE::Component::IRC distribution has a F<docs/> folder with a collection of
salient documentation including the pertinent RFCs.

POE::Component::IRC consists of a POE::Session that manages the IRC connection
and dispatches C<irc_> prefixed events to interested sessions and
an object that can be used to access additional information using methods.

Sessions register their interest in receiving C<irc_> events by sending
L<C<register>|/register> to the component. One would usually do this in
your C<_start> handler. Your session will continue to receive events until
you L<C<unregister>|/unregister>. The component will continue to stay
around until you tell it not to with L<C<shutdown>|/shutdown>.

The L<SYNOPSIS|/SYNOPSIS> demonstrates a fairly basic bot.

See L<POE::Component::IRC::Cookbook|POE::Component::IRC::Cookbook> for more
examples.

=head2 Useful subclasses

Included with POE::Component::IRC are a number of useful subclasses. As they
are subclasses they support all the methods, etc. documented here and have
additional methods and quirks which are documented separately:

=over 4

=item * L<POE::Component::IRC::State|POE::Component::IRC::State>

POE::Component::IRC::State provides all the functionality of POE::Component::IRC
but also tracks IRC state entities such as nicks and channels.

=item * L<POE::Component::IRC::Qnet|POE::Component::IRC::Qnet>

POE::Component::IRC::Qnet is POE::Component::IRC tweaked for use on Quakenet IRC
network.

=item * L<POE::Component::IRC::Qnet::State|POE::Component::IRC::Qnet::State>

POE::Component::IRC::Qnet::State is a tweaked version of POE::Component::IRC::State
for use on the Quakenet IRC network.

=back

=head2 The Plugin system

As of 3.7, PoCo-IRC sports a plugin system. The documentation for it can be
read by looking at L<POE::Component::IRC::Plugin|POE::Component::IRC::Plugin>.
That is not a subclass, just a placeholder for documentation!

A number of useful plugins have made their way into the core distribution:

=over 4

=item * L<POE::Component::IRC::Plugin::DCC|POE::Component::IRC::Plugin::DCC>

Provides DCC support. Loaded by default.

=item * L<POE::Component::IRC::Plugin::AutoJoin|POE::Component::IRC::Plugin::AutoJoin>

Keeps you on your favorite channels throughout reconnects and even kicks.

=item * L<POE::Component::IRC::Plugin::Connector|POE::Component::IRC::Plugin::Connector>

Glues an irc bot to an IRC network, i.e. deals with maintaining ircd connections.

=item * L<POE::Component::IRC::Plugin::BotTraffic|POE::Component::IRC::Plugin::BotTraffic>

Under normal circumstances irc bots do not normal the msgs and public msgs that
they generate themselves. This plugin enables you to handle those events.

=item * L<POE::Component::IRC::Plugin::BotAddressed|POE::Component::IRC::Plugin::BotAddressed>

Generates C<irc_bot_addressed> / C<irc_bot_mentioned> / C<irc_bot_mentioned_action>
events whenever your bot's name comes up in channel discussion.

=item * L<POE::Component::IRC::Plugin::BotCommand|POE::Component::IRC::Plugin::BotCommand>

Provides an easy way to handle commands issued to your bot.

=item * L<POE::Component::IRC::Plugin::Console|POE::Component::IRC::Plugin::Console>

See inside the component. See what events are being sent. Generate irc commands
manually. A TCP based console.

=item * L<POE::Component::IRC::Plugin::FollowTail|POE::Component::IRC::Plugin::FollowTail>

Follow the tail of an ever-growing file.

=item * L<POE::Component::IRC::Plugin::Logger|POE::Component::IRC::Plugin::Logger>

Log public and private messages to disk.

=item * L<POE::Component::IRC::Plugin::NickServID|POE::Component::IRC::Plugin::NickServID>

Identify with NickServ when needed.

=item * L<POE::Component::IRC::Plugin::Proxy|POE::Component::IRC::Plugin::Proxy>

A lightweight IRC proxy/bouncer.

=item * L<POE::Component::IRC::Plugin::CTCP|POE::Component::IRC::Plugin::CTCP>

Automagically generates replies to ctcp version, time and userinfo queries.

=item * L<POE::Component::IRC::Plugin::PlugMan|POE::Component::IRC::Plugin::PlugMan>

An experimental Plugin Manager plugin.

=item * L<POE::Component::IRC::Plugin::NickReclaim|POE::Component::IRC::Plugin::NickReclaim>

Automagically deals with your nickname being in use and reclaiming it.

=item * L<POE::Component::IRC::Plugin::CycleEmpty|POE::Component::IRC::Plugin::CycleEmpty>

Cycles (parts and rejoins) channels if they become empty and opless, in order
to gain ops.

=back

=head1 CONSTRUCTORS

Both constructors return an object. The object is also available within 'irc_'
event handlers by using C<< $_[SENDER]->get_heap() >>. See also
L<C<register>|/register> and L<C<irc_registered>|/irc_registered>.

=head2 C<spawn>

Takes a number of arguments, all of which are optional. All the options
below may be supplied to the L<C<connect>|/connect> input event as well,
except for B<'alias'>, B<'options'>, B<'NoDNS'>, B<'debug'>, and
B<'plugin_debug'>.

=over 4

=item * B<'alias'>, a name (kernel alias) that this instance will be known
by;

=item * B<'options'>, a hashref containing L<POE::Session|POE::Session>
options;

=item * B<'Server'>, the server name;

=item * B<'Port'>, the remote port number;

=item * B<'Password'>, an optional password for restricted servers;

=item * B<'Nick'>, your client's IRC nickname;

=item * B<'Username'>, your client's username;

=item * B<'Ircname'>, some cute comment or something.

=item * B<'Bitmode'>, an integer representing your initial user modes set
in the USER command. See RFC 2812. If you do not set this, C<8> (+i) will
be used.

=item *  B<'UseSSL'>, set to some true value if you want to connect using
SSL.

=item *  B<'SSLCert'>, set to a SSL Certificate(PAM encoded) to connect using a client cert

=item *  B<'SSLKey'>, set to a SSL Key(PAM encoded) to connect using a client cert

=item *  B<'SSLCtx'>, set to a SSL Context to configure the SSL Connection

The B<'SSLCert'> and B<'SSLKey'> both need to be specified. The B<'SSLCtx'> takes precedence specified.

=item * B<'Raw'>, set to some true value to enable the component to send
L<C<irc_raw>|/irc_raw> and L<C<irc_raw_out>|/irc_raw_out> events.

=item * B<'LocalAddr'>, which local IP address on a multihomed box to
connect as;

=item * B<'LocalPort'>, the local TCP port to open your socket on;

=item * B<'NoDNS'>, set this to 1 to disable DNS lookups using
PoCo-Client-DNS. (See note below).

=item * B<'Flood'>, when true, it disables the component's flood
protection algorithms, allowing it to send messages to an IRC server at
full speed. Disconnects and k-lines are some common side effects of
flooding IRC servers, so care should be used when enabling this option.
Default is false.

Two new attributes are B<'Proxy'> and B<'ProxyPort'> for sending your
=item * B<'Proxy'>, IP address or server name of a proxy server to use.

=item * B<'ProxyPort'>, which tcp port on the proxy to connect to.

=item * B<'NATAddr'>, what other clients see as your IP address.

=item * B<'DCCPorts'>, an arrayref containing tcp ports that can be used
for DCC sends.

=item * B<'Resolver'>, provide a L<POE::Component::Client::DNS|POE::Component::Client::DNS> object for the component to use.

=item * B<'msg_length'>, the maximum length of IRC messages, in bytes.
Default is 450. The IRC component shortens all messages longer than this
value minus the length of your current nickname. IRC only allows raw
protocol lines messages that are 512 bytes or shorter, including the
trailing "\r\n". This is most relevant to long PRIVMSGs. The IRC component
can't be sure how long your user@host mask will be every time you send a
message, considering that most networks mangle the 'user' part and some
even replace the whole string (think FreeNode cloaks). If you have an
unusually long user@host mask you might want to decrease this value if
you're prone to sending long messages. Conversely, if you have an
unusually short one, you can increase this value if you want to be able to
send as long a message as possible. Be careful though, increase it too
much and the IRC server might disconnect you with a "Request too long"
message when you try to send a message that's too long.

=item * B<'debug'>, if set to a true value causes the IRC component to
print every message sent to and from the server, as well as print some
warnings when it receives malformed messages. This option will be enabled
if the C<POCOIRC_DEBUG> environment variable is set to a true value.

=item * B<'plugin_debug'>, set to some true value to print plugin debug
info, default 0. Plugins are processed inside an eval. When you enable
this option, you will be notified when (and why) a plugin raises an
exception. This option will be enabled if the C<POCOIRC_DEBUG> environment
variable is set to a true value.

=item * B<'socks_proxy'>, specify a SOCKS4/SOCKS4a proxy to use.

=item * B<'socks_port'>, the SOCKS port to use, defaults to 1080 if not
specified.

=item * B<'socks_id'>, specify a SOCKS user_id. Default is none.

=item * B<'useipv6'>, enable the use of IPv6 for connections.

=item * B<'webirc'>, enable the use of WEBIRC to spoof host/IP.
You must have a WEBIRC password set up on the IRC server/network (so will
only work for servers which trust you to spoof the IP & host the connection
is from) - value should be a hashref containing keys C<pass>, C<user>,
C<host> and C<ip>.

=back

C<spawn> will supply reasonable defaults for any of these attributes
which are missing, so don't feel obliged to write them all out.

If the component finds that L<POE::Component::Client::DNS|POE::Component::Client::DNS>
is installed it will use that to resolve the server name passed. Disable
this behaviour if you like, by passing: C<< NoDNS => 1 >>.

IRC traffic through a proxy server. B<'Proxy'>'s value should be the IP
address or server name of the proxy. B<'ProxyPort'>'s value should be the
port on the proxy to connect to. L<C<connect>|/connect> will default
to using the I<actual> IRC server's port if you provide a proxy but omit
the proxy's port. These are for HTTP Proxies. See B<'socks_proxy'> for
SOCKS4 and SOCKS4a support.

For those people who run bots behind firewalls and/or Network Address
Translation there are two additional attributes for DCC. B<'DCCPorts'>,
is an arrayref of ports to use when initiating DCC connections.
B<'NATAddr'>, is the NAT'ed IP address that your bot is hidden behind,
this is sent whenever you do DCC.

SSL support requires L<POE::Component::SSLify|POE::Component::SSLify>, as
well as an IRC server that supports SSL connections. If you're missing
POE::Component::SSLify, specifying B<'UseSSL'> will do nothing. The
default is to not try to use SSL.

B<'Resolver'>, requires a L<POE::Component::Client::DNS|POE::Component::Client::DNS>
object. Useful when spawning multiple poco-irc sessions, saves the
overhead of multiple dns sessions.

B<'NoDNS'> has different results depending on whether it is set with
L<C<spawn>|/spawn> or L<C<connect>|/connect>. Setting it with
C<spawn>, disables the creation of the POE::Component::Client::DNS
completely. Setting it with L<C<connect>|/connect> on the other hand
allows the PoCo-Client-DNS session to be spawned, but will disable
any dns lookups using it.

SOCKS4 proxy support is provided by B<'socks_proxy'>, B<'socks_port'> and
B<'socks_id'> parameters. If something goes wrong with the SOCKS connection
you should get a warning on STDERR. This is fairly experimental currently.

IPv6 support is available for connecting to IPv6 enabled ircds (it won't
work for DCC though). To enable it, specify B<'useipv6'>. Perl >=5.14 or
L<Socket6|Socket6> (for older Perls) is required. If you that and
L<POE::Component::Client::DNS|POE::Component::Client::DNS> installed and
specify a hostname that resolves to an IPv6 address then IPv6 will be used.
If you specify an ipv6 B<'localaddr'> then IPv6 will be used.

=head2 C<new>

This method is deprecated. See the L<C<spawn>|/spawn> method instead.
The first argument should be a name (kernel alias) which this new
connection will be known by. Optionally takes more arguments (see
L<C<spawn>|/spawn> as name/value pairs. Returns a POE::Component::IRC
object. :)

B<Note:> Use of this method will generate a warning. There are currently no
plans to make it die() >;]

=head1 METHODS

=head2 Information

=head3 C<server>

Takes no arguments. Returns the server host we are currently connected to
(or trying to connect to).

=head3 C<port>

Takes no arguments. Returns the server port we are currently connected to
(or trying to connect to).

=head3 C<server_name>

Takes no arguments. Returns the name of the IRC server that the component
is currently connected to.

=head3 C<server_version>

Takes no arguments. Returns the IRC server version.

=head3 C<nick_name>

Takes no arguments. Returns a scalar containing the current nickname that the
bot is using.

=head3 C<localaddr>

Takes no arguments. Returns the IP address being used.

=head3 C<send_queue>

The component provides anti-flood throttling. This method takes no arguments
and returns a scalar representing the number of messages that are queued up
waiting for dispatch to the irc server.

=head3 C<logged_in>

Takes no arguments. Returns true or false depending on whether the IRC
component is logged into an IRC network.

=head3 C<connected>

Takes no arguments. Returns true or false depending on whether the component's
socket is currently connected.

=head3 C<disconnect>

Takes no arguments. Terminates the socket connection disgracefully >;o]

=head3 C<isupport>

Takes one argument, a server capability to query. Returns C<undef> on failure
or a value representing the applicable capability. A full list of capabilities
is available at L<http://www.irc.org/tech_docs/005.html>.

=head3 C<isupport_dump_keys>

Takes no arguments, returns a list of the available server capabilities keys,
which can be used with L<C<isupport>|/isupport>.

=head3 C<resolver>

Returns a reference to the L<POE::Component::Client::DNS|POE::Component::Client::DNS>
object that is internally created by the component.

=head2 Events

=head3 C<session_id>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/session_id>>

Takes no arguments. Returns the ID of the component's session. Ideal for posting
events to the component.

 $kernel->post($irc->session_id() => 'mode' => $channel => '+o' => $dude);

=head3 C<session_alias>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/session_alias>>

Takes no arguments. Returns the session alias that has been set through
L<C<spawn>|/spawn>'s B<'alias'> argument.

=head3 C<raw_events>

With no arguments, returns true or false depending on whether
L<C<irc_raw>|/irc_raw> and L<C<irc_raw_out>|/irc_raw_out> events are being generated
or not. Provide a true or false argument to enable or disable this feature
accordingly.

=head3 C<yield>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/yield>>

This method provides an alternative object based means of posting events to the
component. First argument is the event to post, following arguments are sent as
arguments to the resultant post.

 $irc->yield(mode => $channel => '+o' => $dude);

=head3 C<call>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/call>>

This method provides an alternative object based means of calling events to the
component. First argument is the event to call, following arguments are sent as
arguments to the resultant
call.

 $irc->call(mode => $channel => '+o' => $dude);

=head3 C<delay>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/delay>>

This method provides a way of posting delayed events to the component. The
first argument is an arrayref consisting of the delayed command to post and
any command arguments. The second argument is the time in seconds that one
wishes to delay the command being posted.

 my $alarm_id = $irc->delay( [ mode => $channel => '+o' => $dude ], 60 );

Returns an alarm ID that can be used with L<C<delay_remove>|/delay_remove>
to cancel the delayed event. This will be undefined if something went wrong.

=head3 C<delay_remove>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/delay_remove>>

This method removes a previously scheduled delayed event from the component.
Takes one argument, the C<alarm_id> that was returned by a
L<C<delay>|/delay> method call.

 my $arrayref = $irc->delay_remove( $alarm_id );

Returns an arrayref that was originally requested to be delayed.

=head3 C<send_event>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/send_event>>

Sends an event through the component's event handling system. These will get
processed by plugins then by registered sessions. First argument is the event
name, followed by any parameters for that event.

=head3 C<send_event_next>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/send_event_next>>

This sends an event right after the one that's currently being processed.
Useful if you want to generate some event which is directly related to
another event so you want them to appear together. This method can only be
called when POE::Component::IRC is processing an event, e.g. from one of your
event handlers. Takes the same arguments as L<C<send_event>|/send_event>.

=head3 C<send_event_now>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/send_event_now>>

This will send an event to be processed immediately. This means that if an
event is currently being processed and there are plugins or sessions which
will receive it after you do, then an event sent with C<send_event_now> will
be received by those plugins/sessions I<before> the current event. Takes the
same arguments as L<C<send_event>|/send_event>.

=head2 Plugins

=head3 C<pipeline>

I<Inherited from L<Object::Pluggable|Object::Pluggable/pipeline>>

Returns the L<Object::Pluggable::Pipeline|Object::Pluggable::Pipeline>
object.

=head3 C<plugin_add>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_add>>

Accepts two arguments:

 The alias for the plugin
 The actual plugin object
 Any number of extra arguments

The alias is there for the user to refer to it, as it is possible to have
multiple plugins of the same kind active in one Object::Pluggable object.

This method goes through the pipeline's C<push()> method, which will call
C<< $plugin->plugin_register($pluggable, @args) >>.

Returns the number of plugins now in the pipeline if plugin was initialized,
C<undef>/an empty list if not.

=head3 C<plugin_del>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_del>>

Accepts the following arguments:

 The alias for the plugin or the plugin object itself
 Any number of extra arguments

This method goes through the pipeline's C<remove()> method, which will call
C<< $plugin->plugin_unregister($pluggable, @args) >>.

Returns the plugin object if the plugin was removed, C<undef>/an empty list
if not.

=head3 C<plugin_get>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_get>>

Accepts the following arguments:

 The alias for the plugin

This method goes through the pipeline's C<get()> method.

Returns the plugin object if it was found, C<undef>/an empty list if not.

=head3 C<plugin_list>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_list>>

Takes no arguments.

Returns a hashref of plugin objects, keyed on alias, or an empty list if
there are no plugins loaded.

=head3 C<plugin_order>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_order>>

Takes no arguments.

Returns an arrayref of plugin objects, in the order which they are
encountered in the pipeline.

=head3 C<plugin_register>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_register>>

Accepts the following arguments:

 The plugin object
 The type of the hook (the hook types are specified with _pluggable_init()'s 'types')
 The event name[s] to watch

The event names can be as many as possible, or an arrayref. They correspond
to the prefixed events and naturally, arbitrary events too.

You do not need to supply events with the prefix in front of them, just the
names.

It is possible to register for all events by specifying 'all' as an event.

Returns 1 if everything checked out fine, C<undef>/an empty list if something
is seriously wrong.

=head3 C<plugin_unregister>

I<Inherited from L<Object::Pluggable|Object::Pluggable/plugin_unregister>>

Accepts the following arguments:

 The plugin object
 The type of the hook (the hook types are specified with _pluggable_init()'s 'types')
 The event name[s] to unwatch

The event names can be as many as possible, or an arrayref. They correspond
to the prefixed events and naturally, arbitrary events too.

You do not need to supply events with the prefix in front of them, just the
names.

It is possible to register for all events by specifying 'all' as an event.

Returns 1 if all the event name[s] was unregistered, undef if some was not
found.

=head1 INPUT EVENTS

How to talk to your new IRC component... here's the events we'll accept.
These are events that are posted to the component, either via
C<< $poe_kernel->post() >> or via the object method L<C<yield>|/yield>.

So the following would be functionally equivalent:

 sub irc_001 {
     my ($kernel,$sender) = @_[KERNEL,SENDER];
     my $irc = $sender->get_heap(); # obtain the poco's object

     $irc->yield( privmsg => 'foo' => 'Howdy!' );
     $kernel->post( $sender => privmsg => 'foo' => 'Howdy!' );
     $kernel->post( $irc->session_id() => privmsg => 'foo' => 'Howdy!' );
     $kernel->post( $irc->session_alias() => privmsg => 'foo' => 'Howdy!' );

     return;
 }

=head2 Important Commands

=head3 C<register>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/register>>

Takes N arguments: a list of event names that your session wants to
listen for, minus the C<irc_> prefix. So, for instance, if you just
want a bot that keeps track of which people are on a channel, you'll
need to listen for JOINs, PARTs, QUITs, and KICKs to people on the
channel you're in. You'd tell POE::Component::IRC that you want those
events by saying this:

 $kernel->post('my client', 'register', qw(join part quit kick));

Then, whenever people enter or leave a channel your bot is on (forcibly
or not), your session will receive events with names like
L<C<irc_join>|/irc_join>, L<C<irc_kick>|/irc_kick>, etc.,
which you can use to update a list of people on the channel.

Registering for B<'all'> will cause it to send all IRC-related events to
you; this is the easiest way to handle it. See the test script for an
example.

Registering will generate an L<C<irc_registered>|/irc_registered>
event that your session can trap. C<ARG0> is the components object. Useful
if you want to bolt PoCo-IRC's new features such as Plugins into a bot
coded to the older deprecated API. If you are using the new API, ignore this :)

Registering with multiple component sessions can be tricky, especially if
one wants to marry up sessions/objects, etc. Check the L<SIGNALS|/SIGNALS>
section for an alternative method of registering with multiple poco-ircs.

Starting with version 4.96, if you spawn the component from inside another POE
session, the component will automatically register that session as wanting
B<'all'> irc events. That session will receive an
L<C<irc_registered>|/irc_registered> event indicating that the component
is up and ready to go.

=head3 C<unregister>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/unregister>>

Takes N arguments: a list of event names which you I<don't> want to
receive. If you've previously done a L<C<register>|/register>
for a particular event which you no longer care about, this event will
tell the IRC connection to stop sending them to you. (If you haven't, it just
ignores you. No big deal.)

If you have registered with 'all', attempting to unregister individual
events such as 'mode', etc. will not work. This is a 'feature'.

=head3 C<connect>

Takes one argument: a hash reference of attributes for the new connection,
see L<C<spawn>|/spawn> for details. This event tells the IRC client to
connect to a new/different server. If it has a connection already open, it'll
close it gracefully before reconnecting.

=head3 C<ctcp> and C<ctcpreply>

Sends a CTCP query or response to the nick(s) or channel(s) which you
specify. Takes 2 arguments: the nick or channel to send a message to
(use an array reference here to specify multiple recipients), and the
plain text of the message to send (the CTCP quoting will be handled
for you). The "/me" command in popular IRC clients is actually a CTCP action.

 # Doing a /me
 $irc->yield(ctcp => $channel => 'ACTION dances.');

=head3 C<join>

Tells your IRC client to join a single channel of your choice. Takes
at least one arg: the channel name (required) and the channel key
(optional, for password-protected channels).

=head3 C<kick>

Tell the IRC server to forcibly evict a user from a particular
channel. Takes at least 2 arguments: a channel name, the nick of the
user to boot, and an optional witty message to show them as they sail
out the door.

=head3 C<remove>

Tell the IRC server to forcibly evict a user from a particular
channel. Takes at least 2 arguments: a channel name, the nick of the
user to boot, and an optional witty message to show them as they sail
out the door. Similar to KICK but does an enforced PART instead. Not
supported by all servers.

=head3 C<mode>

Request a mode change on a particular channel or user. Takes at least
one argument: the mode changes to effect, as a single string (e.g.
"#mychan +sm-p+o"), and any number of optional operands to the mode changes
(nicks, hostmasks, channel keys, whatever.) Or just pass them all as one
big string and it'll still work, whatever. I regret that I haven't the
patience now to write a detailed explanation, but serious IRC users know
the details anyhow.

=head3 C<nick>

Allows you to change your nickname. Takes exactly one argument: the
new username that you'd like to be known as.

=head3 C<nickserv>

Talks to NickServ, on networks which have it. Takes any number of
arguments.

=head3 C<notice>

Sends a NOTICE message to the nick(s) or channel(s) which you
specify. Takes 2 arguments: the nick or channel to send a notice to
(use an array reference here to specify multiple recipients), and the
text of the notice to send.

=head3 C<part>

Tell your IRC client to leave the channels which you pass to it. Takes
any number of arguments: channel names to depart from. If the last argument
doesn't begin with a channel name identifier or contains a space character,
it will be treated as a PART message and dealt with accordingly.

=head3 C<privmsg>

Sends a public or private message to the nick(s) or channel(s) which
you specify. Takes 2 arguments: the nick or channel to send a message
to (use an array reference here to specify multiple recipients), and
the text of the message to send.

Have a look at the constants in L<IRC::Utils|IRC::Utils> if you would
like to use formatting and color codes in your messages.

 $irc->yield('primvsg', '#mychannel', 'Hello there');

 # same, but with a green Hello
 use IRC::Utils qw(GREEN NORMAL);
 $irc->yield('primvsg', '#mychannel', GREEN.'Hello'.NORMAL.' there');

=head3 C<quit>

Tells the IRC server to disconnect you. Takes one optional argument:
some clever, witty string that other users in your channels will see
as you leave. You can expect to get an
L<C<irc_disconnected>|/irc_disconnected> event shortly after sending this.

=head3 C<shutdown>

By default, POE::Component::IRC sessions never go away. Even after
they're disconnected, they're still sitting around in the background,
waiting for you to call L<C<connect>|/connect> on them again to
reconnect. (Whether this behavior is the Right Thing is doubtful, but I
don't want to break backwards compatibility at this point.) You can send
the IRC session a C<shutdown> event manually to make it delete itself.

If you are logged into an IRC server, C<shutdown> first will send a quit
message and wait to be disconnected. It will wait for up to 5 seconds before
forcibly disconnecting from the IRC server. If you provide an argument, that
will be used as the QUIT message. If you provide two arguments, the second
one will be used as the timeout (in seconds).

Terminating multiple components can be tricky. Check the L<SIGNALS|/SIGNALS>
section for a method of shutting down multiple poco-ircs.

=head3 C<topic>

Retrieves or sets the topic for particular channel. If called with just
the channel name as an argument, it will ask the server to return the
current topic. If called with the channel name and a string, it will
set the channel topic to that string. Supply an empty string to unset a
channel topic.

=head3 C<debug>

Takes one argument: 0 to turn debugging off or 1 to turn debugging on.
This flips the debugging flag in L<POE::Filter::IRCD|POE::Filter::IRCD>,
L<POE::Filter::IRC::Compat|POE::Filter::IRC::Compat>, and
POE::Component::IRC. This has the same effect as setting Debug in
L<C<spawn>|/spawn> or L<C<connect>|/connect>.

=head2 Not-So-Important Commands

=head3 C<admin>

Asks your server who your friendly neighborhood server administrators
are. If you prefer, you can pass it a server name to query, instead of
asking the server you're currently on.

=head3 C<away>

When sent with an argument (a message describig where you went), the
server will note that you're now away from your machine or otherwise
preoccupied, and pass your message along to anyone who tries to
communicate with you. When sent without arguments, it tells the server
that you're back and paying attention.

=head3 C<cap>

Used to query/enable/disable IRC protocol capabilities. Takes any number of
arguments.

=head3 C<dcc*>

See the L<DCC plugin|POE::Component::IRC::Plugin/COMMANDS> (loaded by default)
documentation for DCC-related commands.

=head3 C<info>

Basically the same as the L<C<version>|/version> command, except that the
server is permitted to return any information about itself that it thinks is
relevant. There's some nice, specific standards-writing for ya, eh?

=head3 C<invite>

Invites another user onto an invite-only channel. Takes 2 arguments:
the nick of the user you wish to admit, and the name of the channel to
invite them to.

=head3 C<ison>

Asks the IRC server which users out of a list of nicknames are
currently online. Takes any number of arguments: a list of nicknames
to query the IRC server about.

=head3 C<links>

Asks the server for a list of servers connected to the IRC
network. Takes two optional arguments, which I'm too lazy to document
here, so all you would-be linklooker writers should probably go dig up
the RFC.

=head3 C<list>

Asks the server for a list of visible channels and their topics. Takes
any number of optional arguments: names of channels to get topic
information for. If called without any channel names, it'll list every
visible channel on the IRC network. This is usually a really big list,
so don't do this often.

=head3 C<motd>

Request the server's "Message of the Day", a document which typically
contains stuff like the server's acceptable use policy and admin
contact email addresses, et cetera. Normally you'll automatically
receive this when you log into a server, but if you want it again,
here's how to do it. If you'd like to get the MOTD for a server other
than the one you're logged into, pass it the server's hostname as an
argument; otherwise, no arguments.

=head3 C<names>

Asks the server for a list of nicknames on particular channels. Takes
any number of arguments: names of channels to get lists of users
for. If called without any channel names, it'll tell you the nicks of
everyone on the IRC network. This is a really big list, so don't do
this much.

=head3 C<quote>

Sends a raw line of text to the server. Takes one argument: a string
of a raw IRC command to send to the server. It is more optimal to use
the events this module supplies instead of writing raw IRC commands
yourself.

=head3 C<stats>

Returns some information about a server. Kinda complicated and not
terribly commonly used, so look it up in the RFC if you're
curious. Takes as many arguments as you please.

=head3 C<time>

Asks the server what time it thinks it is, which it will return in a
human-readable form. Takes one optional argument: a server name to
query. If not supplied, defaults to current server.

=head3 C<trace>

If you pass a server name or nick along with this request, it asks the
server for the list of servers in between you and the thing you
mentioned. If sent with no arguments, it will show you all the servers
which are connected to your current server.

=head3 C<users>

Asks the server how many users are logged into it. Defaults to the
server you're currently logged into; however, you can pass a server
name as the first argument to query some other machine instead.

=head3 C<version>

Asks the server about the version of ircd that it's running. Takes one
optional argument: a server name to query. If not supplied, defaults
to current server.

=head3 C<who>

Lists the logged-on users matching a particular channel name, hostname,
nickname, or what-have-you. Takes one optional argument: a string for
it to search for. Wildcards are allowed; in the absence of this
argument, it will return everyone who's currently logged in (bad
move). Tack an "o" on the end if you want to list only IRCops, as per
the RFC.

=head3 C<whois>

Queries the IRC server for detailed information about a particular
user. Takes any number of arguments: nicknames or hostmasks to ask for
information about. As of version 3.2, you will receive an
L<C<irc_whois>|/irc_whois> event in addition to the usual numeric
responses. See below for details.

=head3 C<whowas>

Asks the server for information about nickname which is no longer
connected. Takes at least one argument: a nickname to look up (no
wildcards allowed), the optional maximum number of history entries to
return, and the optional server hostname to query. As of version 3.2,
you will receive an L<C<irc_whowas>|/irc_whowas> event in addition
to the usual numeric responses. See below for details.

=head3 C<ping> and C<pong>

Included for completeness sake. The component will deal with ponging to
pings automatically. Don't worry about it.

=head2 Purely Esoteric Commands

=head3 C<die>

Tells the IRC server you're connect to, to terminate. Only useful for
IRCops, thank goodness. Takes no arguments.

=head3 C<locops>

Opers-only command. This one sends a message to all currently
logged-on local-opers (+l). This option is specific to EFNet.

=head3 C<oper>

In the exceedingly unlikely event that you happen to be an IRC
operator, you can use this command to authenticate with your IRC
server. Takes 2 arguments: your username and your password.

=head3 C<operwall>

Opers-only command. This one sends a message to all currently
logged-on global opers. This option is specific to EFNet.

=head3 C<rehash>

Tells the IRC server you're connected to, to rehash its configuration
files. Only useful for IRCops. Takes no arguments.

=head3 C<restart>

Tells the IRC server you're connected to, to shut down and restart itself.
Only useful for IRCops, thank goodness. Takes no arguments.

=head3 C<sconnect>

Tells one IRC server (which you have operator status on) to connect to
another. This is actually the CONNECT command, but I already had an
event called L<C<connect>|/connect>, so too bad. Takes the args
you'd expect: a server to connect to, an optional port to connect on,
and an optional remote server to connect with, instead of the one you're
currently on.

=head3 C<squit>

Operator-only command used to disconnect server links. Takes two arguments,
the server to disconnect and a message explaining your action.

=head3 C<summon>

Don't even ask.

=head3 C<servlist>

Lists the currently connected services on the network that are visible to you.
Takes two optional arguments, a mask for matching service names against, and
a service type.

=head3 C<squery>

Sends a message to a service. Takes the same arguments as
L<C<privmsg>|/privmsg>.

=head3 C<userhost>

Asks the IRC server for information about particular nicknames. (The
RFC doesn't define exactly what this is supposed to return.) Takes any
number of arguments: the nicknames to look up.

=head3 C<wallops>

Another opers-only command. This one sends a message to all currently
logged-on opers (and +w users); sort of a mass PA system for the IRC
server administrators. Takes one argument: some clever, witty message
to send.

=head1 OUTPUT EVENTS

The events you will receive (or can ask to receive) from your running
IRC component. Note that all incoming event names your session will
receive are prefixed by C<irc_>, to inhibit event namespace pollution.

If you wish, you can ask the client to send you every event it
generates. Simply register for the event name "all". This is a lot
easier than writing a huge list of things you specifically want to
listen for.

FIXME: I'd really like to classify these somewhat ("basic", "oper", "ctcp",
"dcc", "raw" or some such), and I'd welcome suggestions for ways to make
this easier on the user, if you can think of some.

In your event handlers, C<$_[SENDER]> is the particular component session that
sent you the event. C<< $_[SENDER]->get_heap() >> will retrieve the component's
object. Useful if you want on-the-fly access to the object and its methods.

=head2 Important Events

=head3 C<irc_registered>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/syndicator_registered>>

Sent once to the requesting session on registration (see
L<C<register>|/register>). C<ARG0> is a reference tothe component's object.

=head3 C<irc_shutdown>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/syndicator_shutdown>>

Sent to all registered sessions when the component has been asked to
L<C<shutdown>|/shutdown>. C<ARG0> will be the session ID of the requesting
session.

=head3 C<irc_connected>

The IRC component will send an C<irc_connected> event as soon as it
establishes a connection to an IRC server, before attempting to log
in. C<ARG0> is the server name.

B<NOTE:> When you get an C<irc_connected> event, this doesn't mean you
can start sending commands to the server yet. Wait until you receive
an L<C<irc_001>|/All numeric events> event (the server welcome message)
before actually sending anything back to the server.

=head3 C<irc_ctcp>

C<irc_ctcp> events are generated upon receipt of CTCP messages, in addition to
the C<irc_ctcp_*> events mentioned below. They are identical in every way to
these, with one difference: instead of the * being in the method name, it
is prepended to the argument list. For example, if someone types C</ctcp
Flibble foo bar>, an C<irc_ctcp> event will be sent with B<'foo'> as C<ARG0>,
and the rest as given below.

It is not recommended that you register for both C<irc_ctcp> and C<irc_ctcp_*>
events, since they will both be fired and presumably cause duplication.

=head3 C<irc_ctcp_*>

C<irc_ctcp_whatever> events are generated upon receipt of CTCP messages.
For instance, receiving a CTCP PING request generates an C<irc_ctcp_ping>
event, CTCP ACTION (produced by typing "/me" in most IRC clients)
generates an C<irc_ctcp_action> event, blah blah, so on and so forth. C<ARG0>
is the nick!hostmask of the sender. C<ARG1> is the channel/recipient
name(s). C<ARG2> is the text of the CTCP message. On servers supporting the
IDENTIFY-MSG feature (e.g. FreeNode), CTCP ACTIONs will have C<ARG3>, which
will be C<1> if the sender has identified with NickServ, C<0> otherwise.

Note that DCCs are handled separately -- see the
L<DCC plugin|POE::Component::IRC::Plugin::DCC>.

=head3 C<irc_ctcpreply_*>

C<irc_ctcpreply_whatever> messages are just like C<irc_ctcp_whatever>
messages, described above, except that they're generated when a response
to one of your CTCP queries comes back. They have the same arguments and
such as C<irc_ctcp_*> events.

=head3 C<irc_disconnected>

The counterpart to L<C<irc_connected>|/irc_connected>, sent whenever
a socket connection to an IRC server closes down (whether intentionally or
unintentionally). C<ARG0> is the server name.

=head3 C<irc_error>

You get this whenever the server sends you an ERROR message. Expect
this to usually be accompanied by the sudden dropping of your
connection. C<ARG0> is the server's explanation of the error.

=head3 C<irc_join>

Sent whenever someone joins a channel that you're on. C<ARG0> is the
person's nick!hostmask. C<ARG1> is the channel name.

=head3 C<irc_invite>

Sent whenever someone offers you an invitation to another channel. C<ARG0>
is the person's nick!hostmask. C<ARG1> is the name of the channel they want
you to join.

=head3 C<irc_kick>

Sent whenever someone gets booted off a channel that you're on. C<ARG0>
is the kicker's nick!hostmask. C<ARG1> is the channel name. C<ARG2> is the
nick of the unfortunate kickee. C<ARG3> is the explanation string for the
kick.

=head3 C<irc_mode>

Sent whenever someone changes a channel mode in your presence, or when
you change your own user mode. C<ARG0> is the nick!hostmask of that
someone. C<ARG1> is the channel it affects (or your nick, if it's a user
mode change). C<ARG2> is the mode string (i.e., "+o-b"). The rest of the
args (C<ARG3 .. $#_>) are the operands to the mode string (nicks,
hostmasks, channel keys, whatever).

=head3 C<irc_msg>

Sent whenever you receive a PRIVMSG command that was addressed to you
privately. C<ARG0> is the nick!hostmask of the sender. C<ARG1> is an array
reference containing the nick(s) of the recipients. C<ARG2> is the text
of the message. On servers supporting the IDENTIFY-MSG feature (e.g.
FreeNode), there will be an additional argument, C<ARG3>, which will be
C<1> if the sender has identified with NickServ, C<0> otherwise.

=head3 C<irc_nick>

Sent whenever you, or someone around you, changes nicks. C<ARG0> is the
nick!hostmask of the changer. C<ARG1> is the new nick that they changed
to.

=head3 C<irc_notice>

Sent whenever you receive a NOTICE command. C<ARG0> is the nick!hostmask
of the sender. C<ARG1> is an array reference containing the nick(s) or
channel name(s) of the recipients. C<ARG2> is the text of the NOTICE
message.

=head3 C<irc_part>

Sent whenever someone leaves a channel that you're on. C<ARG0> is the
person's nick!hostmask. C<ARG1> is the channel name. C<ARG2> is the part
message.

=head3 C<irc_public>

Sent whenever you receive a PRIVMSG command that was sent to a channel.
C<ARG0> is the nick!hostmask of the sender. C<ARG1> is an array
reference containing the channel name(s) of the recipients. C<ARG2> is the
text of the message. On servers supporting the IDENTIFY-MSG feature (e.g.
FreeNode), there will be an additional argument, C<ARG3>, which will be
C<1> if the sender has identified with NickServ, C<0> otherwise.

=head3 C<irc_quit>

Sent whenever someone on a channel with you quits IRC (or gets
KILLed). C<ARG0> is the nick!hostmask of the person in question. C<ARG1> is
the clever, witty message they left behind on the way out.

=head3 C<irc_socketerr>

Sent when a connection couldn't be established to the IRC server. C<ARG0>
is probably some vague and/or misleading reason for what failed.

=head3 C<irc_topic>

Sent when a channel topic is set or unset. C<ARG0> is the nick!hostmask of the
sender. C<ARG1> is the channel affected. C<ARG2> will be either: a string if the
topic is being set; or a zero-length string (i.e. '') if the topic is being
unset. Note: replies to queries about what a channel topic *is*
(i.e. TOPIC #channel), are returned as numerics, not with this event.

=head3 C<irc_whois>

Sent in response to a WHOIS query. C<ARG0> is a hashref, with the following
keys:

=over 4

=item * B<'nick'>, the users nickname;

=item * B<'user'>, the users username;

=item * B<'host'>, their hostname;

=item * B<'real'>, their real name;

=item * B<'idle'>, their idle time in seconds;

=item * B<'signon'>, the epoch time they signed on (will be undef if ircd
does not support this);

=item * B<'channels'>, an arrayref listing visible channels they are on,
the channel is prefixed with '@','+','%' depending on whether they have
+o +v or +h;

=item * B<'server'>, their server (might not be useful on some networks);

=item * B<'oper'>, whether they are an IRCop, contains the IRC operator
string if they are, undef if they aren't.

=item * B<'actually'>, some ircds report the user's actual ip address,
that'll be here;

=item * B<'identified'>. if the user has identified with NICKSERV
(ircu, seven, Plexus)

=item * B<'modes'>, a string describing the user's modes (Rizon)

=back

=head3 C<irc_whowas>

Similar to the above, except some keys will be missing.

=head3 C<irc_raw>

Enabled by passing C<< Raw => 1 >> to L<C<spawn>|/spawn> or
L<C<connect>|/connect>, or by calling L<C<raw_events>|/raw_events> with
a true argument. C<ARG0> is the raw IRC string received by the component from
the IRC server, before it has been mangled by filters and such like.

=head3 C<irc_raw_out>

Enabled by passing C<< Raw => 1 >> to L<C<spawn>|/spawn> or
L<C<connect>|/connect>, or by calling L<C<raw_events>|/raw_events> with
a true argument. C<ARG0> is the raw IRC string sent by the component to the
the IRC server.

=head3 C<irc_isupport>

Emitted by the first event after an L<C<irc_005>|/All numeric events>, to
indicate that isupport information has been gathered. C<ARG0> is the
L<POE::Component::IRC::Plugin::ISupport|POE::Component::IRC::Plugin::ISupport>
object.

=head3 C<irc_socks_failed>

Emitted whenever we fail to connect successfully to a SOCKS server or the
SOCKS server is not actually a SOCKS server. C<ARG0> will be some vague reason
as to what went wrong. Hopefully.

=head3 C<irc_socks_rejected>

Emitted whenever a SOCKS connection is rejected by a SOCKS server. C<ARG0> is
the SOCKS code, C<ARG1> the SOCKS server address, C<ARG2> the SOCKS port and
C<ARG3> the SOCKS user id (if defined).

=head3 C<irc_plugin_add>

I<Inherited from L<Object::Pluggable|Object::Pluggable/_pluggable_event>>

Emitted whenever a new plugin is added to the pipeline. C<ARG0> is the
plugin alias. C<ARG1> is the plugin object.

=head3 C<irc_plugin_del>

I<Inherited from L<Object::Pluggable|Object::Pluggable/_pluggable_event>>

Emitted whenever a plugin is removed from the pipeline. C<ARG0> is the
plugin alias. C<ARG1> is the plugin object.

=head3 C<irc_plugin_error>

I<Inherited from L<Object::Pluggable|Object::Pluggable/_pluggable_event>>

Emitted when an error occurs while executing a plugin handler. C<ARG0> is
the error message. C<ARG1> is the plugin alias. C<ARG2> is the plugin object.

=head2 Somewhat Less Important Events

=head3 C<irc_cap>

A reply from the server regarding protocol capabilities. C<ARG0> is the
CAP subcommand (e.g. 'LS'). C<ARG1> is the result of the subcommand, unless
this is a multi-part reply, in which case C<ARG1> is '*' and C<ARG2> contains
the result.

=head3 C<irc_dcc_*>

See the L<DCC plugin|POE::Component::IRC::Plugin/OUTPUT> (loaded by default)
documentation for DCC-related events.

=head3 C<irc_ping>

An event sent whenever the server sends a PING query to the
client. (Don't confuse this with a CTCP PING, which is another beast
entirely. If unclear, read the RFC.) Note that POE::Component::IRC will
automatically take care of sending the PONG response back to the
server for you, although you can still register to catch the event for
informational purposes.

=head3 C<irc_snotice>

A weird, non-RFC-compliant message from an IRC server. Usually sent during
to you during an authentication phase right after you connect, while the
server does a hostname lookup or similar tasks. C<ARG0> is the text of the
server's message. C<ARG1> is the target, which could be B<'*'> or B<'AUTH'>
or whatever. Servers vary as to whether these notices include a server name
as the sender, or no sender at all. C<ARG1> is the sender, if any.

=head3 C<irc_delay_set>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/syndicator_delay_set>>

Emitted on a successful addition of a delayed event using the
L<C<delay>|/delay> method. C<ARG0> will be the alarm_id which can be used
later with L<C<delay_remove>|/delay_remove>. Subsequent parameters are
the arguments that were passed to L<C<delay>|/delay>.

=head3 C<irc_delay_removed>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/syndicator_delay_removed>>

Emitted when a delayed command is successfully removed. C<ARG0> will be the
alarm_id that was removed. Subsequent parameters are the arguments that were
passed to L<C<delay>|/delay>.

=head2 All numeric events

Most messages from IRC servers are identified only by three-digit
numeric codes with undescriptive constant names like RPL_UMODEIS and
ERR_NOTOPLEVEL. (Actually, the list of codes in the RFC is kind of
out-of-date... the list in the back of Net::IRC::Event.pm is more
complete, and different IRC networks have different and incompatible
lists. Ack!) As an example, say you wanted to handle event 376
(RPL_ENDOFMOTD, which signals the end of the MOTD message). You'd
register for '376', and listen for C<irc_376> events. Simple, no? C<ARG0>
is the name of the server which sent the message. C<ARG1> is the text of
the message. C<ARG2> is an array reference of the parsed message, so there
is no need to parse C<ARG1> yourself.

=head1 SIGNALS

The component will handle a number of custom signals that you may send using
L<POE::Kernel|POE::Kernel>'s C<signal> method.

=head2 C<POCOIRC_REGISTER>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/SYNDICATOR_REGISTER>>

Registering with multiple PoCo-IRC components has been a pita. Well, no more,
using the power of L<POE::Kernel|POE::Kernel> signals.

If the component receives a C<POCOIRC_REGISTER> signal it'll register the
requesting session and trigger an L<C<irc_registered>|/irc_registered>
event. From that event one can get all the information necessary such as the
poco-irc object and the SENDER session to do whatever one needs to build a
poco-irc dispatch table.

The way the signal handler in PoCo-IRC is written also supports sending the
C<POCOIRC_REGISTER> to multiple sessions simultaneously, by sending the signal
to the POE Kernel itself.

Pass the signal your session, session ID or alias, and the IRC events (as
specified to L<C<register>|/register>).

To register with multiple PoCo-IRCs one can do the following in your session's
_start handler:

 sub _start {
     my ($kernel, $session) = @_[KERNEL, SESSION];

     # Registering with multiple pocoircs for 'all' IRC events
     $kernel->signal($kernel, 'POCOIRC_REGISTER', $session->ID(), 'all');

     return:
 }

Each poco-irc will send your session an
L<C<irc_registered>|/irc_registered> event:

 sub irc_registered {
     my ($kernel, $sender, $heap, $irc_object) = @_[KERNEL, SENDER, HEAP, ARG0];

     # Get the poco-irc session ID
     my $sender_id = $sender->ID();

     # Or it's alias
     my $poco_alias = $irc_object->session_alias();

     # Store it in our heap maybe
     $heap->{irc_objects}->{ $sender_id } = $irc_object;

     # Make the poco connect
     $irc_object->yield(connect => { });

     return;
 }

=head2 C<POCOIRC_SHUTDOWN>

I<Inherited from L<POE::Component::Syndicator|POE::Component::Syndicator/SYNDICATOR_SHUTDOWN>>

Telling multiple poco-ircs to shutdown was a pita as well. The same principle as
with registering applies to shutdown too.

Send a C<POCOIRC_SHUTDOWN> to the POE Kernel to terminate all the active
poco-ircs simultaneously.

 $poe_kernel->signal($poe_kernel, 'POCOIRC_SHUTDOWN');

Any additional parameters passed to the signal will become your quit messages
on each IRC network.

=head1 ENCODING

This can be an issue. Take a look at L<IRC::Utils' section|IRC::Utils/ENCODING>
on it.

=head1 BUGS

A few have turned up in the past and they are sure to again. Please use
L<http://rt.cpan.org/> to report any. Alternatively, email the current
maintainer.

=head1 DEVELOPMENT

You can find the latest source on github:
L<http://github.com/bingos/poe-component-irc>

The project's developers usually hang out in the C<#poe> IRC channel on
irc.perl.org. Do drop us a line.

=head1 MAINTAINERS

Chris C<BinGOs> Williams <chris@bingosnet.co.uk>

Hinrik E<Ouml>rn SigurE<eth>sson <hinrik.sig@gmail.com>

=head1 AUTHOR

Dennis Taylor.

=head1 LICENCE

Copyright (c) Dennis Taylor, Chris Williams and Hinrik E<Ouml>rn SigurE<eth>sson

This module may be used, modified, and distributed under the same
terms as Perl itself. Please see the license that came with your Perl
distribution for details.

=head1 MAD PROPS

The maddest of mad props go out to Rocco "dngor" Caputo
<troc@netrus.net>, for inventing something as mind-bogglingly
cool as POE, and to Kevin "oznoid" Lenzo E<lt>lenzo@cs.cmu.eduE<gt>,
for being the attentive parent of our precocious little infobot on
#perl.

Further props to a few of the studly bughunters who made this module not
suck: Abys <abys@web1-2-3.com>, Addi <addi@umich.edu>, ResDev
<ben@reser.org>, and Roderick <roderick@argon.org>. Woohoo!

Kudos to Apocalypse, <apocal@cpan.org>, for the plugin system and to
Jeff 'japhy' Pinyan, <japhy@perlmonk.org>, for Pipeline.

Thanks to the merry band of POE pixies from #PoE @ irc.perl.org,
including ( but not limited to ), ketas, ct, dec, integral, webfox,
immute, perigrin, paulv, alias.

IP functions are shamelessly 'borrowed' from L<Net::IP|Net::IP> by Manuel
Valente

Check out the Changes file for further contributors.

=head1 SEE ALSO

RFC 1459 L<http://www.faqs.org/rfcs/rfc1459.html>

L<http://www.irchelp.org/>,

L<http://poe.perl.org/>,

L<http://www.infobot.org/>,

Some good examples reside in the POE cookbook which has a whole section
devoted to IRC programming L<http://poe.perl.org/?POE_Cookbook>.

The examples/ folder of this distribution.

=cut
