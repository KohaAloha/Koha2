#!/usr/bin/perl

# $Id$

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
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Biblio;
use C4::SearchMarc; # also includes Biblio.pm, SearchMarc is used to FindDuplicate
use C4::Context;
use C4::Log;
use C4::Koha; # XXX subfield_is_koha_internal_p
use HTML::Template;
use MARC::File::USMARC;

use vars qw( $tagslib);
use vars qw( $authorised_values_sth);
use vars qw( $is_a_modif );

my $itemtype; # created here because it can be used in build_authorized_values_list sub

=item find_value

    ($indicators, $value) = find_value($tag, $subfield, $record,$encoding);

Find the given $subfield in the given $tag in the given
MARC::Record $record.  If the subfield is found, returns
the (indicators, value) pair; otherwise, (undef, undef) is
returned.

=cut

sub find_value {
	my ($tagfield,$insubfield,$record,$encoding) = @_;
	my @result;
	my $indicator;
	if ($tagfield <10) {
		if ($record->field($tagfield)) {
			push @result, $record->field($tagfield)->data();
		} else {
			push @result,"";
		}
	} else {
		foreach my $field ($record->field($tagfield)) {
			my @subfields = $field->subfields();
			foreach my $subfield (@subfields) {
				if (@$subfield[0] eq $insubfield) {
					push @result,char_decode(@$subfield[1],$encoding);
					$indicator = $field->indicator(1).$field->indicator(2);
				}
			}
		}
	}
	return($indicator,@result);
}


=item MARCfindbreeding

    $record = MARCfindbreeding($dbh, $breedingid);

Look up the breeding farm with database handle $dbh, for the
record with id $breedingid.  If found, returns the decoded
MARC::Record; otherwise, -1 is returned (FIXME).
Returns as second parameter the character encoding.

=cut

sub MARCfindbreeding {
	my ($dbh,$id) = @_;
	my $sth = $dbh->prepare("select file,marc,encoding from marc_breeding where id=?");
	$sth->execute($id);
	my ($file,$marc,$encoding) = $sth->fetchrow;
	if ($marc) {
		my $record = MARC::File::USMARC::decode($marc);
		if (ref($record) eq undef) {
			return -1;
		} else {
			return $record,$encoding;
		}
	}
	return -1;
}


=item build_authorized_values_list

=cut

sub build_authorized_values_list ($$$$$) {
	my($tag, $subfield, $value, $dbh,$authorised_values_sth) = @_;

	my @authorised_values;
	my %authorised_lib;

	# builds list, depending on authorised value...

	#---- branch
	if ($tagslib->{$tag}->{$subfield}->{'authorised_value'} eq "branches" ) {
	my $sth=$dbh->prepare("select branchcode,branchname from branches order by branchname");
	$sth->execute;
	push @authorised_values, ""
		unless ($tagslib->{$tag}->{$subfield}->{mandatory});

	while (my ($branchcode,$branchname) = $sth->fetchrow_array) {
		push @authorised_values, $branchcode;
		$authorised_lib{$branchcode}=$branchname;
	}

	#----- itemtypes
	} elsif ($tagslib->{$tag}->{$subfield}->{authorised_value} eq "itemtypes") {
		my $sth=$dbh->prepare("select itemtype,description from itemtypes order by description");
		$sth->execute;
		push @authorised_values, "" unless ($tagslib->{$tag}->{$subfield}->{mandatory});
	
		while (my ($itemtype,$description) = $sth->fetchrow_array) {
			push @authorised_values, $itemtype;
			$authorised_lib{$itemtype}=$description;
		}
		$value=$itemtype unless ($value);

	#---- "true" authorised value
	} else {
		$authorised_values_sth->execute($tagslib->{$tag}->{$subfield}->{authorised_value});

		push @authorised_values, "" unless ($tagslib->{$tag}->{$subfield}->{mandatory});
	
		while (my ($value,$lib) = $authorised_values_sth->fetchrow_array) {
			push @authorised_values, $value;
			$authorised_lib{$value}=$lib;
		}
    }
    return CGI::scrolling_list( -name     => 'field_value',
				-values   => \@authorised_values,
				-default  => $value,
				-labels   => \%authorised_lib,
				-override => 1,
				-size     => 1,
				-multiple => 0 );
}

=item create_input
 builds the <input ...> entry for a subfield.
