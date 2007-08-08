#!/usr/bin/perl

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
use CGI;
use C4::Auth;
use C4::Koha;
use C4::Date;
use C4::Serials;
use C4::Output;
use C4::Context;
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
    $numberingmethod, $status, $biblionumber, $bibliotitle, $callnumber, $notes, $hemisphere,$letter,$manualhistory,$histstartdate,$enddate,$missinglist,$recievedlist,$opacnote,$librariannote);

$subscriptionid = $query->param('subscriptionid');


if ($op eq 'del') {
    &DelSubscription($subscriptionid);
    print "Content-Type: text/html\n\n<META HTTP-EQUIV=Refresh CONTENT=\"0; URL=serials-home.pl\"></html>";
    exit;

}
my $subs = &GetSubscription($subscriptionid);
# use Data::Dumper; warn $subscriptionid; warn Dumper($subs);
my ($routing, @routinglist) = getroutinglist($subscriptionid);
my ($totalissues,@serialslist) = GetSerials($subscriptionid);
$totalissues-- if $totalissues; # the -1 is to have 0 if this is a new subscription (only 1 issue)
# the subscription must be deletable if there is NO issues for a reason or another (should not happend, but...)

($template, $loggedinuser, $cookie)
= get_template_and_user({template_name => "serials/subscription-detail.tmpl",
                query => $query,
                type => "intranet",
                authnotrequired => 0,
                flagsrequired => {serials => 1},
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

# COMMENT hdl : IMHO, we should think about passing more and more data hash to template->param rather than duplicating code a new coding Guideline ?
$subs->{startdate}=format_date($subs->{startdate});
$subs->{firstacquidate}=format_date($subs->{firstacquidate});
$subs->{histstartdate}=format_date($subs->{histstartdate});
$subs->{enddate}=format_date($subs->{enddate});
$subs->{abouttoexpire}=abouttoexpire($subs->{subscriptionid});

$template->param($subs);

$template->param(
    routing => $routing,
    serialslist => \@serialslist,
    totalissues => $totalissues,
    hemisphere => $hemisphere,
    );
$template->param(
            "periodicity".$subs->{periodicity} => 1,
            "arrival".$subs->{dow} => 1,
            "numberpattern".$subs->{numberpattern} => 1,
            intranetstylesheet => C4::Context->preference("intranetstylesheet"),
            intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"), 
            );

output_html_with_http_headers $query, $cookie, $template->output;
