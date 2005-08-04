#!/usr/bin/perl

use strict;
use CGI;
use C4::Auth;
use C4::Koha;
use C4::Date;
use C4::Bull;
use C4::Letters;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Context;
use HTML::Template;

my $query = new CGI;
my $op = $query->param('op');
my $dbh = C4::Context->dbh;
my $selectview = $query->param('selectview');
$selectview = C4::Context->preference("SubscriptionHistory") unless $selectview;

my $sth;
# my $id;
my ($template, $loggedinuser, $cookie);
my $biblionumber = $query->param('biblionumber');
if ($selectview eq "full"){
	my $subscriptions = get_full_subscription_list_from_biblionumber($biblionumber);
	
	# now, check is there is an alert subscription for one of the subscriptions
	foreach (@$subscriptions) {
		if (getalert($loggedinuser,'issue',$_->{subscriptionid})) {
			warn "SUBSCRIPTION FOR : $loggedinuser,'issue',$_->{subscriptionid}";
		}
	}
	my $title = $subscriptions->[0]{bibliotitle};
	my $yearmin=$subscriptions->[0]{year};
	my $yearmax=$subscriptions->[scalar(@$subscriptions)-1]{year};
	
	
	($template, $loggedinuser, $cookie)
	= get_template_and_user({template_name => "opac-full-serial-issues.tmpl",
					query => $query,
					type => "opac",
					authnotrequired => 1,
					debug => 1,
					});
	
	# replace CR by <br> in librarian note
	# $subscription->{opacnote} =~ s/\n/\<br\/\>/g;
	
	$template->param(
		biblionumber => $query->param('biblionumber'),
		years => $subscriptions,
		yearmin => $yearmin,
		yearmax =>$yearmax,
		bibliotitle => $title,
		suggestion => C4::Context->preference("suggestion"),
		virtualshelves => C4::Context->preference("virtualshelves"),
		);

} else {
	my $subscriptions = get_subscription_list_from_biblionumber($biblionumber);
	
	# now, check is there is an alert subscription for one of the subscriptions
	foreach (@$subscriptions) {
		if (getalert($loggedinuser,'issue',$_->{subscriptionid})) {
			$_->{hasalert} = 1;
		}
	}
	
	($template, $loggedinuser, $cookie)
	= get_template_and_user({template_name => "opac-serial-issues.tmpl",
					query => $query,
					type => "opac",
					authnotrequired => 1,
					debug => 1,
					});
	
	# replace CR by <br> in librarian note
	# $subscription->{opacnote} =~ s/\n/\<br\/\>/g;
	
	$template->param(
		biblionumber => $query->param('biblionumber'),
		subscription_LOOP => $subscriptions,
		suggestion => C4::Context->preference("suggestion"),
		virtualshelves => C4::Context->preference("virtualshelves"),
		);
}
output_html_with_http_headers $query, $cookie, $template->output;