=cut
sub create_input () {
	my ($tag,$subfield,$value,$i,$tabloop,$rec,$authorised_values_sth) = @_;
	$value =~ s/"/&quot;/g;
	my $dbh = C4::Context->dbh;
	my %subfield_data;
	$subfield_data{tag}=$tag;
	$subfield_data{subfield}=$subfield;
	$subfield_data{marc_lib}="<span id=\"error$i\">".$tagslib->{$tag}->{$subfield}->{lib}."</span>";
	$subfield_data{tag_mandatory}=$tagslib->{$tag}->{mandatory};
	$subfield_data{mandatory}=$tagslib->{$tag}->{$subfield}->{mandatory};
	$subfield_data{repeatable}=$tagslib->{$tag}->{$subfield}->{repeatable};
	$subfield_data{kohafield}=$tagslib->{$tag}->{$subfield}->{kohafield};
	# it's an authorised field
	if ($tagslib->{$tag}->{$subfield}->{authorised_value}) {
		$subfield_data{marc_value}= build_authorized_values_list($tag, $subfield, $value, $dbh,$authorised_values_sth);
	# it's a thesaurus / authority field
	} elsif ($tagslib->{$tag}->{$subfield}->{authtypecode}) {
		$subfield_data{marc_value}="<input type=\"text\" name=\"field_value\" value=\"$value\" size=\"77\" maxlength=\"255\" DISABLE READONLY> <a href=\"javascript:Dopop('../authorities/auth_finder.pl?authtypecode=".$tagslib->{$tag}->{$subfield}->{authtypecode}."&index=$i',$i)\">...</a>";
	# it's a plugin field
	} elsif ($tagslib->{$tag}->{$subfield}->{'value_builder'}) {
		# opening plugin. Just check wether we are on a developper computer on a production one
		# (the cgidir differs)
		my $cgidir = C4::Context->intranetdir ."/cgi-bin/value_builder";
		unless (opendir(DIR, "$cgidir")) {
			$cgidir = C4::Context->intranetdir."/value_builder";
		} 
		my $plugin=$cgidir."/".$tagslib->{$tag}->{$subfield}->{'value_builder'}; 
		require $plugin;
		my $extended_param = plugin_parameters($dbh,$rec,$tagslib,$i,$tabloop);
		my ($function_name,$javascript) = plugin_javascript($dbh,$rec,$tagslib,$i,$tabloop);
		$subfield_data{marc_value}="<input type=\"text\" name=\"field_value\"  value=\"$value\" size=\"77\" maxlength=\"255\" OnFocus=\"javascript:Focus$function_name($i)\" OnBlur=\"javascript:Blur$function_name($i)\"> <a href=\"javascript:Clic$function_name($i)\">...</a> $javascript";
	# it's an hidden field
	} elsif  ($tag eq '') {
		$subfield_data{marc_value}="<input type=\"hidden\" name=\"field_value\" value=\"$value\">";
	} elsif  ($tagslib->{$tag}->{$subfield}->{'hidden'}) {
		$subfield_data{marc_value}="<input type=\"text\" name=\"field_value\" value=\"$value\" size=\"80\" maxlength=\"255\" DISABLE READONLY>";
	# it's a standard field
	} else {
		if (length($value) >100) {
			$subfield_data{marc_value}="<textarea name=\"field_value\" cols=\"80\" rows=\"5\" >$value</textarea>";
		} else {
			$subfield_data{marc_value}="<input type=\"text\" name=\"field_value\" value=\"$value\" size=\"80\">"; #"
		}
	}
	return \%subfield_data;
}

