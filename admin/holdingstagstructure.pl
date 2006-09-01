#!/usr/bin/perl


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
use C4::Auth;
use C4::Koha;
use C4::Context;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Search;


# retrieve parameters
my $input = new CGI;
my $frameworkcode = $input->param('frameworkcode'); # set to select framework
$frameworkcode="" unless $frameworkcode;
my $existingframeworkcode = $input->param('existingframeworkcode'); # set when we have to create a new framework (in frameworkcode) by copying an old one (in existingframeworkcode)
$existingframeworkcode = "" unless $existingframeworkcode;
my $frameworkinfo = getframeworkinfo($frameworkcode);
my $searchfield=$input->param('searchfield');
$searchfield=0 unless $searchfield;
$searchfield=~ s/\,//g;

my $offset=$input->param('offset');
my $op = $input->param('op');
my $dspchoice = $input->param('select_display');
my $pagesize=20;

my $script_name="/cgi-bin/koha/admin/holdingstagstructure.pl";

my $dbh = C4::Context->dbh;

# open template
my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "admin/holdingstagstructure.tmpl",
			     query => $input,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {parameters => 1},
			     debug => 1,
			     });

# get framework list
my $frameworks = getframeworks();
my @frameworkloop;
foreach my $thisframeworkcode (keys %$frameworks) {
	my $selected = 1 if $thisframeworkcode eq $frameworkcode;
	my %row =(value => $thisframeworkcode,
				selected => $selected,
				frameworktext => $frameworks->{$thisframeworkcode}->{'frameworktext'},
			);
	push @frameworkloop, \%row;
}

# check that framework is defined in holdings_tag_structure
my $sth=$dbh->prepare("select count(*) from holdings_tag_structure where frameworkcode=?");
$sth->execute($frameworkcode);
my ($frameworkexist) = $sth->fetchrow;
if ($frameworkexist) {
} else {
	# if frameworkcode does not exists, then OP must be changed to "create framework" if we are not on the way to create it
	# (op = itemtyp_create_confirm)
	if ($op eq "framework_create_confirm") {
		duplicate_framework($frameworkcode, $existingframeworkcode);
		$op=""; # unset $op to go back to framework list
	} else {
		$op = "framework_create";
	}
}
$template->param(frameworkloop => \@frameworkloop,
				frameworkcode => $frameworkcode,
				frameworktext => $frameworkinfo->{frameworktext});
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
	#---- if primkey exists, it's a modify action, so read values to modify...
	my $data;
	if ($searchfield) {
		$sth=$dbh->prepare("select tagfield,liblibrarian,libopac,repeatable,mandatory,authorised_value from holdings_tag_structure where tagfield=? and frameworkcode=?");
		$sth->execute($searchfield,$frameworkcode);
		$data=$sth->fetchrow_hashref;
		$sth->finish;
	}
	my $sth = $dbh->prepare("select distinct category from authorised_values");
	$sth->execute;
	my @authorised_values;
	push @authorised_values,"";
	while ((my $category) = $sth->fetchrow_array) {
		push @authorised_values, $category;
	}
	my $authorised_value  = CGI::scrolling_list(-name=>'authorised_value',
			-values=> \@authorised_values,
			-size=>1,
			-id=>"authorised_value",
			-multiple=>0,
			-default => $data->{'authorised_value'},
			);

	if ($searchfield) {
		$template->param(action => "Modify tag",
								searchfield => "<input type=\"hidden\" name=\"tagfield\" value=\"$searchfield\" />$searchfield");
		$template->param('heading-modify-tag-p' => 1);
	} else {
		$template->param(action => "Add tag",
								searchfield => "<input type=\"text\" name=\"tagfield\" size=\"5\" maxlength=\"3\" />");
		$template->param('heading-add-tag-p' => 1);
	}
	$template->param('use-heading-flags-p' => 1);
	$template->param(liblibrarian => $data->{'liblibrarian'},
			libopac => $data->{'libopac'},
			repeatable => CGI::checkbox(-name=>'repeatable',
						-checked=> $data->{'repeatable'}?'checked':'',
						-value=> 1,
						-label => '',
						-id=> 'repeatable'),
			mandatory => CGI::checkbox(-name => 'mandatory',
						-checked => $data->{'mandatory'}?'checked':'',
						-value => 1,
						-label => '',
						-id => 'mandatory'),
			authorised_value => $authorised_value,
			frameworkcode => $frameworkcode,
			);
													# END $OP eq ADD_FORM
