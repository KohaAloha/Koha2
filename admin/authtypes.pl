#!/usr/bin/perl
# NOTE: 4-character tabs

#written 20/02/2002 by paul.poulain@free.fr
# This software is placed under the gnu General Public License, v2 (http://www.gnu.org/licenses/gpl.html)

# Copyright 2000-2002 Katipo Communications
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA

use strict;
use CGI;
use C4::Context;
use C4::Output;
use C4::Search;
use C4::Auth;
use C4::Interface::CGI::Output;
use HTML::Template;

sub StringSearch  {
	my ($env,$searchstring,$type)=@_;
	my $dbh = C4::Context->dbh;
	$searchstring=~ s/\'/\\\'/g;
	my @data=split(' ',$searchstring);
	my $count=@data;
	my $sth=$dbh->prepare("Select * from auth_types where (authtypecode like ?) order by authtypecode");
	$sth->execute("$data[0]%");
	my @results;
	while (my $data=$sth->fetchrow_hashref){
	push(@results,$data);
	}
	#  $sth->execute;
	$sth->finish;
	return (scalar(@results),\@results);
}

my $input = new CGI;
my $searchfield=$input->param('authtypecode');
my $offset=$input->param('offset');
my $script_name="/cgi-bin/koha/admin/authtypes.pl";
my $authtypecode=$input->param('authtypecode');
my $pagesize=20;
my $op = $input->param('op');
$searchfield=~ s/\,//g;
my ($template, $borrowernumber, $cookie)
    = get_template_and_user({template_name => "parameters/authtypes.tmpl",
			     query => $input,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {parameters => 1},
			     debug => 1,
			     });

if ($op) {
$template->param(script_name => $script_name,
						$op              => 1); # we show only the TMPL_VAR names $op
} else {
$template->param(script_name => $script_name,
						else              => 1); # we show only the TMPL_VAR names $op
}
################## ADD_FORM ##################################
# called by default. Used to create form to add or  modify a record
if ($op eq 'add_form') {
	#start the page and read in includes
	#---- if primkey exists, it's a modify action, so read values to modify...
	my $data;
	if ($authtypecode) {
		my $dbh = C4::Context->dbh;
		my $sth=$dbh->prepare("select authtypecode,authtypetext,auth_tag_to_report from auth_types where authtypecode=?");
		$sth->execute($authtypecode);
		$data=$sth->fetchrow_hashref;
		$sth->finish;
	}
	$template->param(authtypecode => $authtypecode,
							authtypetext => $data->{'authtypetext'},
							auth_tag_to_report => $data->{'auth_tag_to_report'},
							);
;
													# END $OP eq ADD_FORM
################## ADD_VALIDATE ##################################
# called by add_form, used to insert/modify data in DB
} elsif ($op eq 'add_validate') {
	my $dbh = C4::Context->dbh;
	my $sth=$dbh->prepare("replace auth_types (authtypecode,authtypetext,auth_tag_to_report) values (?,?,?)");
	$sth->execute($input->param('authtypecode'),$input->param('authtypetext'),$input->param('auth_tag_to_report'));
	$sth->finish;
	print "Content-Type: text/html\n\n<META HTTP-EQUIV=Refresh CONTENT=\"0; URL=authtypes.pl\"></html>";
	exit;
													# END $OP eq ADD_VALIDATE
################## DELETE_CONFIRM ##################################
# called by default form, used to confirm deletion of data in DB
} elsif ($op eq 'delete_confirm') {
	#start the page and read in includes
	my $dbh = C4::Context->dbh;

	# Check both categoryitem and biblioitems, see Bug 199
	my $total = 0;
	for my $table ('auth_tag_structure') {
	   my $sth=$dbh->prepare("select count(*) as total from $table where authtypecode=?");
	   $sth->execute($authtypecode);
	   $total += $sth->fetchrow_hashref->{total};
	   $sth->finish;
	}

	my $sth=$dbh->prepare("select authtypecode,authtypetext from authtypes where authtypecode=?");
	$sth->execute($authtypecode);
	my $data=$sth->fetchrow_hashref;
	$sth->finish;

	$template->param(authtypecode => $authtypecode,
							authtypetext => $data->{'authtypetext'},
							total => $total);
													# END $OP eq DELETE_CONFIRM
################## DELETE_CONFIRMED ##################################
# called by delete_confirm, used to effectively confirm deletion of data in DB
} elsif ($op eq 'delete_confirmed') {
	#start the page and read in includes
	my $dbh = C4::Context->dbh;
	my $authtypecode=uc($input->param('authtypecode'));
	my $sth=$dbh->prepare("delete from auth_types where authtypecode=?");
	$sth->execute($authtypecode);
	$sth->finish;
	print "Content-Type: text/html\n\n<META HTTP-EQUIV=Refresh CONTENT=\"0; URL=authtypes.pl\"></html>";
	exit;
													# END $OP eq DELETE_CONFIRMED
################## DEFAULT ##################################
} else { # DEFAULT
	my $env;
	my ($count,$results)=StringSearch($env,$searchfield,'web');
	my $toggle="white";
	my @loop_data;
	for (my $i=$offset; $i < ($offset+$pagesize<$count?$offset+$pagesize:$count); $i++){
		my %row_data;
		if ($toggle eq 'white'){
			$row_data{toggle}="#ffffcc";
		} else {
			$row_data{toggle}="white";
		}
		$row_data{authtypecode} = $results->[$i]{'authtypecode'};
		$row_data{authtypetext} = $results->[$i]{'authtypetext'};
		$row_data{auth_tag_to_report} = $results->[$i]{'auth_tag_to_report'};
		push(@loop_data, \%row_data);
	}
	$template->param(loop => \@loop_data);
	if ($offset>0) {
		my $prevpage = $offset-$pagesize;
		$template->param(previous => "$script_name?offset=".$prevpage);
	}
	if ($offset+$pagesize<$count) {
		my $nextpage =$offset+$pagesize;
		$template->param(next => "$script_name?offset=".$nextpage);
	}
} #---- END $OP eq DEFAULT
output_html_with_http_headers $input, $cookie, $template->output;

# Local Variables:
# tab-width: 4
# End:
