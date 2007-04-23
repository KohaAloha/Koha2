#!/usr/bin/perl

# Please use 8-character tabs for this file (indents are every 4 characters)

# written 8/5/2002 by Finlay
# script to execute issuing of books

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
use CGI;
use C4::Output;
use C4::Print;
use C4::Auth;
use C4::Date;
use C4::Interface::CGI::Output;
use C4::Branch; # GetBranches
use C4::Koha;   # GetPrinter
use Date::Calc qw(
  Today
  Today_and_Now
  Add_Delta_YM
  Add_Delta_Days
  Date_to_Days
);

use C4::Circulation;
use C4::Members;
use C4::Biblio;
use C4::Reserves;

#
# PARAMETERS READING
#
my $query = new CGI;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user (
    {
        template_name   => 'circ/circulation.tmpl',
        query           => $query,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { circulate => 1 },
    }
);
my $branches = GetBranches();

my $printers = GetPrinters();
my $printer = GetPrinter($query, $printers);

my $findborrower = $query->param('findborrower');
$findborrower =~ s|,| |g;
#$findborrower =~ s|'| |g;
my $borrowernumber = $query->param('borrowernumber');

# new op dev the branch and the printer are now defined by the userenv
my $branch  = C4::Context->userenv->{'branch'};
my $printer = C4::Context->userenv->{'branchprinter'};

# If Autolocated is not activated, we show the Circulation Parameters to chage settings of librarian
    if (C4::Context->preference("AutoLocation") ne 1)
        {
            $template->param(
            ManualLocation => 1,
            );
        }

my $barcode        = $query->param('barcode') || '';
my $year           = $query->param('year');
my $month          = $query->param('month');
my $day            = $query->param('day');
my $stickyduedate  = $query->param('stickyduedate');
my $issueconfirmed = $query->param('issueconfirmed');
my $cancelreserve  = $query->param('cancelreserve');
my $organisation   = $query->param('organisations');
my $print          = $query->param('print');

#set up cookie.....
# my $branchcookie;
# my $printercookie;
# if ($query->param('setcookies')) {
#     $branchcookie = $query->cookie(-name=>'branch', -value=>"$branch", -expires=>'+1y');
#     $printercookie = $query->cookie(-name=>'printer', -value=>"$printer", -expires=>'+1y');
# }
#


my @datearr = localtime( time() );

# FIXME - Could just use POSIX::strftime("%Y%m%d", localtime);
my $todaysdate =
    ( 1900 + $datearr[5] )
  . sprintf( "%0.2d", ( $datearr[4] + 1 ) )
  . sprintf( "%0.2d", ( $datearr[3] ) );

# check and see if we should print
if ( $barcode eq '' && $print eq 'maybe' ) {
    $print = 'yes';
}

my $inprocess = $query->param('inprocess');
if ( $barcode eq '' ) {
    $inprocess = '';
}
else {
}

if ( $barcode eq '' && $query->param('charges') eq 'yes' ) {
    $template->param(
        PAYCHARGES     => 'yes',
        borrowernumber => $borrowernumber
    );
}

if ( $print eq 'yes' && $borrowernumber ne '' ) {
    printslip( $borrowernumber );
    $query->param( 'borrowernumber', '' );
    $borrowernumber = '';
}

#
# STEP 2 : FIND BORROWER
# if there is a list of find borrowers....
#
my $borrowerslist;
my $message;
if ($findborrower) {
    my ( $count, $borrowers ) =
      SearchBorrower($findborrower, 'cardnumber', 'web' );
    my @borrowers = @$borrowers;
    if ( $#borrowers == -1 ) {
        $query->param( 'findborrower', '' );
        $message = "'$findborrower'";
    }
    elsif ( $#borrowers == 0 ) {
        $query->param( 'borrowernumber', $borrowers[0]->{'borrowernumber'} );
        $query->param( 'barcode',           '' );
        $borrowernumber = $borrowers[0]->{'borrowernumber'};
    }
    else {
        $borrowerslist = \@borrowers;
    }
}

