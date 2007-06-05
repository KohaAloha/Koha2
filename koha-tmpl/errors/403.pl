#!/usr/bin/perl

use strict;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Context;


my $query = new CGI;
my $admin = C4::Context->preference('KohaAdminEmailAddress');
my ($template, $loggedinuser, $cookie)
= get_template_and_user({template_name => "errors/403.tmpl",
				query => $query,
				type => "intranet",
				authnotrequired => 1,
				debug => 1,
				});
$template->param( admin => $admin);				
output_html_with_http_headers $query, $cookie, $template->output;
