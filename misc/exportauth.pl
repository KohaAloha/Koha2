#!/usr/bin/perl
## This script allows you to export a rel_2_2 bibliographic db in 
#MARC21 format from the command line.
#
use HTML::Template;
use strict;
require Exporter;
use C4::Database;
use C4::Auth;
use C4::Interface::CGI::Output;
use C4::Output;  # contains gettemplate
use C4::Biblio;
use CGI;
use C4::Auth;
my $outfile = $ARGV[0];
open(OUT,">$outfile") or die $!;
my $query = new CGI;
my $dbh=DBI->connect("DBI:mysql:database=koha2;host=localhost;port=3306","kohaserver","kohaserver") or die $DBI::errmsg;
#$dbh->do("set character_set_client='latin5'");	
#$dbh->do("set character_set_connection='utf8'");
#$dbh->do("set character_set_results='latin5'");		
#my $dbh=C4::Context->dbh;
	my $sth;
	
		$sth=$dbh->prepare("select marc from auth_header order by authid");
		$sth->execute();
	
	while (my ($marc) = $sth->fetchrow) {

		print OUT $marc;
	}
close(OUT);