# get the borrower information.....
my $borrower;
my @lines;

if ($borrowernumber) {
    $borrower = GetMemberDetails( $borrowernumber, 0 );
    my ( $od, $issue, $fines ) = GetBorrowerIssuesAndFines( $borrowernumber );

    # Warningdate is the date that the warning starts appearing
    my ( $today_year,   $today_month,   $today_day )   = Today();
    my ( $warning_year, $warning_month, $warning_day ) = split /-/,
      $borrower->{'dateexpiry'};

    # Renew day is calculated by adding the enrolment period to today
    my ( $renew_year, $renew_month, $renew_day ) =
      Add_Delta_YM( $today_year, $today_month, $today_day,
        $borrower->{'enrolmentperiod'}, 0 );
    # if the expiry date is before today
    if ( Date_to_Days( $today_year, $today_month, $today_day ) >
        Date_to_Days( $warning_year, $warning_month, $warning_day ) )
    {

        #borrowercard expired or nearly expired, warn the librarian
        $template->param(
            flagged       => "1",
            warndeparture => "1",
            renewaldate   => "$renew_year-$renew_month-$renew_day"
        );
    }
    # check for NotifyBorrowerDeparture
        if (C4::Context->preference('NotifyBorrowerDeparture') &&
            Date_to_Days(Add_Delta_Days($warning_year,$warning_month,$warning_day,- C4::Context->preference('NotifyBorrowerDeparture'))) <
            Date_to_Days( $today_year, $today_month, $today_day ) ) 
        {
            $template->param("warndeparture" => 1);
        }
    $template->param(
        overduecount => $od,
        issuecount   => $issue,
        finetotal    => $fines
    );
}

#
# STEP 3 : ISSUING
#
#

if ($barcode) {
    $barcode = cuecatbarcodedecode($barcode);
    my ( $datedue, $invalidduedate ) = fixdate( $year, $month, $day );
    if ($issueconfirmed) {
        AddIssue( $borrower, $barcode, $datedue, $cancelreserve );
        $inprocess = 1;
    }
    else {
        my ( $error, $question ) =
          CanBookBeIssued( $borrower, $barcode, $year, $month, $day,
            $inprocess );
        my $noerror    = 1;
        my $noquestion = 1;
#         Get the item title for more information
    my $getmessageiteminfo  = GetBiblioFromItemNumber( undef, $barcode );
    
        foreach my $impossible ( keys %$error ) {
            $template->param(
                $impossible => $$error{$impossible},
                IMPOSSIBLE  => 1
            );
            $noerror = 0;
        }
        foreach my $needsconfirmation ( keys %$question ) {
            $template->param(
                $needsconfirmation => $$question{$needsconfirmation},
                getTitleMessageIteminfo => $getmessageiteminfo->{'title'},
                NEEDSCONFIRMATION  => 1
            );
            $noquestion = 0;
        }
        $template->param(
            day   => $day,
            month => $month,
            year  => $year
        );
        if ( $noerror && ( $noquestion || $issueconfirmed ) ) {
            AddIssue( $borrower, $barcode, $datedue );
            $inprocess = 1;
        }
    }
    
# FIXME If the issue is confirmed, we launch another time borrdata2, now display the issue count after issue 
        my ( $od, $issue, $fines ) = GetBorrowerIssuesAndFines( $borrowernumber );
        $template->param(
        issuecount   => $issue,
        );
}

# reload the borrower info for the sake of reseting the flags.....
if ($borrowernumber) {
    $borrower = GetMemberDetails( $borrowernumber, 0 );
}

