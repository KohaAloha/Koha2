#!/usr/bin/perl

# $Id$

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
use C4::Context;
use C4::Output;
use CGI;
use C4::Branch; # GetBranches
use C4::Auth;
use C4::Date;
use C4::Circulation;
use C4::Reserves;
use C4::Members;
use Date::Calc qw(
  Today
  Add_Delta_Days
  Date_to_Days
);
use C4::Koha;
use C4::Biblio;

my $input = new CGI;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "circ/transferstodo.tmpl",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { circulate => 1 },
        debug           => 1,
    }
);

# set the userenv branch
my $default = C4::Context->userenv->{'branch'};

my @datearr    = localtime( time() );
my $todaysdate =
    ( 1900 + $datearr[5] ) . '-'
  . sprintf( "%0.2d", ( $datearr[4] + 1 ) ) . '-'
  . sprintf( "%0.2d", $datearr[3] );

my $item = $input->param('itemnumber');
my $fbr  = $input->param('fbr');
my $tbr  = $input->param('tbr');

# If we have a return of the form dotransfer, we launch the subroutine dotransfer
if ($item) {
    C4::Circulation::Circ2::dotransfer( $item, $fbr, $tbr );
}

# get the all the branches for reference
my $branches = GetBranches();

my @branchesloop;
foreach my $br ( keys %$branches ) {
    my @reservloop;
    my %branchloop;
    $branchloop{'branchname'} = $branches->{$br}->{'branchname'};
    $branchloop{'branchcode'} = $branches->{$br}->{'branchcode'};
    my @getreserves =
      GetReservesToBranch( $branches->{$br}->{'branchcode'} );
    if (@getreserves) {
        foreach my $num (@getreserves) {
            my %getreserv;
            my $gettitle     = GetBiblioFromItemNumber( $num->{'itemnumber'} );
#             use Data::Dumper;
#             warn Dumper($gettitle);
            warn "ITEM : ".$gettitle->{'title'};
            my $itemtypeinfo = getitemtypeinfo( $gettitle->{'itemtype'} );
            if ( $gettitle->{'holdingbranch'} eq $default ) {
                my $getborrower =
                  GetMemberDetails( $num->{'borrowernumber'} );
                $getreserv{'reservedate'} =
                  format_date( $num->{'reservedate'} );
                my ( $reserve_year, $reserve_month, $reserve_day ) = split /-/,
                  $num->{'reservedate'};
                ( $reserve_year, $reserve_month, $reserve_day ) =
                  Add_Delta_Days( $reserve_year, $reserve_month, $reserve_day,
                    C4::Context->preference('ReservesMaxPickUpDelay'));
                my $calcDate =
                  Date_to_Days( $reserve_year, $reserve_month, $reserve_day );
                my $today   = Date_to_Days(&Today);
                my $warning = ( $today > $calcDate );

                if ( $warning > 0 ) {
                    $getreserv{'messcompa'} = 1;
                }
                $getreserv{'title'}          = $gettitle->{'title'};
                $getreserv{'biblionumber'}   = $gettitle->{'biblionumber'};
                $getreserv{'itemnumber'}     = $gettitle->{'itemnumber'};
                $getreserv{'barcode'}        = $gettitle->{'barcode'};
                $getreserv{'itemtype'}       = $itemtypeinfo->{'description'};
                $getreserv{'holdingbranch'}  = $gettitle->{'holdingbranch'};
                $getreserv{'itemcallnumber'} = $gettitle->{'itemcallnumber'};
                $getreserv{'borrowernum'}    = $getborrower->{'borrowernumber'};
                $getreserv{'borrowername'}   = $getborrower->{'surname'};
                $getreserv{'borrowerfirstname'} = $getborrower->{'firstname'};
                $getreserv{'borrowermail'} = $getborrower->{'emailaddress'};
                $getreserv{'borrowerphone'} = $getborrower->{'phone'};
                push( @reservloop, \%getreserv );
                warn "=".$getreserv{'title'}.">>".$gettitle->{'title'};
            }
        }

      # 		If we have a return of reservloop we put it in the branchloop sequence
        if (@reservloop) {
            $branchloop{'reserv'} = \@reservloop;
        }

        # 		else, we unset the value of the branchcode .
        else {
            $branchloop{'branchcode'} = 0;
        }
    }
    else {

# 	if we don't have a retrun from reservestobranch we unset branchname and branchcode
        $branchloop{'branchname'} = 0;
        $branchloop{'branchcode'} = 0;
    }
    push( @branchesloop, \%branchloop );
}

$template->param(
    branchesloop => \@branchesloop,
    show_date    => format_date($todaysdate)
);

print "Content-Type: text/html\n\n", $template->output;

