#!/usr/bin/perl

use strict;
use CGI;
use C4::Auth;
use C4::Koha;
use C4::Date;
use C4::Serials;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Context;
use HTML::Template;
use Date::Manip;

my $query = new CGI;
my $op = $query->param('op');
my $dbh = C4::Context->dbh;
my $sth;
# my $id;
my ($template, $loggedinuser, $cookie, $subs);
my ($subscriptionid,$auser,$librarian,$cost,$aqbooksellerid, $aqbooksellername,$aqbudgetid, $bookfundid, $startdate, $periodicity,
	$firstacquidate, $dow, $irregularity, $sublength, $subtype, $numberpattern, $numberlength, $weeklength, $monthlength,
	$add1,$every1,$whenmorethan1,$setto1,$lastvalue1,$innerloop1,
	$add2,$every2,$whenmorethan2,$setto2,$lastvalue2,$innerloop2,
	$add3,$every3,$whenmorethan3,$setto3,$lastvalue3,$innerloop3,
	$numberingmethod, $status, $biblionumber, $bibliotitle, $callnumber, $notes, $hemisphere);

$subscriptionid = $query->param('subscriptionid');

if ($op eq 'modsubscription') {
    my @irregular = $query->param('irregular');
    my $irregular_count = @irregular;
    for(my $i =0;$i<$irregular_count;$i++){
	$irregularity .=$irregular[$i]."|";
    }
    $irregularity =~ s/\|$//;

    
	$auser = $query->param('user');
	$librarian => $query->param('librarian'),
	$cost = $query->param('cost');
	$aqbooksellerid = $query->param('aqbooksellerid');
	$biblionumber = $query->param('biblionumber');
	$aqbudgetid = $query->param('aqbudgetid');
	$startdate = format_date_in_iso($query->param('startdate'));
	$firstacquidate = format_date_in_iso($query->param('firstacquidate'));    
	$periodicity = $query->param('periodicity');
	$dow = $query->param('dow');
        $sublength = $query->param('sublength');
        $subtype = $query->param('subtype');

        if($subtype eq 'months'){
	    $monthlength = $sublength;
	} elsif ($subtype eq 'weeks'){
	    $weeklength = $sublength;
	} else {
	    $numberlength = $sublength;
	}
        $numberpattern = $query->param('numbering_pattern');
	$add1 = $query->param('add1');
	$every1 = $query->param('every1');
	$whenmorethan1 = $query->param('whenmorethan1');
	$setto1 = $query->param('setto1');
	$lastvalue1 = $query->param('lastvalue1');
	$innerloop1 = $query->param('innerloop1');
	$add2 = $query->param('add2');
	$every2 = $query->param('every2');
	$whenmorethan2 = $query->param('whenmorethan2');
	$setto2 = $query->param('setto2');
	$lastvalue2 = $query->param('lastvalue2');
	$innerloop2 = $query->param('innerloop2');
	$add3 = $query->param('add3');
	$every3 = $query->param('every3');
	$whenmorethan3 = $query->param('whenmorethan3');
	$setto3 = $query->param('setto3');
	$lastvalue3 = $query->param('lastvalue3');
	$innerloop3 = $query->param('innerloop3');
	$numberingmethod = $query->param('numberingmethod');
	$status = 1;
        $callnumber = $query->param('callnumber');
	$notes = $query->param('notes');
        $hemisphere = $query->param('hemisphere');

	&ModSubscription($auser,$aqbooksellerid,$cost,$aqbudgetid,$startdate,
					$periodicity,$firstacquidate,$dow,$irregularity,$numberpattern,$numberlength,$weeklength,$monthlength,
					$add1,$every1,$whenmorethan1,$setto1,$lastvalue1,$innerloop1,
					$add2,$every2,$whenmorethan2,$setto2,$lastvalue2,$innerloop2,
					$add3,$every3,$whenmorethan3,$setto3,$lastvalue3,$innerloop3,
					$numberingmethod, $status, $biblionumber, $callnumber, $notes, $hemisphere, $subscriptionid);
}

