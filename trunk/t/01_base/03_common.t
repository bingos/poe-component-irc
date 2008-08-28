use strict;
use warnings;
use POE::Component::IRC::Common qw(:ALL);
use Test::More tests => 32;

is('SIMPLE', u_irc('simple'), 'Upper simple test');
is('simple', l_irc('SIMPLE'), 'Lower simple test');
is('C0MPL~[X]', u_irc('c0mpl^{x}'), 'Upper complex test');
is('c0mpl^{x}', l_irc('C0MPL~[X]'), 'Lower complex test');
is('C0MPL~[X]', u_irc('c0mpl~[x]', 'ascii'), 'Upper complex test ascii');
is('c0mpl^{x}', l_irc('C0MPL^{X}', 'ascii'), 'Lower complex test ascii');
is('C0MPL~[X]', u_irc('c0mpl~{x}', 'strict-rfc1459'), 'Upper complex test strict');
is('c0mpl^{x}', l_irc('C0MPL^[X]', 'strict-rfc1459'), 'Lower complex test strict');

my $hashref = parse_mode_line(qw(ov rita bob));
is($hashref->{modes}->[0], '+o', 'Parse mode test 1');
is($hashref->{args}->[0], 'rita', 'Parse mode test 2');
my $hashref2 = parse_mode_line(qw(-b +b!*@*));
is($hashref2->{modes}->[0], '-b', 'Parse mode test 3');
is($hashref2->{args}->[0], '+b!*@*', 'Parse mode test 4');
my $hashref3 = parse_mode_line(qw(+b -b!*@*));
is($hashref3->{modes}->[0], '+b', 'Parse mode test 5');
is($hashref3->{args}->[0], '-b!*@*', 'Parse mode test 6');

my $banmask = parse_ban_mask('stalin*');
my $match = 'stalin!joe@kremlin.ru';
my $no_match = 'BinGOs!foo@blah.com';
is($banmask, 'stalin*!*@*', 'Parse ban mask test');
ok(matches_mask($banmask, $match), 'Matches Mask test 1');
ok(!matches_mask($banmask, $no_match), 'Matches Mask test 2');
ok(%{ matches_mask_array([$banmask], [$match]) }, 'Matches Mask array test 1');
ok(!%{ matches_mask_array([$banmask], [$no_match] ) }, 'Matches Mask array test 2');

my $nick = parse_user('BinGOs!null@fubar.com');
my @args = parse_user('BinGOs!null@fubar.com');
is($nick, 'BinGOs', 'Parse User Test 1');
is($nick, $args[0], 'Parse User Test 2');
is($args[1], 'null', 'Parse User Test 3');
is($args[2], 'fubar.com', 'Parse User Test 4');

my $colored = "\x0304,05Hi, I am a color junkie\x03";
ok(has_color($colored), 'Has Color Test');
is(strip_color($colored), 'Hi, I am a color junkie', 'Strip Color Test');

my $bg_colored = "\x03,05Hi, observe my colored background\x03";
is(strip_color($bg_colored), 'Hi, observe my colored background', 'Strip bg color test');
my $fg_colored = "\x0305Hi, observe my colored foreground\x03";
is(strip_color($fg_colored), 'Hi, observe my colored foreground', 'Strip fg color test');

my $formatted = "This is \x02bold\x0f and this is \x1funderlined\x0f";
ok(has_formatting($formatted), 'Has Formatting Test');
my $stripped = strip_formatting($formatted);
is($stripped, 'This is bold and this is underlined', 'Strip Formatting Test');

is(irc_ip_get_version('100.0.0.1'), 4, 'IPv4');
is(irc_ip_get_version('2001:0db8:0000:0000:0000:0000:1428:57ab'), 6, 'IPv6');
ok(!irc_ip_get_version('blah'), 'Not an IP');
