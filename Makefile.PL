# $Id: Makefile.PL,v 3.9 2005/04/14 19:23:16 chris Exp $

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $GOT_DNS;

BEGIN {
   $GOT_DNS = 0;
   eval {
	require POE::Component::Client::DNS;
	$GOT_DNS = 1;
   };
}

print <<NOTICE;

---------------------------------------------------------------
POE::Component::IRC now features an online test as part of the
testsuite. Whilst I have tried to make it as robust as I can
the last test may take up to 40 seconds or so to complete.
Please be patient while it does it's thing.
---------------------------------------------------------------

---------------------------------------------------------------
A lot of the tests make use of the loopback interface. If this
is firewalled then these tests will fail. 
---------------------------------------------------------------

NOTICE

_no_dns() unless $GOT_DNS;

WriteMakefile(
			  'NAME'	=> 'POE::Component::IRC',
			  'PREREQ_PM' => {
					  'warnings' => 0,
					  'POE'    => 0.3202,
					  'POE::Filter::IRCD' => 1.7,
					  'Carp'   => 0,
					  'Socket' => 0,
					  'POSIX' => 0,
							 },
			  'VERSION_FROM' => 'lib/POE/Component/IRC.pm', # finds $VERSION
			  'dist' => { 'COMPRESS' => 'gzip --best' },
			  'test' => { TESTS => 't/*.t t/*/*.t' },
			  'clean' => { FILES => "README.send" },
			 );

exit 0;

sub _no_dns {
  print <<NO_DNS;

---------------------------------------------------------------
Hmmm. POE::Component::Client::DNS isn't installed. It's use is
recommended but not necessary. Consider installing it. Thanks.
---------------------------------------------------------------

NO_DNS
  return;
}
