#!/usr/bin/perl

use strict;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Context;
use HTML::Template;

my $query = new CGI;
my $quicksearch = $query->param('quicksearch');
my ($template, $loggedinuser, $cookie);
my $template_name;

if($quicksearch){
($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "members/member-quicksearch.tmpl",
			     query => $query,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {borrowers => 1},
			     debug => 1,
			     });
} else {
($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "members/members-home.tmpl",
			     query => $query,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {borrowers => 1},
			     debug => 1,
			     });
}

$template->param(intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
		);
output_html_with_http_headers $query, $cookie, $template->output;
