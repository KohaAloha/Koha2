#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 126;
BEGIN {
	use FindBin;
	use lib $FindBin::Bin;
	use override_context_prefs;
	use_ok('C4::Dates', qw(format_date format_date_in_iso));
}

sub describe ($$) {
	my $front = sprintf("%-25s", shift);
	my $tail = shift || 'FAILED';
	return  "$front : $tail";
}

my %thash = (
	  iso  => ['2001-01-01','1989-09-21','1952-01-00'],
	metric => ["01-01-2001",'21-09-1989','00-01-1952'],
	   us  => ["01-01-2001",'09-21-1989','01-00-1952'],
	  sql  => ['20010101    010101',
	  		   '19890921    143907',
	  		   '19520100    000000'     ],
);

my ($date, $format, $today, $today0, $val, $re, $syspref);
my @formats = sort keys %thash;
diag "\n Testing Legacy Functions: format_date and format_date_in_iso";
ok($syspref = C4::Dates->new->format(),         "Your system preference is: $syspref");
print "\n";
foreach (@{$thash{'iso'}}) {
	ok($val = format_date($_),                  "format_date('$_'): $val"            );
}
foreach (@{$thash{$syspref}}) {
	ok($val = format_date_in_iso($_),           "format_date_in_iso('$_'): $val"     );
}
ok($today0 = C4::Dates->today(),                "(default) CLASS ->today : $today0" );
diag "\nTesting " . scalar(@formats) . " formats.\nTesting no input (defaults):\n";
print "\n";
foreach (@formats) {
	my $pre = sprintf '(%-6s)', $_;
	ok($date = C4::Dates->new(),                "$pre Date Creation   : new()");
	ok($_ eq ($format = $date->format($_)),     "$pre format($_)      : " . ($format|| 'FAILED') );
	ok($format = $date->visual(),  				"$pre visual()        : " . ($format|| 'FAILED') );
	ok($today  = $date->output(),               "$pre output()        : " . ($today || 'FAILED') );
	ok($today  = $date->today(),                "$pre object->today   : " . ($today || 'FAILED') );
	print "\n";
}

diag "\nTesting with valid inputs:\n";
foreach $format (@formats) {
	my $pre = sprintf '(%-6s)', $format;
  foreach my $testval (@{$thash{ $format }}) {
	ok($date = C4::Dates->new($testval,$format),         "$pre Date Creation   : new('$testval','$format')");
	ok($re   = $date->regexp,                            "$pre has regexp()" );
	ok($val  = $date->output(),                 describe("$pre output()", $val) );
	foreach (grep {!/$format/} @formats) {
		ok($today = $date->output($_),          describe(sprintf("$pre output(%8s)","'$_'"), $today) );
	}
	ok($today  = $date->today(),                describe("$pre object->today", $today) );
	# ok($today == ($today = C4::Dates->today()), "$pre CLASS ->today   : $today" );
	ok($val  = $date->output(),                 describe("$pre output()", $val) );
	# ok($format eq ($format = $date->format()),  "$pre format()        : $format" );
	print "\n";
  }
}

diag "\nTesting object independence from class\n";
my $in1 = '12/25/1952';	# us
my $in2 = '13/01/2001'; # metric
my $d1 = C4::Dates->new($in1, 'us');
my $d2 = C4::Dates->new($in2, 'metric');
my $out1 = $d1->output('iso');
my $out2 = $d2->output('iso');
ok($out1 ne $out2,                             "subsequent constructors get different dataspace ($out1 != $out2)");
diag "done.\n";
