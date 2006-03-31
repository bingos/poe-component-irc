# $Id: Makefile.PL,v 3.9 2005/04/14 19:23:16 chris Exp $

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

print <<NOTICE;

---------------------------------------------------------------
POE::Component::IRC now features an online test as part of the
testsuite. Whilst I have tried to make it as robust as I can
the last test may take up to 40 seconds or so to complete.
Please be patient while it does it's thing.
---------------------------------------------------------------

NOTICE

WriteMakefile(
			  'NAME'	=> 'POE::Component::IRC',
			  'PREREQ_PM' => {
							  'POE'    => 0.3202,
							  'POE::Filter::IRCD' => 1.4,
							  'POE::Component::Client::DNS' => 0.9803,
							  'POE::Component::Client::Ident' => 0.7,
							  'Carp'   => 0,
							  'Socket' => 0,
							  'Date::Format' => 0,
							 },
			  'VERSION_FROM' => 'lib/POE/Component/IRC.pm', # finds $VERSION
			  'dist' => { 'COMPRESS' => 'gzip --best' },
			  'test' => { TESTS => 't/*.t t/*/*.t' },
			 );