################## ADD_VALIDATE ##################################
# called by add_form, used to insert/modify data in DB
} elsif ($op eq 'add_validate') {
	$sth=$dbh->prepare("replace holdings_tag_structure (tagfield,liblibrarian,libopac,repeatable,mandatory,authorised_value,frameworkcode) values (?,?,?,?,?,?,?)");
	my $tagfield       =$input->param('tagfield');
	my $liblibrarian  = $input->param('liblibrarian');
	my $libopac       =$input->param('libopac');
	my $repeatable =$input->param('repeatable');
	my $mandatory =$input->param('mandatory');
	my $authorised_value =$input->param('authorised_value');
	unless (C4::Context->config('demo') eq 1) {
		$sth->execute($tagfield,
							$liblibrarian,
							$libopac,
							$repeatable?1:0,
							$mandatory?1:0,
							$authorised_value,
							$frameworkcode
							);
	}
	$sth->finish;
	print "Content-Type: text/html\n\n<META HTTP-EQUIV=Refresh CONTENT=\"0; URL=holdingstagstructure.pl?searchfield=$tagfield&frameworkcode=$frameworkcode\"></html>";
	exit;
													# END $OP eq ADD_VALIDATE
################## DELETE_CONFIRM ##################################
# called by default form, used to confirm deletion of data in DB
} elsif ($op eq 'delete_confirm') {
	$sth=$dbh->prepare("select tagfield,liblibrarian,libopac,repeatable,mandatory,authorised_value from holdings_tag_structure where tagfield=? and frameworkcode=?");
	$sth->execute($searchfield,$frameworkcode);
	my $data=$sth->fetchrow_hashref;
	$sth->finish;
	$template->param(liblibrarian => $data->{'liblibrarian'},
							searchfield => $searchfield,
							frameworkcode => $frameworkcode,
							);
													# END $OP eq DELETE_CONFIRM
################## DELETE_CONFIRMED ##################################
# called by delete_confirm, used to effectively confirm deletion of data in DB
} elsif ($op eq 'delete_confirmed') {
	unless (C4::Context->config('demo') eq 1) {
		$dbh->do("delete from holdings_tag_structure where tagfield='$searchfield' and frameworkcode='$frameworkcode'");
		$dbh->do("delete from holdings_subfield_structure where tagfield='$searchfield' and frameworkcode='$frameworkcode'");

	}
													# END $OP eq DELETE_CONFIRMED
################## ITEMTYPE_CREATE ##################################
# called automatically if an unexisting  frameworkis selected
} elsif ($op eq 'framework_create') {
	$sth = $dbh->prepare("select count(*),holdings_tag_structure.frameworkcode,frameworktext from holdings_tag_structure,biblio_framework where biblio_framework.frameworkcode=holdings_tag_structure.frameworkcode group by holdings_tag_structure.frameworkcode");
	$sth->execute;
	my @existingframeworkloop;
	while (my ($tot,$thisframeworkcode,$frameworktext) = $sth->fetchrow) {
		if ($tot>0) {
			my %line = ( value => $thisframeworkcode,
						frameworktext => $frameworktext,
					);
			push @existingframeworkloop,\%line;
		}
	}
	$template->param(existingframeworkloop => \@existingframeworkloop,
					frameworkcode => $frameworkcode,
# 					FRtext => $frameworkinfo->{frameworktext},
					);
################## DEFAULT ##################################
} else { # DEFAULT
	# here, $op can be unset or set to "framework_create_confirm".
	if  ($searchfield ne '') {
		 $template->param(searchfield => $searchfield);
	}
	my $cnt=0;
	if ($dspchoice) {
		#here, user only wants used tags/subfields displayed
		my $env;
		$searchfield=~ s/\'/\\\'/g;
		my @data=split(' ',$searchfield);
		my $sth=$dbh->prepare("Select holdings_tag_structure.tagfield as mts_tagfield,holdings_tag_structure.liblibrarian as mts_liblibrarian,holdings_tag_structure.libopac as mts_libopac,holdings_tag_structure.repeatable as mts_repeatable,holdings_tag_structure.mandatory as mts_mandatory,holdings_tag_structure.authorised_value as mts_authorized_value,holdings_subfield_structure.* from holdings_tag_structure LEFT JOIN holdings_subfield_structure ON (holdings_tag_structure.tagfield=holdings_subfield_structure.tagfield AND holdings_tag_structure.frameworkcode=holdings_subfield_structure.frameworkcode) where (holdings_tag_structure.tagfield >= ? and holdings_tag_structure.frameworkcode=?) AND holdings_subfield_structure.tab>=0 order by holdings_tag_structure.tagfield,holdings_subfield_structure.tagsubfield");
		#could be ordoned by tab
		$sth->execute($data[0], $frameworkcode);
		my @results = ();
		while (my $data=$sth->fetchrow_hashref){
			push(@results,$data);
			$cnt++;
		}
		$sth->finish;
		
		my $toggle=0;
		my @loop_data = ();
		my $j=1;
		my $i=$offset;
		while ($i < ($offset+$pagesize<$cnt?$offset+$pagesize:$cnt)) {
			if ($toggle eq 0){
				$toggle=1;
			} else {
				$toggle=0;
			}
			my %row_data;  # get a fresh hash for the row data
			$row_data{tagfield} = $results[$i]->{'mts_tagfield'};
			$row_data{liblibrarian} = $results[$i]->{'mts_liblibrarian'};
			$row_data{repeatable} = $results[$i]->{'mts_repeatable'};
			$row_data{mandatory} = $results[$i]->{'mts_mandatory'};
			$row_data{authorised_value} = $results[$i]->{'mts_authorised_value'};
			$row_data{subfield_link} ="holdings_subfields_structure.pl?op=add_form&tagfield=".$results[$i]->{'mts_tagfield'}."&frameworkcode=".$frameworkcode;
			$row_data{edit} = "$script_name?op=add_form&amp;searchfield=".$results[$i]->{'mts_tagfield'}."&frameworkcode=".$frameworkcode;
			$row_data{delete} = "$script_name?op=delete_confirm&amp;searchfield=".$results[$i]->{'mts_tagfield'}."&frameworkcode=".$frameworkcode;
			$row_data{toggle} = $toggle;
			$j=$i;
			my @internal_loop = ();
			while (($results[$i]->{'tagfield'}==$results[$j]->{'tagfield'}) and ($j< ($offset+$pagesize<$cnt?$offset+$pagesize:$cnt))) {
				if ($toggle eq 0) {
					$toggle=1;
				} else {
					$toggle=0;
				}
				my %subfield_data;
				$subfield_data{tagsubfield} = $results[$j]->{'tagsubfield'};
				$subfield_data{liblibrarian} = $results[$j]->{'liblibrarian'};
				
				$subfield_data{repeatable} = $results[$j]->{'repeatable'};
				$subfield_data{mandatory} = $results[$j]->{'mandatory'};
				$subfield_data{tab} = $results[$j]->{'tab'};
				$subfield_data{seealso} = $results[$j]->{'seealso'};
				$subfield_data{authorised_value} = $results[$j]->{'authorised_value'};
				$subfield_data{authtypecode}= $results[$j]->{'authtypecode'};
				$subfield_data{value_builder}= $results[$j]->{'value_builder'};
				$subfield_data{toggle}	= $toggle;
# 				warn "tagfield :  ".$results[$j]->{'tagfield'}." tagsubfield :".$results[$j]->{'tagsubfield'};
				push @internal_loop,\%subfield_data;
				$j++;
			}
			$row_data{'subfields'}=\@internal_loop;
			push(@loop_data, \%row_data);
#			undef @internal_loop;
			$i=$j;
		}
		$template->param(select_display => "True",
						loop => \@loop_data);
		#  $sth->execute;
		$sth->finish;
	} else {
		#here, normal old style : display every tags
		my $env;
		my ($count,$results)=StringSearch($env,$searchfield,$frameworkcode);
		$cnt = $count;
		my $toggle=0;
		my @loop_data = ();
		for (my $i=$offset; $i < ($offset+$pagesize<$count?$offset+$pagesize:$count); $i++){
			if ($toggle eq 0){
				$toggle=1;
			} else {
				$toggle=0;
			}
			my %row_data;  # get a fresh hash for the row data
			$row_data{tagfield} = $results->[$i]{'tagfield'};
			$row_data{liblibrarian} = $results->[$i]{'liblibrarian'};
			$row_data{repeatable} = $results->[$i]{'repeatable'};
			$row_data{mandatory} = $results->[$i]{'mandatory'};
			$row_data{authorised_value} = $results->[$i]{'authorised_value'};
			$row_data{subfield_link} ="holdings_subfields_structure.pl?tagfield=".$results->[$i]{'tagfield'}."&frameworkcode=".$frameworkcode;
			$row_data{edit} = "$script_name?op=add_form&amp;searchfield=".$results->[$i]{'tagfield'}."&frameworkcode=".$frameworkcode;
			$row_data{delete} = "$script_name?op=delete_confirm&amp;searchfield=".$results->[$i]{'tagfield'}."&frameworkcode=".$frameworkcode;
			$row_data{toggle} = $toggle;
			push(@loop_data, \%row_data);
		}
		$template->param(loop => \@loop_data);
	}
	if ($offset>0) {
		my $prevpage = $offset-$pagesize;
		$template->param(isprevpage => $offset,
						prevpage=> $prevpage,
						searchfield => $searchfield,
						script_name => $script_name,
						frameworkcode => $frameworkcode,
		);
	}
	if ($offset+$pagesize<$cnt) {
		my $nextpage =$offset+$pagesize;
		$template->param(nextpage =>$nextpage,
						searchfield => $searchfield,
						script_name => $script_name,
						frameworkcode => $frameworkcode,
		);
	}
} #---- END $OP eq DEFAULT

$template->param(loggeninuser => $loggedinuser,
		intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
		);
output_html_with_http_headers $input, $cookie, $template->output;


#
# the sub used for searches
#
sub StringSearch  {
	my ($env,$searchstring,$frameworkcode)=@_;
	my $dbh = C4::Context->dbh;
	$searchstring=~ s/\'/\\\'/g;
	my @data=split(' ',$searchstring);
	my $count=@data;
	my $sth=$dbh->prepare("Select tagfield,liblibrarian,libopac,repeatable,mandatory,authorised_value from holdings_tag_structure where (tagfield >= ? and frameworkcode=?) order by tagfield");
	$sth->execute($data[0], $frameworkcode);
	my @results;
	while (my $data=$sth->fetchrow_hashref){
	push(@results,$data);
	}
	#  $sth->execute;
	$sth->finish;
	return (scalar(@results),\@results);
}

#


