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

=head1 NAME

MARCdetail.pl : script to show a biblio in MARC format

=head1 SYNOPSIS


=head1 DESCRIPTION

This script needs a biblionumber in bib parameter (bibnumber
from koha style DB.  Automaticaly maps to marc biblionumber).

It shows the biblio in a (nice) MARC format depending on MARC
parameters tables.

The template is in <templates_dir>/catalogue/MARCdetail.tmpl.
this template must be divided into 11 "tabs".

The first 10 tabs present the biblio, the 11th one presents
the items attached to the biblio

=head1 FUNCTIONS

=over 2

=cut


use strict;
require Exporter;
use C4::Auth;
use C4::Context;
use C4::Output;
use C4::Interface::CGI::Output;
use CGI;
use C4::Search;
use MARC::Record;
use C4::Biblio;
use C4::Acquisition;
use C4::Bull; #uses getsubscriptionfrom biblionumber
use HTML::Template;

my $query=new CGI;

my $dbh=C4::Context->dbh;

my $biblionumber=$query->param('bib');
my $bibid = $query->param('bibid');
my $popup = $query->param('popup'); # if set to 1, then don't insert links, it's just to show the biblio

$bibid = &MARCfind_MARCbibid_from_oldbiblionumber($dbh,$biblionumber) unless $bibid;
$biblionumber = &MARCfind_oldbiblionumber_from_MARCbibid($dbh,$bibid) unless $biblionumber;
my $itemtype = &MARCfind_frameworkcode($dbh,$bibid);
my $tagslib = &MARCgettagslib($dbh,1,$itemtype);

my $record =MARCgetbiblio($dbh,$bibid);
warn "=>".$record->as_formatted;
# open template
my ($template, $loggedinuser, $cookie)
		= get_template_and_user({template_name => "catalogue/MARCdetail.tmpl",
			     query => $query,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {catalogue => 1},
			     debug => 1,
			     });

# fill arrays
my @loop_data =();
my $tag;
# loop through each tab 0 through 9
for (my $tabloop = 0; $tabloop<=10;$tabloop++) {
# loop through each tag
	my @fields = $record->fields();
	my @loop_data =();
# 	foreach my $field (@fields) {
	my @subfields_data;
	for (my $x_i=0;$x_i<=$#fields;$x_i++) {
		warn "$tabloop => $x_i";
		# if tag <10, there's no subfield, use the "@" trick
		if ($fields[$x_i]->tag()<10) {
			next if ($tagslib->{$fields[$x_i]->tag()}->{'@'}->{tab}  ne $tabloop);
			next if ($tagslib->{$fields[$x_i]->tag()}->{'@'}->{hidden});
			my %subfield_data;
			$subfield_data{marc_lib}=$tagslib->{$fields[$x_i]->tag()}->{'@'}->{lib};
			$subfield_data{marc_value}=$fields[$x_i]->data();
			$subfield_data{marc_subfield}='@';
			$subfield_data{marc_tag}=$fields[$x_i]->tag();
			push(@subfields_data, \%subfield_data);
		} else {
			my @subf=$fields[$x_i]->subfields;
	# loop through each subfield
			for my $i (0..$#subf) {
				$subf[$i][0] = "@" unless $subf[$i][0];
				next if ($tagslib->{$fields[$x_i]->tag()}->{$subf[$i][0]}->{tab}  ne $tabloop);
				next if ($tagslib->{$fields[$x_i]->tag()}->{$subf[$i][0]}->{hidden});
				my %subfield_data;
				$subfield_data{marc_lib}=$tagslib->{$fields[$x_i]->tag()}->{$subf[$i][0]}->{lib};
				if ($tagslib->{$fields[$x_i]->tag()}->{$subf[$i][0]}->{isurl}) {
					$subfield_data{marc_value}="<a href=\"$subf[$i][1]\">$subf[$i][1]</a>";
				} else {
					if ($tagslib->{$fields[$x_i]->tag()}->{$subf[$i][0]}->{authtypecode}) {
						$subfield_data{authority}=$fields[$x_i]->subfield(9);
					}
					$subfield_data{marc_value}=$subf[$i][1];
				}
				$subfield_data{marc_subfield}=$subf[$i][0];
				$subfield_data{marc_tag}=$fields[$x_i]->tag();
				push(@subfields_data, \%subfield_data);
			}
		}
		if ($#subfields_data>=0) {
			my %tag_data;
			if ($fields[$x_i]->tag() eq $fields[$x_i-1]->tag()) {
				$tag_data{tag}="";
			} else {
				$tag_data{tag}=$fields[$x_i]->tag().' -'. $tagslib->{$fields[$x_i]->tag()}->{lib};
			}
			my @tmp = @subfields_data;
			$tag_data{subfield} = \@tmp;
			push (@loop_data, \%tag_data);
			undef @subfields_data;
		}
	}
	$template->param($tabloop."XX" =>\@loop_data);
}
# now, build item tab !
# the main difference is that datas are in lines and not in columns : thus, we build the <th> first, then the values...
# loop through each tag
# warning : we may have differents number of columns in each row. Thus, we first build a hash, complete it if necessary
# then construct template.
my @fields = $record->fields();
my %witness; #---- stores the list of subfields used at least once, with the "meaning" of the code
my @big_array;
foreach my $field (@fields) {
	next if ($field->tag()<10);
	my @subf=$field->subfields;
	my %this_row;
# loop through each subfield
	for my $i (0..$#subf) {
		next if ($tagslib->{$field->tag()}->{$subf[$i][0]}->{tab}  ne 10);
		$witness{$subf[$i][0]} = $tagslib->{$field->tag()}->{$subf[$i][0]}->{lib};
		$this_row{$subf[$i][0]} =$subf[$i][1];
	}
	if (%this_row) {
		push(@big_array, \%this_row);
	}
}
#fill big_row with missing datas
foreach my $subfield_code  (keys(%witness)) {
	for (my $i=0;$i<=$#big_array;$i++) {
		$big_array[$i]{$subfield_code}="&nbsp;" unless ($big_array[$i]{$subfield_code});
	}
}
# now, construct template !
my @item_value_loop;
my @header_value_loop;
for (my $i=0;$i<=$#big_array; $i++) {
	my $items_data;
	foreach my $subfield_code (keys(%witness)) {
		$items_data .="<td>".$big_array[$i]{$subfield_code}."</td>";
	}
	my %row_data;
	$row_data{item_value} = $items_data;
	push(@item_value_loop,\%row_data);
}
foreach my $subfield_code (keys(%witness)) {
	my %header_value;
	$header_value{header_value} = $witness{$subfield_code};
	push(@header_value_loop, \%header_value);
}

my $subscriptionid = getsubscriptionfrombiblionumber($biblionumber);
$template->param(item_loop => \@item_value_loop,
						item_header_loop => \@header_value_loop,
						biblionumber => $biblionumber,
						bibid => $bibid,
						biblionumber => $biblionumber,
						subscriptionid => $subscriptionid,
						popup => $popup,
						);
output_html_with_http_headers $query, $cookie, $template->output;