sub build_tabs ($$$$) {
    my($template, $record, $dbh,$encoding) = @_;
    # fill arrays
    my @loop_data =();
    my $tag;
    my $i=0;
	my $authorised_values_sth = $dbh->prepare("select authorised_value,lib
		from authorised_values
		where category=? order by lib");

# loop through each tab 0 through 9
	for (my $tabloop = 0; $tabloop <= 9; $tabloop++) {
		my @loop_data = ();
		foreach my $tag (sort(keys (%{$tagslib}))) {
			my $indicator;
	# if MARC::Record is not empty => use it as master loop, then add missing subfields that should be in the tab.
	# if MARC::Record is empty => use tab as master loop.
			if ($record ne -1 && ($record->field($tag) || $tag eq '000')) {
				my @fields;
				if ($tag ne '000') {
					@fields = $record->field($tag);
				} else {
					push @fields,$record->leader();
				}
				foreach my $field (@fields)  {
					my @subfields_data;
					if ($tag<10) {
						my ($value,$subfield);
						if ($tag ne '000') {
							$value=$field->data();
							$subfield="@";
						} else {
							$value = $field;
							$subfield='@';
						}
						next if ($tagslib->{$tag}->{$subfield}->{tab} ne $tabloop);
						next if ($tagslib->{$tag}->{$subfield}->{kohafield} eq 'biblio.biblionumber');
						push(@subfields_data, &create_input($tag,$subfield,char_decode($value,$encoding),$i,$tabloop,$record,$authorised_values_sth));
						$i++;
					} else {
						my @subfields=$field->subfields();
						foreach my $subfieldcount (0..$#subfields) {
							my $subfield=$subfields[$subfieldcount][0];
							my $value=$subfields[$subfieldcount][1];
							next if (length $subfield !=1);
							next if ($tagslib->{$tag}->{$subfield}->{tab} ne $tabloop);
							push(@subfields_data, &create_input($tag,$subfield,char_decode($value,$encoding),$i,$tabloop,$record,$authorised_values_sth));
							$i++;
						}
					}
# now, loop again to add parameter subfield that are not in the MARC::Record
					foreach my $subfield (sort( keys %{$tagslib->{$tag}})) {
						next if (length $subfield !=1);
						next if ($tagslib->{$tag}->{$subfield}->{tab} ne $tabloop);
						next if ($tag<10);
						next if (defined($field->subfield($subfield)));
						push(@subfields_data, &create_input($tag,$subfield,'',$i,$tabloop,$record,$authorised_values_sth));
						$i++;
					}
					if ($#subfields_data >= 0) {
						my %tag_data;
						$tag_data{tag} = $tag;
						$tag_data{tag_lib} = $tagslib->{$tag}->{lib};
						$tag_data{repeatable} = $tagslib->{$tag}->{repeatable};
						$tag_data{indicator} = $record->field($tag)->indicator(1). $record->field($tag)->indicator(2) if ($tag>=10);
						$tag_data{subfield_loop} = \@subfields_data;
						push (@loop_data, \%tag_data);
					}
# If there is more than 1 field, add an empty hidden field as separator.
					if ($#fields >1) {
						my @subfields_data;
						my %tag_data;
						push(@subfields_data, &create_input('','','',$i,$tabloop,$record,$authorised_values_sth));
						$tag_data{tag} = '';
						$tag_data{tag_lib} = '';
						$tag_data{indicator} = '';
						$tag_data{subfield_loop} = \@subfields_data;
						push (@loop_data, \%tag_data);
						$i++;
					}
				}
	# if breeding is empty
			} else {
				my @subfields_data;
				foreach my $subfield (sort(keys %{$tagslib->{$tag}})) {
					next if (length $subfield !=1);
					next if ($tagslib->{$tag}->{$subfield}->{tab} ne $tabloop);
					push(@subfields_data, &create_input($tag,$subfield,'',$i,$tabloop,$record,$authorised_values_sth));
					$i++;
				}
				if ($#subfields_data >= 0) {
					my %tag_data;
					$tag_data{tag} = $tag;
					$tag_data{tag_lib} = $tagslib->{$tag}->{lib};
					$tag_data{repeatable} = $tagslib->{$tag}->{repeatable};
					$tag_data{indicator} = $indicator;
					$tag_data{subfield_loop} = \@subfields_data;
					push (@loop_data, \%tag_data);
				}
			}
		}
		$template->param($tabloop."XX" =>\@loop_data);
	}
}


sub build_hidden_data () {
    # build hidden data =>
    # we store everything, even if we show only requested subfields.

    my @loop_data =();
    my $i=0;
    foreach my $tag (keys %{$tagslib}) {
	my $previous_tag = '';

	# loop through each subfield
	foreach my $subfield (keys %{$tagslib->{$tag}}) {
	    next if ($subfield eq 'lib');
	    next if ($subfield eq 'tab');
	    next if ($subfield eq 'mandatory');
		next if ($subfield eq 'repeatable');
	    next if ($tagslib->{$tag}->{$subfield}->{'tab'}  ne "-1");
	    my %subfield_data;
	    $subfield_data{marc_lib}=$tagslib->{$tag}->{$subfield}->{lib};
	    $subfield_data{marc_mandatory}=$tagslib->{$tag}->{$subfield}->{mandatory};
	    $subfield_data{marc_repeatable}=$tagslib->{$tag}->{$subfield}->{repeatable};
	    $subfield_data{marc_value}="<input type=\"hidden\" name=\"field_value[]\">";
	    push(@loop_data, \%subfield_data);
	    $i++
	}
    }
}


# ======================== 
#          MAIN 
#=========================
my $input = new CGI;
my $error = $input->param('error');
my $biblionumber=$input->param('biblionumber'); # if biblionumber exists, it's a modif, not a new biblio.
my $breedingid = $input->param('breedingid');
my $z3950 = $input->param('z3950');
my $op = $input->param('op');
my $frameworkcode = $input->param('frameworkcode');
my $dbh = C4::Context->dbh;


$frameworkcode = &MARCfind_frameworkcode($dbh,$biblionumber) if ($biblionumber and not ($frameworkcode));
$frameworkcode='' if ($frameworkcode eq 'Default');
my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "acqui.simple/addbiblio.tmpl",
			     query => $input,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {editcatalogue => 1},
			     debug => 1,
			     });

