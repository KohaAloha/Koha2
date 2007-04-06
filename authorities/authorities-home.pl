#!/usr/bin/perl
# WARNING: 4-character tab stops here

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
require Exporter;
use CGI;
use C4::Auth;

use C4::Context;
use C4::Auth;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::AuthoritiesMarc;
use C4::Acquisition;
use C4::Koha; # XXX subfield_is_koha_internal_p
use C4::Biblio;

my $query=new CGI;
my $op = $query->param('op');
my $authtypecode = $query->param('authtypecode');
my $dbh = C4::Context->dbh;

my $authid=$query->param('authid');
my ($template, $loggedinuser, $cookie);

my $authtypes = getauthtypes;
my @authtypesloop;
foreach my $thisauthtype (sort { $authtypes->{$a} <=> $authtypes->{$b} } keys %$authtypes) {
	my $selected = 1 if $thisauthtype eq $authtypecode;
	my %row =(value => $thisauthtype,
				selected => $selected,
				authtypetext => $authtypes->{$thisauthtype}{'authtypetext'},
			);
	push @authtypesloop, \%row;
}

if ($op eq "do_search") {
	my @marclist = $query->param('marclist');
	my @and_or = $query->param('and_or');
	my @excluding = $query->param('excluding');
	my @operator = $query->param('operator');
	my $orderby = $query->param('orderby');
	my @value = $query->param('value');

    my $startfrom = $query->param('startfrom') || 1;
    my $resultsperpage = $query->param('resultsperpage') || 19;

	my ($results,$total) = SearchAuthorities(
        \@marclist,
        \@and_or,
        \@excluding,
        \@operator,
        \@value,
        ($startfrom - 1)*$resultsperpage,
        $resultsperpage,
        $authtypecode,
        $orderby
    );

	($template, $loggedinuser, $cookie)
		= get_template_and_user({
            template_name => "authorities/searchresultlist.tmpl",
            query => $query,
            type => 'intranet',
            authnotrequired => 0,
            flagsrequired => {catalogue => 1},
            debug => 1,
        });

	my @field_data = ();

	# we must get parameters once again. Because if there is a mainentry, it
	# has been replaced by something else during the search, thus the links
	# next/previous would not work anymore
	my @marclist_ini = $query->param('marclist');
	for(my $i = 0 ; $i <= $#marclist ; $i++)
	{
		push @field_data, { term => "marclist"  , val=>$marclist_ini[$i] };
		push @field_data, { term => "and_or"    , val=>$and_or[$i] };
		push @field_data, { term => "excluding" , val=>$excluding[$i] };
		push @field_data, { term => "operator"  , val=>$operator[$i] };
		push @field_data, { term => "value"     , val=>$value[$i] };
	}

    # construction of the url of each page
    my $base_url =
        'authorities-home.pl?'
        .join(
            '&amp;',
            map { $_->{term}.'='.$_->{val} } @field_data
        )
        .'&amp;'
        .join(
            '&amp;',
            map { $_->{term}.'='.$_->{val} } (
                {term => 'resultsperpage', val => $resultsperpage},
                {term => 'type'          , val => 'intranet'},
                {term => 'op'            , val => 'do_search'},
                {term => 'authtypecode'  , val => $authtypecode},
                {term => 'orderby'       , val => $orderby},
            )
        )
        ;

	my $from = ($startfrom - 1) * $resultsperpage + 1;
	my $to;

 	if ($total < $startfrom * $resultsperpage) {
		$to = $total;
	}
    else {
		$to = $startfrom * $resultsperpage;
	}

	$template->param(result => $results) if $results;

	$template->param(
        pagination_bar => pagination_bar(
            $base_url,
            int($total/$resultsperpage)+1,
            $startfrom,
            'startfrom'
            ),
        total=>$total,
        from=>$from,
        to=>$to,
        isEDITORS => $authtypecode eq 'EDITORS',
    );

} elsif ($op eq "delete") {

	&DelAuthority($authid, 1);

	($template, $loggedinuser, $cookie)
		= get_template_and_user({template_name => "authorities/authorities-home.tmpl",
				query => $query,
				type => 'intranet',
				authnotrequired => 0,
				flagsrequired => {catalogue => 1},
				debug => 1,
				});
# 	$template->param("statements" => \@statements,
# 						"nbstatements" => $nbstatements);
}
elsif ($op eq "AddStatement") {

	($template, $loggedinuser, $cookie)
		= get_template_and_user({template_name => "authorities/authorities-home.tmpl",
				query => $query,
				type => 'intranet',
				authnotrequired => 0,
				flagsrequired => {catalogue => 1},
				debug => 1,
				});

	# Gets the entered information
	my @marcfields = $query->param('marclist');
	my @and_or = $query->param('and_or');
	my @excluding = $query->param('excluding');
	my @operator = $query->param('operator');
	my @value = $query->param('value');

	my @statements = ();

	# List of the marc tags to display
	my $marcarray = create_marclist();

	my $nbstatements = $query->param('nbstatements');
	$nbstatements = 1 if(!defined $nbstatements);

	for(my $i = 0 ; $i < $nbstatements ; $i++)
	{
		my %fields = ();

		# Recreates the old scrolling lists with the previously selected values
		my $marclist = create_scrolling_list({name=>"marclist",
					values=> $marcarray,
					size=> 1,
		 			-tabindex=>'',
					default=>$marcfields[$i],
					onChange => "sql_update()"}
					);

		$fields{'marclist'} = $marclist;
		$fields{'first'} = 1 if($i == 0);

		# Restores the and/or parameters (no need to test the 'and' for activation because it's the default value)
		$fields{'or'} = 1 if($and_or[$i] eq "or");

		#Restores the "not" parameters
		$fields{'not'} = 1 if($excluding[$i]);

		#Restores the operators (most common operators first);
		if($operator[$i] eq "=") { $fields{'eq'} = 1; }
		elsif($operator[$i] eq "contains") { $fields{'contains'} = 1; }
		elsif($operator[$i] eq "start") { $fields{'start'} = 1; }
		elsif($operator[$i] eq ">") { $fields{'gt'} = 1; }	#greater than
		elsif($operator[$i] eq ">=") { $fields{'ge'} = 1; } #greater or equal
		elsif($operator[$i] eq "<") { $fields{'lt'} = 1; } #lower than
		elsif($operator[$i] eq "<=") { $fields{'le'} = 1; } #lower or equal

		#Restores the value
		$fields{'value'} = $value[$i];

		push @statements, \%fields;
	}
	$nbstatements++;

	# The new scrolling list
	my $marclist = create_scrolling_list({name=>"marclist",
				values=> $marcarray,
				size=>1,
	 			-tabindex=>'',
				onChange => "sql_update()"});
	push @statements, {"marclist" => $marclist };

	$template->param("statements" => \@statements,
						"nbstatements" => $nbstatements);

}
else {
	($template, $loggedinuser, $cookie)
		= get_template_and_user({template_name => "authorities/authorities-home.tmpl",
				query => $query,
				type => 'intranet',
				authnotrequired => 0,
				flagsrequired => {catalogue => 1},
				debug => 1,
				});

}

$template->param(authtypesloop => \@authtypesloop,
		intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
		);

# Print the page
output_html_with_http_headers $query, $cookie, $template->output;

# Local Variables:
# tab-width: 4
# End:
