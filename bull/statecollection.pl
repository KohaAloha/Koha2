#!/usr/bin/perl

use strict;
use CGI;
use C4::Auth;
use C4::Date;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Context;
use C4::Bull;
use HTML::Template;

my $query = new CGI;
my $op = $query->param('op');
my $dbh = C4::Context->dbh;
my $subscriptionid = $query->param('subscriptionid');
my $auser = $query->param('user');
my $histstartdate = format_date_in_iso($query->param('histstartdate'));
my $enddate = format_date_in_iso($query->param('enddate'));
my $recievedlist = $query->param('recievedlist');
my $missinglist = $query->param('missinglist');
my $opacnote = $query->param('opacnote');
my $librariannote = $query->param('librariannote');
my @serialids = $query->param('serialid');
my @serialseqs = $query->param('serialseq');
my @planneddates = $query->param('planneddate');
my @notes = $query->param('notes');
my @status = $query->param('status');

my ($template, $loggedinuser, $cookie)
= get_template_and_user({template_name => "bull/statecollection.tmpl",
				query => $query,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {catalogue => 1},
				debug => 1,
				});

my $hassubscriptionexpired = hassubscriptionexpired($subscriptionid);
my $subscription=getsubscription($subscriptionid);
if ($op eq 'modsubscriptionhistory') {
	modsubscriptionhistory($subscriptionid,$histstartdate,$enddate,$recievedlist,$missinglist,$opacnote,$librariannote);
}
# change status except, if subscription has expired, for the "waited" issue.
if ($op eq 'serialchangestatus') {
	my $sth = $dbh->prepare("select status from serial where serialid=?");
	for (my $i=0;$i<=$#serialids;$i++) {
		$sth->execute($serialids[$i]);
		my ($oldstatus) = $sth->fetchrow;
		if ($serialids[$i]) {
			serialchangestatus($serialids[$i],$serialseqs[$i],format_date_in_iso($planneddates[$i]),$status[$i],$notes[$i]) unless ($hassubscriptionexpired && $oldstatus == 1);
		} else {
			# add a special issue
			if ($serialseqs[$i]) {
				my $subscription=getsubscription($subscriptionid);
				newissue($serialseqs[$i],$subscriptionid,$subscription->{biblionumber},$status[$i], format_date_in_iso($planneddates[$i]));
			}
		}
	}
}
my $subs = &getsubscription($subscriptionid);
my ($totalissues,@serialslist) = getserials($subscriptionid,10);

my $sth=$dbh->prepare("select * from subscriptionhistory where subscriptionid = ?");
$sth->execute($subscriptionid);
my $solhistory = $sth->fetchrow_hashref;

	$template->param(
			serialslist => \@serialslist,
			biblionumber => $subscription->{biblionumber},
			histstartdate => format_date($solhistory->{'histstartdate'}),
			enddate => format_date($solhistory->{'enddate'}),
			recievedlist => $solhistory->{'recievedlist'},
			missinglist => $solhistory->{'missinglist'},
			opacnote => $solhistory->{'opacnote'},
			librariannote => $solhistory->{'librariannote'},
			subscriptionid => $subscriptionid,
			bibliotitle => $subs->{bibliotitle},
			biblionumber => $subs->{biblionumber},
			hassubscriptionexpired =>$hassubscriptionexpired,
		);
output_html_with_http_headers $query, $cookie, $template->output;