#Getting the list of all frameworks
my $queryfwk =$dbh->prepare("select frameworktext, frameworkcode from biblio_framework");
$queryfwk->execute;
my %select_fwk;
my @select_fwk;
my $curfwk;
push @select_fwk,"Default";
$select_fwk{"Default"} = "Default";
while (my ($description, $fwk) =$queryfwk->fetchrow) {
	push @select_fwk, $fwk;
	$select_fwk{$fwk} = $description;
}
$curfwk=$frameworkcode;
my $framework=CGI::scrolling_list( -name     => 'Frameworks',
			-id => 'Frameworks',
			-default => $curfwk,
			-OnChange => 'Changefwk(this);',
			-values   => \@select_fwk,
			-labels   => \%select_fwk,
			-size     => 1,
			-multiple => 0 );
$template->param( framework => $framework);

$tagslib = &MARCgettagslib($dbh,1,$frameworkcode);
my $record=-1;
my $encoding="";
$record = MARCgetbiblio($dbh,$biblionumber) if ($biblionumber);
($record,$encoding) = MARCfindbreeding($dbh,$breedingid) if ($breedingid);

$is_a_modif=0;
my ($oldbiblionumtagfield,$oldbiblionumtagsubfield);
my ($oldbiblioitemnumtagfield,$oldbiblioitemnumtagsubfield,$bibitem,$oldbiblioitemnumber);
if ($biblionumber) {
	$is_a_modif=1;
	# if it's a modif, retrieve old biblio and bibitem numbers for the future modification of old-DB.
	($oldbiblionumtagfield,$oldbiblionumtagsubfield) = &MARCfind_marc_from_kohafield($dbh,"biblio.biblionumber",$frameworkcode);
	($oldbiblioitemnumtagfield,$oldbiblioitemnumtagsubfield) = &MARCfind_marc_from_kohafield($dbh,"biblioitems.biblioitemnumber",$frameworkcode);
	# search biblioitems value
	my $sth=$dbh->prepare("select biblioitemnumber from biblioitems where biblionumber=?");
	$sth->execute($biblionumber);
	($oldbiblioitemnumber) = $sth->fetchrow;
}
#------------------------------------------------------------------------------------------------------------------------------
if ($op eq "addbiblio") {
#------------------------------------------------------------------------------------------------------------------------------
	# rebuild
	my @tags = $input->param('tag');
	my @subfields = $input->param('subfield');
	my @values = $input->param('field_value');
	# build indicator hash.
	my @ind_tag = $input->param('ind_tag');
	my @indicator = $input->param('indicator');
	my %indicators;
	for (my $i=0;$i<=$#ind_tag;$i++) {
		$indicators{$ind_tag[$i]} = $indicator[$i];
	}
	my $record = MARChtml2marc($dbh,\@tags,\@subfields,\@values,%indicators);
	# check for a duplicate
	my ($duplicatebiblionumber,$duplicatebibid,$duplicatetitle) = FindDuplicate($record) if ($op eq "addbiblio") && (!$is_a_modif);
	my $confirm_not_duplicate = $input->param('confirm_not_duplicate');
	# it is not a duplicate (determined either by Koha itself or by user checking it's not a duplicate)
	if (!$duplicatebiblionumber or $confirm_not_duplicate) {
		# MARC::Record built => now, record in DB
		my $oldbibnum;
		my $oldbibitemnum;
		if ($is_a_modif) {
			NEWmodbiblioframework($dbh,$biblionumber,$frameworkcode);
			NEWmodbiblio($dbh,$record,$biblionumber,$frameworkcode);
			logaction($loggedinuser,"acqui.simple","modify",$biblionumber,"record : ".$record->as_formatted) if (C4::Context->preference("Activate_Log"));
		} else {
			($biblionumber,$oldbibnum,$oldbibitemnum) = NEWnewbiblio($dbh,$record,$frameworkcode);
			logaction($loggedinuser,"acqui.simple","add",$oldbibnum,"record : ".$record->as_formatted) if (C4::Context->preference("Activate_Log"));
		}
	# now, redirect to additem page
		print $input->redirect("additem.pl?biblionumber=$biblionumber&frameworkcode=$frameworkcode");
		exit;
	} else {
	# it may be a duplicate, warn the user and do nothing
		build_tabs ($template, $record, $dbh,$encoding);
		build_hidden_data;
		$template->param(
			biblionumber             => $biblionumber,
			oldbiblionumtagfield        => $oldbiblionumtagfield,
			oldbiblionumtagsubfield     => $oldbiblionumtagsubfield,
			oldbiblioitemnumtagfield    => $oldbiblioitemnumtagfield,
			oldbiblioitemnumtagsubfield => $oldbiblioitemnumtagsubfield,
			oldbiblioitemnumber         => $oldbiblioitemnumber,
			duplicatebiblionumber		=> $duplicatebiblionumber,
			duplicatetitle				=> $duplicatetitle,
			 );
	}
#------------------------------------------------------------------------------------------------------------------------------
} elsif ($op eq "addfield") {
#------------------------------------------------------------------------------------------------------------------------------
	my $addedfield = $input->param('addfield_field');
	my @tags = $input->param('tag');
	my @subfields = $input->param('subfield');
	my @values = $input->param('field_value');
	# build indicator hash.
	my @ind_tag = $input->param('ind_tag');
	my @indicator = $input->param('indicator');
	my %indicators;
	for (my $i=0;$i<=$#ind_tag;$i++) {
		$indicators{$ind_tag[$i]} = $indicator[$i];
	}
	my $record = MARChtml2marc($dbh,\@tags,\@subfields,\@values,%indicators);
	# adding an empty field
	my $field = MARC::Field->new("$addedfield",'','','a'=> "");
	$record->append_fields($field);
	build_tabs ($template, $record, $dbh,$encoding);
	build_hidden_data;
	$template->param(
		biblionumber             => $biblionumber,
		oldbiblionumtagfield        => $oldbiblionumtagfield,
		oldbiblionumtagsubfield     => $oldbiblionumtagsubfield,
		oldbiblioitemnumtagfield    => $oldbiblioitemnumtagfield,
		oldbiblioitemnumtagsubfield => $oldbiblioitemnumtagsubfield,
		oldbiblioitemnumber         => $oldbiblioitemnumber );
} elsif ($op eq "delete") {
#------------------------------------------------------------------------------------------------------------------------------
	&NEWdelbiblio($dbh,$biblionumber);
	logaction($loggedinuser,"acqui.simple","del",$biblionumber,"") if (logstatus);
	
	print "Content-Type: text/html\n\n<META HTTP-EQUIV=Refresh CONTENT=\"0; URL=/cgi-bin/koha/search.marc/search.pl?type=intranet\"></html>";
	exit;
#------------------------------------------------------------------------------------------------------------------------------logaction($loggedinuser,"acqui.simple","add","biblionumber :$oldbibnum");
#------------------------------------------------------------------------------------------------------------------------------
} else {
#------------------------------------------------------------------------------------------------------------------------------
	# If we're in a duplication case, we have to set to "" the bibid and biblionumber
	# as we'll save the biblio as a new one.
	if ($op eq "duplicate")
	{
		$biblionumber= "";
	}
 
	build_tabs ($template, $record, $dbh,$encoding);
	build_hidden_data;
	$template->param(
		biblionumber             => $biblionumber,
		oldbiblionumtagfield        => $oldbiblionumtagfield,
		oldbiblionumtagsubfield     => $oldbiblionumtagsubfield,
		oldbiblioitemnumtagfield    => $oldbiblioitemnumtagfield,
		oldbiblioitemnumtagsubfield => $oldbiblioitemnumtagsubfield,
		oldbiblioitemnumber         => $oldbiblioitemnumber,
		);
}
$template->param(
		frameworkcode => $frameworkcode,
		itemtype => $frameworkcode # HINT: if the library has itemtype = framework, itemtype is auto filled !
		);
output_html_with_http_headers $input, $cookie, $template->output;