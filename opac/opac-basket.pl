#!/usr/bin/perl
use strict;
require Exporter;
use CGI;
use C4::Search;
use C4::Auth;
use C4::Interface::CGI::Output;
use HTML::Template;

my $query=new CGI;

my ($template, $borrowernumber, $cookie)
    = get_template_and_user({template_name => "opac-basket.tmpl",
			     query => $query,
			     type => "opac",
			     authnotrequired => 1,
			     flagsrequired => {borrow => 1},
			 });


my $bib_list=$query->param('bib_list');
my $print_basket=$query->param('print');
my $verbose = $query->param('verbose');

if($verbose) { $template->param(verbose => 1); }
if ($print_basket) { $template->param(print_basket => 1); }

my @bibs = split(/\//, $bib_list);
my @results;

my $num = 1;
foreach my $biblionumber (@bibs) {
	$template->param(biblionumber => $biblionumber);

	my $dat                                   = &bibdata($biblionumber);
	my ($authorcount, $addauthor)             = &addauthor($biblionumber);

	$dat->{'additional'}=$addauthor->[0]->{'author'};
	for (my $i = 1; $i < $authorcount; $i++) {
			$dat->{'additional'} .= "|" . $addauthor->[$i]->{'author'};
	} # for
	if($num % 2 == 1){
		$dat->{'even'} = 1;
	}
	$num++;
	$dat->{'biblionumber'} = $biblionumber;
	
	push (@results, $dat);
}

my $resultsarray=\@results;

$template->param(BIBLIO_RESULTS => $resultsarray);

output_html_with_http_headers $query, $cookie, $template->output;
