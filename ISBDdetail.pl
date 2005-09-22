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

ISBDdetail.pl : script to show a biblio in ISBD format

=head1 SYNOPSIS


=head1 DESCRIPTION

This script needs a biblionumber in bib parameter (bibnumber
from koha style DB.  Automaticaly maps to marc biblionumber).

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
use HTML::Template;

my $query=new CGI;

my $dbh=C4::Context->dbh;

my $biblionumber=$query->param('biblionumber');
my $itemtype = &MARCfind_frameworkcode($dbh,$biblionumber);
my $tagslib = &MARCgettagslib($dbh,1,$itemtype);

my $record =MARCgetbiblio($dbh,$biblionumber);
# open template
my ($template, $loggedinuser, $cookie)
		= get_template_and_user({template_name => "catalogue/ISBDdetail.tmpl",
			     query => $query,
			     type => "intranet",
			     authnotrequired => 1,
			     debug => 1,
			     });

my $ISBD = C4::Context->preference('ISBD');
# my @blocs = split /\@/,$ISBD;
# my @fields = $record->fields();
my $res;
# foreach my $bloc (@blocs) {
# 	$bloc =~ s/\n//g;
	my $bloc = $ISBD;
	my $blocres;
	foreach my $isbdfield (split /#/,$bloc) {
# 		$isbdfield= /(.?.?.?)/;
		$isbdfield =~ /(\d\d\d)\|(.*)\|(.*)\|(.*)/;
		my $fieldvalue=$1;
		my $textbefore=$2;
		my $analysestring=$3;
		my $textafter=$4;
# 		warn "==> $1 / $2 / $3 / $4";
# 		my $fieldvalue=substr($isbdfield,0,3);
		if ($fieldvalue>0) {
	# 		warn "ERROR IN ISBD DEFINITION at : $isbdfield" unless $fieldvalue;
# 			warn "FV : $fieldvalue";
			my $hasputtextbefore=0;
			foreach my $field ($record->field($fieldvalue)) {
				my $calculated = $analysestring;
				my $tag = $field->tag();
				if ($tag<10) {
				} else {
					my @subf = $field->subfields;
					for my $i (0..$#subf) {
						my $subfieldcode = $subf[$i][0];
						my $subfieldvalue = get_authorised_value_desc($tag, $subf[$i][0], $subf[$i][1], '', $dbh);;
						my $tagsubf = $tag.$subfieldcode;
						$calculated =~ s/\{(.?.?.?)$tagsubf(.*?)\}/$1$subfieldvalue\{$1$tagsubf$2\}$2/g;
					}
					# field builded, store the result
					if ($calculated && !$hasputtextbefore) { # put textbefore if not done
						$blocres .=$textbefore;
						$hasputtextbefore=1
					}
					# remove punctuation at start
					$calculated =~ s/^( |;|:|\.|-)*//g;
					$blocres.=$calculated;
				}
			}
			$blocres .=$textafter if $hasputtextbefore;
		} else {
			$blocres.=$isbdfield;
		}
	}
	$res.=$blocres;
# }
$res =~ s/\{(.*?)\}//g;
$res =~ s/\\n/\n/g;
$res =~ s/\n/<br\/>/g;
# remove empty ()
$res =~ s/\(\)//g;
$template->param(ISBD => $res,
				biblionumber => $biblionumber);

output_html_with_http_headers $query, $cookie, $template->output;

sub get_authorised_value_desc ($$$$$) {
   my($tag, $subfield, $value, $framework, $dbh) = @_;

   #---- branch
    if ($tagslib->{$tag}->{$subfield}->{'authorised_value'} eq "branches" ) {
       return getbranchname($value);
    }

   #---- itemtypes
   if ($tagslib->{$tag}->{$subfield}->{'authorised_value'} eq "itemtypes" ) {
   		my $itemtypedef = getitemtypeinfo($itemtype);
       return $itemtypedef->{description};
    }

   #---- "true" authorized value
   my $category = $tagslib->{$tag}->{$subfield}->{'authorised_value'};

   if ($category ne "") {
       my $sth = $dbh->prepare("select lib from authorised_values where category = ? and authorised_value = ?");
       $sth->execute($category, $value);
       my $data = $sth->fetchrow_hashref;
       return $data->{'lib'};
   } else {
       return $value; # if nothing is found return the original value
   }
}
