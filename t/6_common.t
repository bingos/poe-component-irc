use Test::More tests => 8;
BEGIN { use_ok('POE::Component::IRC::Common', qw(:ALL)) }
ok( 'SIMPLE' eq u_irc( 'simple' ), "Upper simple test" );
ok( 'simple' eq l_irc( 'SIMPLE' ), "Lower simple test" );
ok( 'C0MPL~[X]' eq u_irc ( 'c0mpl^{x}' ), "Upper complex test" );
ok( 'c0mpl^{x}' eq l_irc ( 'C0MPL~[X]' ), "Lower complex test" );
my $hashref = parse_mode_line( qw(ov rita bob) );
ok( $hashref->{modes}->[0] eq '+o', "Parse mode test 1" );
ok( $hashref->{args}->[0] eq 'rita', "Parse mode test 2" );
my $banmask = parse_ban_mask( 'stalin*' );
ok( $banmask eq 'stalin*!*@*', "Parse ban mask test 1" );