##################################################################################
# BUILD HTML
# show all reserves of this borrower, and the position of the reservation ....
if ($borrowernumber) {

    # new op dev
    # now we show the status of the borrower's reservations
    my @borrowerreserv = GetReservations( 0, $borrowernumber );
    my @reservloop;
    my @WaitingReserveLoop;
    
    foreach my $num_res (@borrowerreserv) {
        my %getreserv;
        my %getWaitingReserveInfo;
        my $getiteminfo  = GetBiblioFromItemNumber( $num_res->{'itemnumber'} );
        my $itemtypeinfo = getitemtypeinfo( $getiteminfo->{'itemtype'} );
        my ( $transfertwhen, $transfertfrom, $transfertto ) =
          GetTransfers( $num_res->{'itemnumber'} );

        $getreserv{waiting}       = 0;
        $getreserv{transfered}    = 0;
        $getreserv{nottransfered} = 0;

        $getreserv{reservedate}    = format_date( $num_res->{'reservedate'} );
        $getreserv{biblionumber}   = $getiteminfo->{'biblionumber'};
        $getreserv{title}          = $getiteminfo->{'title'};
        $getreserv{itemtype}       = $itemtypeinfo->{'description'};
        $getreserv{author}         = $getiteminfo->{'author'};
        $getreserv{barcodereserv}  = $getiteminfo->{'barcode'};
        $getreserv{itemcallnumber} = $getiteminfo->{'itemcallnumber'};

        #         check if we have a waiting status for reservations
        if ( $num_res->{'found'} eq 'W' ) {
            $getreserv{color}   = 'reserved';
            $getreserv{waiting} = 1;
#     genarate information displaying only waiting reserves
        $getWaitingReserveInfo{title}        = $getiteminfo->{'title'};
        $getWaitingReserveInfo{itemtype}    = $itemtypeinfo->{'description'};
        $getWaitingReserveInfo{author}        = $getiteminfo->{'author'};
        $getWaitingReserveInfo{reservedate}    = format_date( $num_res->{'reservedate'} );
        if ($getiteminfo->{'holdingbranch'} ne $num_res->{'branchcode'} ) {
        $getWaitingReserveInfo{waitingat}    = GetBranchName( $num_res->{'branchcode'} );
        }
    
        }
        #         check transfers with the itemnumber foud in th reservation loop
        if ($transfertwhen) {
            $getreserv{color}      = 'transfered';
            $getreserv{transfered} = 1;
            $getreserv{datesent}   = format_date($transfertwhen);
            $getreserv{frombranch} = GetBranchName($transfertfrom);
        }

        if ( ( $getiteminfo->{'holdingbranch'} ne $num_res->{'branchcode'} )
            and not $transfertwhen )
        {
            $getreserv{nottransfered}   = 1;
            $getreserv{nottransferedby} =
              GetBranchName( $getiteminfo->{'holdingbranch'} );
        }

#         if we don't have a reserv on item, we put the biblio infos and the waiting position
        if ( $getiteminfo->{'title'} eq '' ) {
            my $getbibinfo = GetBiblioItemData( $num_res->{'biblionumber'} );
            my $getbibtype = getitemtypeinfo( $getbibinfo->{'itemtype'} );
            $getreserv{color}           = 'inwait';
            $getreserv{title}           = $getbibinfo->{'title'};
            $getreserv{waitingposition} = $num_res->{'priority'};
            $getreserv{nottransfered}   = 0;
            $getreserv{itemtype}        = $getbibtype->{'description'};
            $getreserv{author}          = $getbibinfo->{'author'};
            $getreserv{itemcallnumber}  = '----------';

        }
        push( @reservloop, \%getreserv );

#         if we have a reserve waiting, initiate waitingreserveloop
        if ($getreserv{waiting} eq 1) {
        push (@WaitingReserveLoop, \%getWaitingReserveInfo)
        }
      
    }

    # return result to the template
    $template->param( 
        countreserv => scalar @reservloop,
        reservloop  => \@reservloop ,
        WaitingReserveLoop  => \@WaitingReserveLoop,
    );
}

