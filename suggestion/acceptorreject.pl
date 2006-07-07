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

# $Id$

use strict;
require Exporter;
use CGI;
use HTML::Template;
use C4::Auth;       # get_template_and_user
use C4::Interface::CGI::Output;
use C4::Suggestions;

my $input = new CGI;
my $title = $input->param('title');
my $author = $input->param('author');
my $note = $input->param('note');
my $copyrightdate =$input->param('copyrightdate');
my $publishercode = $input->param('publishercode');
my $volumedesc = $input->param('volumedesc');
my $publicationyear = $input->param('publicationyear');
my $place = $input->param('place');
my $isbn = $input->param('isbn');
my $status = $input->param('status');
my $suggestedbyme = $input->param('suggestedbyme');
my $op = $input->param('op');
$op = 'else' unless $op;

my $dbh = C4::Context->dbh;
my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "suggestion/acceptorreject.tmpl",
			     type => "intranet",
			     query => $input,
			     authnotrequired => 1,
			     flagsrequired => {borrow => 1},
			 });
if ($op eq "aorr_confirm") {
	my @suggestionlist = $input->param("aorr");
	foreach my $suggestion (@suggestionlist) {
		if ($suggestion =~ /(A|R)(.*)/) {
			my ($newstatus,$suggestionid) = ($1,$2);
			$newstatus="REJECTED" if $newstatus eq "R";
			$newstatus="ACCEPTED" if $newstatus eq "A";
			ModStatus($suggestionid,$newstatus,$loggedinuser);
		}
	}
	$op="else";
}

if ($op eq "delete_confirm") {
	my @delete_field = $input->param("delete_field");
	foreach my $delete_field (@delete_field) {
		&DelSuggestion($loggedinuser,$delete_field);
	}
	$op='else';
}

my $suggestions_loop= &SearchSuggestion("","","","",'ASKED',"");
$template->param(suggestions_loop => $suggestions_loop,
		"op_$op" => 1,
		intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
);
output_html_with_http_headers $input, $cookie, $template->output;
