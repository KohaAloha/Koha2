#!/usr/bin/perl

# script to edit a member's flags
# Written by Steve Tonnesen
# July 26, 2002 (my birthday!)

use strict;

use CGI;
use C4::Output;
use C4::Auth;
use C4::Context;
use C4::Members;
#use C4::Acquisitions;

use C4::Interface::CGI::Output;

my $input = new CGI;

my $flagsrequired;
$flagsrequired->{borrowers}=1;
$flagsrequired->{permissions}=1;

my ($template, $loggedinuser, $cookie)
	= get_template_and_user({template_name => "members/member-flags.tmpl",
				query => $input,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {permissions => 1},
				debug => 1,
				});




my $member=$input->param('member');
my %member2;
$member2{'borrowernumber'}=$member;

if ($input->param('newflags')) {
    my $dbh=C4::Context->dbh();
    my $flags=0;
    foreach ($input->param) {
	if (/flag-(\d+)/) {
	    my $flag=$1;
	    $flags=$flags+2**$flag;
	}
    }
    my $sth=$dbh->prepare("update borrowers set flags=? where borrowernumber=?");
    $sth->execute($flags, $member);
    print $input->redirect("/cgi-bin/koha/members/moremember.pl?borrowernumber=$member");
} else {
#     my ($bor,$flags,$accessflags)=GetMemberDetails($member,'');
    my $bor = GetMemberDetails( $member,'');
    my $flags = $bor->{'flags'};
    my $accessflags = $bor->{'authflags'};
    my $dbh=C4::Context->dbh();
    my $sth=$dbh->prepare("select bit,flag,flagdesc from userflags order by bit");
    $sth->execute;
    my @loop;
    while (my ($bit, $flag, $flagdesc) = $sth->fetchrow) {
	my $checked='';
	if ($accessflags->{$flag}) {
	    $checked='checked';
	}
	my %row = ( bit => $bit,
		 flag => $flag,
		 checked => $checked,
		 flagdesc => $flagdesc );
	push @loop, \%row;
    }

    $template->param(member => $member,
			surname => $bor->{'surname'},
			firstname => $bor->{'firstname'},
			loop => \@loop,
			intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
			);

    output_html_with_http_headers $input, $cookie, $template->output;

}