# make the issued books table.
my $todaysissues = '';
my $previssues   = '';
my @realtodayissues;
my @realprevissues;
my $allowborrow;
## ADDED BY JF: new itemtype issuingrules counter stuff
my $issued_itemtypes_loop;
my $issued_itemtypes_count;
my $issued_itemtypes_allowed_count;    # hashref with total allowed by itemtype
my $issued_itemtypes_remaining;        # hashref with remaining
my $issued_itemtypes_flags;            #hashref that stores flags

if ($borrower) {

# get each issue of the borrower & separate them in todayissues & previous issues
    my @todaysissues;
    my @previousissues;
    my $issueslist = GetBorrowerIssues($borrower);

    # split in 2 arrays for today & previous
    my $dbh = C4::Context->dbh;
    foreach my $it ( @$issueslist ) {
        my $issuedate = $it->{'timestamp'};
        $issuedate =~ s/-//g;
        $issuedate = substr( $issuedate, 0, 8 );

        # to let perl sort this correctly
        $it->{'timestamp'} =~ s/(-|\:| )//g;

        if ( $todaysdate == $issuedate ) {
            (
                $it->{'charge'},
                $it->{'itemtype_charge'}
              )
              = GetIssuingCharges(
                $it->{'itemnumber'},
                $borrower->{'borrowernumber'}
              );
            $it->{'charge'} =
              sprintf( "%.2f", $it->{'charge'} );
            (
                $it->{'can_renew'},
                $it->{'can_renew_error'}
              )
              = CanBookBeRenewed(
                $borrower->{'borrowernumber'},
                $it->{'itemnumber'}
              );
            my ( $restype, $reserves ) =
              CheckReserves( $it->{'itemnumber'} );
            if ($restype) {
                $it->{'can_renew'} = 0;
            }
            push @todaysissues, $it;
        }
        else {
            (
                $it->{'charge'},
                $it->{'itemtype_charge'}
              )
              = GetIssuingCharges(
                $it->{'itemnumber'},
                $borrower->{'borrowernumber'}
              );
            $it->{'charge'} =
              sprintf( "%.2f", $it->{'charge'} );
            (
                $it->{'can_renew'},
                $it->{'can_renew_error'}
              )
              = CanBookBeRenewed(
                $borrower->{'borrowernumber'},
                $it->{'itemnumber'}
              );
            my ( $restype, $reserves ) =
              CheckReserves( $it->{'itemnumber'} );
            if ($restype) {
                $it->{'can_renew'} = 0;
            }
            push @previousissues, $it;
        }
    }
    my $od;    # overdues
    my $i = 0;
    my $togglecolor;

    # parses today & build Template array
    foreach my $book ( sort { $b->{'timestamp'} <=> $a->{'timestamp'} }
        @todaysissues )
    {
        #warn "TIMESTAMP".$book->{'timestamp'};
        # ADDED BY JF: NEW ITEMTYPE COUNT DISPLAY
        $issued_itemtypes_count->{ $book->{'itemtype'} }++;

        my $dd      = $book->{'date_due'};
        my $datedue = $book->{'date_due'};

        #$dd=format_date($dd);
        $datedue =~ s/-//g;
        if ( $datedue < $todaysdate ) {
            $od = 1;
        }
        else {
            $od = 0;
        }
        if ( $i % 2 ) {
            $togglecolor = 0;
        }
        else {
            $togglecolor = 1;
        }
        $book->{'togglecolor'} = $togglecolor;
        $book->{'od'}          = format_date($od);
        $book->{'dd'}          = format_date($dd);
        if ( $book->{'author'} eq '' ) {
            $book->{'author'} = ' ';
        }
        push @realtodayissues, $book;
        $i++;
    }

    # parses previous & build Template array
    $i = 0;
    foreach my $book ( sort { $a->{'date_due'} cmp $b->{'date_due'} }
        @previousissues )
    {

        # ADDED BY JF: NEW ITEMTYPE COUNT DISPLAY
        $issued_itemtypes_count->{ $book->{'itemtype'} }++;

        my $dd      = format_date($book->{'date_due'});
        my $datedue = format_date($book->{'date_due'});

        #$dd=format_date($dd);
        my $pcolor = '';
        my $od     = '';
        $datedue =~ s/-//g;
        if ( $datedue < $todaysdate ) {
            $od = 1;
        }
        else {
            $od = 0;
        }
        if ( $i % 2 ) {
            $togglecolor = 0;
        }
        else {
            $togglecolor = 1;
        }
        $book->{'togglecolor'} = $togglecolor;
        $book->{'dd'}          = $dd;
        $book->{'od'}          = $od;
        if ( $book->{'author'} eq '' ) {
            $book->{'author'} = ' ';
        }
        push @realprevissues, $book;
        $i++;
    }
}