if ($op eq 'del') {
	&DelSubscription($subscriptionid);
	print "Content-Type: text/html\n\n<META HTTP-EQUIV=Refresh CONTENT=\"0; URL=serials-home.pl\"></html>";
	exit;

}
my $subs = &GetSubscription($subscriptionid);
my ($routing, @routinglist) = getroutinglist($subscriptionid);
my ($totalissues,@serialslist) = old_getserials($subscriptionid);
$totalissues-- if $totalissues; # the -1 is to have 0 if this is a new subscription (only 1 issue)
# the subscription must be deletable if there is NO issues for a reason or another (should not happend, but...)

($template, $loggedinuser, $cookie)
= get_template_and_user({template_name => "serials/alt_subscription-detail.tmpl",
				query => $query,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {catalogue => 1},
				debug => 1,
				});

my ($user, $cookie, $sessionID, $flags)
	= checkauth($query, 0, {catalogue => 1}, "intranet");

my $weekarrayjs='';
my $count = 0;
my ($year, $month, $day) = UnixDate("today", "%Y", "%m", "%d");
my $firstday = Date_DayOfYear($month,$day,$year);
my $wkno = Date_WeekOfYear($month,$day,$year,1); # week starting monday
my $weekno = $wkno;
for(my $i=$firstday;$i<($firstday+365);$i=$i+7){
            $count = $i;
            if($wkno > 52){$year++; $wkno=1;}
            if($count>365){$count=$i-365;}
            my ($y,$m,$d) = Date_NthDayOfYear($year,$count);
            my $output = "$y-$m-$d";
            $weekarrayjs .= "'Wk $wkno: ".format_date($output)."',";
            $wkno++;
    }
chop($weekarrayjs);

$template->param(
        routing => $routing,
	user => $subs->{auser},
	librarian => $subs->{librarian},
	aqbooksellerid => $subs->{aqbooksellerid},
	aqbooksellername => $subs->{aqbooksellername},
	cost => $subs->{cost},
	aqbudgetid => $subs->{aqbudgetid},
	bookfundid => $subs->{bookfundid},
	startdate => format_date($subs->{startdate}),
	firstacquidate => format_date($subs->{firstacquidate}),    
	periodicity => $subs->{periodicity},
	dow => $subs->{dow},
        irregularity => $subs->{irregularity},
	numberlength => $subs->{numberlength},
	weeklength => $subs->{weeklength},
	monthlength => $subs->{monthlength},
        numberpattern => $subs->{numberpattern},
	add1 => $subs->{add1},
	every1 => $subs->{every1},
	whenmorethan1 => $subs->{whenmorethan1},
	innerloop1 => $subs->{innerloop1},
	setto1 => $subs->{setto1},
	lastvalue1 => $subs->{lastvalue1},
	add2 => $subs->{add2},
	every2 => $subs->{every2},
	whenmorethan2 => $subs->{whenmorethan2},
	setto2 => $subs->{setto2},
	lastvalue2 => $subs->{lastvalue2},
	innerloop2 => $subs->{innerloop2},
	add3 => $subs->{add3},
	every3 => $subs->{every3},
	whenmorethan3 => $subs->{whenmorethan3},
	setto3 => $subs->{setto3},
	lastvalue3 => $subs->{lastvalue3},
	innerloop3 => $subs->{innerloop3},
        weekarrayjs => $weekarrayjs,
	numberingmethod => $subs->{numberingmethod},
	status => $subs->{status},
	biblionumber => $subs->{biblionumber},
	bibliotitle => $subs->{bibliotitle},
        callnumber => $subs->{callnumber},
	notes => $subs->{notes},
	subscriptionid => $subs->{subscriptionid},
	serialslist => \@serialslist,
	totalissues => $totalissues,
        hemisphere => $hemisphere,
	);
$template->param(
			"periodicity$subs->{periodicity}" => 1,
			"arrival$subs->{dow}" => 1,
                        "numberpattern$subs->{numberpattern}" => 1,
			intranetstylesheet => C4::Context->preference("intranetstylesheet"),
			intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"), 
			);

output_html_with_http_headers $query, $cookie, $template->output;
