#!/usr/bin/perl

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

# $Id$

=head1 pay.pl

 written 11/1/2000 by chris@katipo.oc.nz
 part of the koha library system, script to facilitate paying off fines

=cut

use strict;
use C4::Context;
use C4::Auth;
use C4::Output;
use CGI;
use C4::Members;
use C4::Accounts;
use C4::Stats;
use C4::Koha;
use C4::Overdues;
use C4::Branch; # GetBranches

my $input = new CGI;

my $borrowernumber = $input->param('borrowernumber');
if ( $borrowernumber eq '' ) {
    $borrowernumber = $input->param('borrowernumber0');
}

# get borrower details
my $data = borrdata( '', $borrowernumber );
my $user = $input->remote_user;

# get account details
my %bor;
$bor{'borrowernumber'} = $borrowernumber;
my $branches = GetBranches();
my $printers = GetPrinters();
my $branch   = GetBranch( $input, $branches );

my @names = $input->param;
my %inp;
my $check = 0;
for ( my $i = 0 ; $i < @names ; $i++ ) {
    my $temp = $input->param( $names[$i] );
    if ( $temp eq 'wo' ) {
        $inp{ $names[$i] } = $temp;
        $check = 1;
    }
    if ( $temp eq 'yes' ) {

# FIXME : using array +4, +5, +6 is dirty. Should use arrays for each accountline
        my $amount         = $input->param( $names[ $i + 4 ] );
        my $borrowernumber = $input->param( $names[ $i + 5 ] );
        my $accountno      = $input->param( $names[ $i + 6 ] );
        makepayment( $borrowernumber, $accountno, $amount, $user, $branch );
        $check = 2;
    }
}
my %env;

$env{'branchcode'} = $branch;
my $total = $input->param('total');
if ( $check == 0 ) {
    my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
        {
            template_name   => "members/pay.tmpl",
            query           => $input,
            type            => "intranet",
            authnotrequired => 0,
            flagsrequired   => { borrowers => 1 },
            debug           => 1,
        }
    );
    if ( $total ne '' ) {
        recordpayment( \%env, $borrowernumber, $total );
    }

    my ( $numaccts, $accts, $total ) = getboracctrecord( '', \%bor );

#       creation d'une fonction qui va nous retourner le notify_id dans un tableau

    my @allfile;
    my @notify = NumberNotifyId($borrowernumber);

    my $numberofnotify = scalar(@notify);
    for ( my $j = 0 ; $j < scalar(@notify) ; $j++ ) {
        my @loop_pay;
        my ( $numaccts, $accts, $total ) =
          GetBorNotifyAcctRecord( '', \%bor, $notify[$j] );
        for ( my $i = 0 ; $i < $numaccts ; $i++ ) {
            my %line;
            if ( $accts->[$i]{'amountoutstanding'} > 0 ) {
                $accts->[$i]{'amount'}            += 0.00;
                $accts->[$i]{'amountoutstanding'} += 0.00;
                $line{i}           = $j . "" . $i;
                $line{itemnumber}  = $accts->[$i]{'itemnumber'};
                $line{accounttype} = $accts->[$i]{'accounttype'};
                $line{amount}      = sprintf( "%.2f", $accts->[$i]{'amount'} );
                $line{amountoutstanding} =
                  sprintf( "%.2f", $accts->[$i]{'amountoutstanding'} );
                $line{borrowernumber} = $borrowernumber;
                $line{accountno}      = $accts->[$i]{'accountno'};
                $line{description}    = $accts->[$i]{'description'};
                $line{title}          = $accts->[$i]{'title'};
                $line{notify_id}      = $accts->[$i]{'notify_id'};
                $line{notify_level}   = $accts->[$i]{'notify_level'};

            }
            push( @loop_pay, \%line );
        }

        my $totalnotify = AmountNotify( $notify[$j] );
        ( $totalnotify = '0' ) if ( $totalnotify =~ /^0.00/ );
        push @allfile,
          {
            'loop_pay' => \@loop_pay,
            'notify'   => $notify[$j],
            'total'    => $totalnotify
          };
    }

    $template->param(
        allfile        => \@allfile,
        firstname      => $data->{'firstname'},
        surname        => $data->{'surname'},
        borrowernumber => $borrowernumber,
        total          => sprintf( "%.2f", $total )
    );
    print "Content-Type: text/html\n\n", $template->output;

}
else {

    my %inp;
    my @name = $input->param;
    for ( my $i = 0 ; $i < @name ; $i++ ) {
        my $test = $input->param( $name[$i] );
        if ( $test eq 'wo' ) {
            my $temp = $name[$i];
            $temp =~ s/payfine//;
            $inp{ $name[$i] } = $temp;
        }
    }
    my $borrowernumber;
    while ( my ( $key, $value ) = each %inp ) {

        my $accounttype = $input->param("accounttype$value");
        $borrowernumber = $input->param("borrowernumber$value");
        my $itemno    = $input->param("itemnumber$value");
        my $amount    = $input->param("amount$value");
        my $accountno = $input->param("accountno$value");
        writeoff( $borrowernumber, $accountno, $itemno, $accounttype, $amount );
    }
    $borrowernumber = $input->param('borrowernumber');
    print $input->redirect(
        "/cgi-bin/koha/members/moremember.pl?borrowernumber=$borrowernumber");
}

sub writeoff {
    my ( $borrowernumber, $accountnum, $itemnum, $accounttype, $amount ) = @_;
    my $user = $input->remote_user;
    my $dbh  = C4::Context->dbh;
    my $env;
    my $sth =
      $dbh->prepare(
"Update accountlines set amountoutstanding=0 where (accounttype='Res' OR accounttype='FU' OR accounttype ='IP' OR accounttype='CH' OR accounttype='N' OR accounttype='F' OR accounttype='A' OR accounttype='M' OR accounttype='L' OR accounttype='RE' OR accounttype='RL') and accountno=? and borrowernumber=?"
      );
    $sth->execute( $accountnum, $borrowernumber );
    $sth->finish;
    $sth = $dbh->prepare("select max(accountno) from accountlines");
    $sth->execute;
    my $account = $sth->fetchrow_hashref;
    $sth->finish;
    $account->{'max(accountno)'}++;
    $sth = $dbh->prepare(
"insert into accountlines (borrowernumber,accountno,itemnumber,date,amount,description,accounttype)
						values (?,?,?,now(),?,'Writeoff','W')"
    );
    $sth->execute( $borrowernumber, $account->{'max(accountno)'},
        $itemnum, $amount );
    $sth->finish;
    UpdateStats( $env, $branch, 'writeoff', $amount, '', '', '',
        $borrowernumber );
}
