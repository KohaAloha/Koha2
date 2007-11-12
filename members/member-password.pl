#!/usr/bin/perl
#script to set the password, and optionally a userid, for a borrower
#written 2/5/00
#by chris@katipo.co.nz
#converted to using templates 3/16/03 by mwhansen@hmc.edu

use strict;
use C4::Auth;
use C4::Output;
use C4::Context;
use C4::Members;
use C4::Circulation;
use CGI;

use Digest::MD5 qw(md5_base64);

my $input = new CGI;

my $theme = $input->param('theme') || "default";
			# only used if allowthemeoverride is set

my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "members/member-password.tmpl",
			     query => $input,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {borrowers => 1},
			     debug => 1,
			     });

my $flagsrequired;
$flagsrequired->{borrowers}=1;
my ($loggedinuser, $cookie, $sessionID) = checkauth($input, 0, $flagsrequired);

my $member=$input->param('member');
my $cardnumber = $input->param('cardnumber');
my $destination = $input->param('destination');

my %member2;
$member2{'borrowernumber'}=$member;
# my $issues=GetBorrowerIssues(\%member2);
# my $i=0;
# foreach (sort keys %$issues) {
#     $i++;
# }

my ($bor,$flags)=GetMemberDetails( $member,'');
my $newpassword = $input->param('newpassword');

if ( $newpassword ) {
    my $digest=md5_base64($input->param('newpassword'));
    my $uid = $input->param('newuserid');
    my $dbh=C4::Context->dbh;
    warn $destination;
    if (changepassword($uid,$member,$digest)) {
	$template->param(newpassword => $newpassword);
	if ($destination eq 'circ') {
	    print $input->redirect("/cgi-bin/koha/circ/circulation.pl?findborrower=$cardnumber");		
	} 
	else {
	    print $input->redirect("/cgi-bin/koha/members/moremember.pl?borrowernumber=$member");
	}
    } 
    else {
        $template->param(othernames => $bor->{'othernames'},
						surname     => $bor->{'surname'},
						firstname   => $bor->{'firstname'},
						userid      => $bor->{'userid'},
						defaultnewpassword => $newpassword );
    }
} else {
    my $userid = $bor->{'userid'};

    my $chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    my $length=int(rand(2))+4;
    my $defaultnewpassword='';
    for (my $i=0; $i<$length; $i++) {
	$defaultnewpassword.=substr($chars, int(rand(length($chars))),1);
    }
    $template->param( othernames => $bor->{'othernames'},
	    surname     => $bor->{'surname'},
	    firstname   => $bor->{'firstname'},
	    borrowernumber => $bor->{'borrowernumber'},
	    cardnumber => $bor->{'cardnumber'},
	    categorycode => $bor->{'categorycode'},
	    category_type => $bor->{'category_type'},
	    category_description => $bor->{'description'},
	    address => $bor->{'address'},
	    address2 => $bor->{'address2'},
	    city => $bor->{'city'},
	    zipcode => $bor->{'zipcode'},
	    phone => $bor->{'phone'},
	    email => $bor->{'email'},
	    branchcode => $bor->{'branchcode'},
	    userid      => $bor->{'userid'},
	    destination => $destination,
	    defaultnewpassword => $defaultnewpassword 
	);


}

$template->param( member => $member);

output_html_with_http_headers $input, $cookie, $template->output;