#### ADDED BY JF FOR COUNTS BY ITEMTYPE RULES
# FIXME: This should utilize all the issuingrules options rather than just the defaults
# and it should be moved to a module
my $dbh = C4::Context->dbh;

# how many of each is allowed?
my $issueqty_sth = $dbh->prepare( "
SELECT itemtypes.description AS description,issuingrules.itemtype,maxissueqty
FROM issuingrules
  LEFT JOIN itemtypes ON (itemtypes.itemtype=issuingrules.itemtype)
  WHERE categorycode=?
" );
my @issued_itemtypes_count;
$issueqty_sth->execute("*");
while ( my $data = $issueqty_sth->fetchrow_hashref() ) {

    # subtract how many of each this borrower has
    $data->{'count'} = $issued_itemtypes_count->{ $data->{'description'} };
    $data->{'left'}  =
      ( $data->{'maxissueqty'} -
          $issued_itemtypes_count->{ $data->{'description'} } );

    # can't have a negative number of remaining
    if ( $data->{'left'} < 0 ) { $data->{'left'} = "0" }
    $data->{'flag'} = 1 unless ( $data->{'maxissueqty'} > $data->{'count'} );
    unless ( ( $data->{'maxissueqty'} < 1 )
        || ( $data->{'itemtype'} eq "*" )
        || ( $data->{'itemtype'} eq "CIRC" ) )
    {
        push @issued_itemtypes_count, $data;
    }
}
$issued_itemtypes_loop = \@issued_itemtypes_count;

#### / JF

my @values;
my %labels;
my $CGIselectborrower;
if ($borrowerslist) {
    foreach (
        sort {
                $a->{'surname'}
              . $a->{'firstname'} cmp $b->{'surname'}
              . $b->{'firstname'}
        } @$borrowerslist
      )
    {
        push @values, $_->{'borrowernumber'};
        $labels{ $_->{'borrowernumber'} } =
"$_->{'surname'}, $_->{'firstname'} ... ($_->{'cardnumber'} - $_->{'categorycode'}) ...  $_->{'address'} ";
    }
    $CGIselectborrower = CGI::scrolling_list(
        -name     => 'borrowernumber',
        -values   => \@values,
        -labels   => \%labels,
        -size     => 7,
        -tabindex => '',
        -multiple => 0
    );
}

#title
my $flags = $borrower->{'flags'};
my $flag;

foreach $flag ( sort keys %$flags ) {

    $flags->{$flag}->{'message'} =~ s/\n/<br>/g;
    if ( $flags->{$flag}->{'noissues'} ) {
        $template->param(
            flagged  => 1,
            noissues => 'true',
        );
        if ( $flag eq 'GNA' ) {
            $template->param( gna => 'true' );
        }
        if ( $flag eq 'LOST' ) {
            $template->param( lost => 'true' );
        }
        if ( $flag eq 'DBARRED' ) {
            $template->param( dbarred => 'true' );
        }
        if ( $flag eq 'CHARGES' ) {
            $template->param(
                charges    => 'true',
                chargesmsg => $flags->{'CHARGES'}->{'message'}
            );
        }
        if ( $flag eq 'CREDITS' ) {
            $template->param(
                credits    => 'true',
                creditsmsg => $flags->{'CREDITS'}->{'message'}
            );
        }
    }
    else {
        if ( $flag eq 'CHARGES' ) {
            $template->param(
                charges    => 'true',
                flagged    => 1,
                chargesmsg => $flags->{'CHARGES'}->{'message'}
            );
        }
        if ( $flag eq 'CREDITS' ) {
            $template->param(
                credits    => 'true',
                creditsmsg => $flags->{'CREDITS'}->{'message'}
            );
        }
        if ( $flag eq 'ODUES' ) {
            $template->param(
                odues    => 'true',
                flagged  => 1,
                oduesmsg => $flags->{'ODUES'}->{'message'}
            );

            my $items = $flags->{$flag}->{'itemlist'};
# useless ???
#             {
#                 my @itemswaiting;
#                 foreach my $item (@$items) {
#                     my ($iteminformation) =
#                         getiteminformation( $item->{'itemnumber'}, 0 );
#                     push @itemswaiting, $iteminformation;
#                 }
#             }
            if ( $query->param('module') ne 'returns' ) {
                $template->param( nonreturns => 'true' );
            }
        }
        if ( $flag eq 'NOTES' ) {
            $template->param(
                notes    => 'true',
                flagged  => 1,
                notesmsg => $flags->{'NOTES'}->{'message'}
            );
        }
    }
}

my $amountold = $borrower->{flags}->{'CHARGES'}->{'message'} || 0;
my @temp = split( /\$/, $amountold );

my $CGIorganisations;
my $member_of_institution;
if ( C4::Context->preference("memberofinstitution") ) {
    my $organisations = get_institutions();
    my @orgs;
    my %org_labels;
    foreach my $organisation ( keys %$organisations ) {
        push @orgs, $organisation;
        $org_labels{$organisation} =
          $organisations->{$organisation}->{'surname'};
    }
    $member_of_institution = 1;
    $CGIorganisations      = CGI::popup_menu(
        -id     => 'organisations',
        -name   => 'organisations',
        -labels => \%org_labels,
        -values => \@orgs,
    );
}

$amountold = $temp[1];

$template->param(
    issued_itemtypes_count_loop => $issued_itemtypes_loop,
    findborrower                => $findborrower,
    borrower                    => $borrower,
    borrowernumber              => $borrowernumber,
    branch                      => $branch,
    printer                     => $printer,
    printername                 => $printer,
    firstname                   => $borrower->{'firstname'},
    surname                     => $borrower->{'surname'},
    expiry                      =>
      $borrower->{'dateexpiry'},    #format_date($borrower->{'dateexpiry'}),
    categorycode      => $borrower->{'categorycode'},
    streetaddress     => $borrower->{'address'},
    emailaddress      => $borrower->{'emailaddress'},
    borrowernotes     => $borrower->{'borrowernotes'},
    city              => $borrower->{'city'},
    phone             => $borrower->{'phone'},
    cardnumber        => $borrower->{'cardnumber'},
    amountold         => $amountold,
    barcode           => $barcode,
    stickyduedate     => $stickyduedate,
    message           => $message,
    CGIselectborrower => $CGIselectborrower,
    todayissues       => \@realtodayissues,
    previssues        => \@realprevissues,
    inprocess         => $inprocess,
    memberofinstution => $member_of_institution,
    CGIorganisations  => $CGIorganisations,
);

# set return date if stickyduedate
if ($stickyduedate) {
    my $t_year  = "year" . $year;
    my $t_month = "month" . $month;
    my $t_day   = "day" . $day;
    $template->param(
        $t_year  => 1,
        $t_month => 1,
        $t_day   => 1,
    );
}

#if ($branchcookie) {
#$cookie=[$cookie, $branchcookie, $printercookie];
#}

$template->param(
    SpecifyDueDate     => C4::Context->preference("SpecifyDueDate")
);
output_html_with_http_headers $query, $cookie, $template->output;
