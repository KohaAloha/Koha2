package C4::Circulation;

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
require Exporter;
use C4::Context;
use C4::Stats;
use C4::Reserves;
use C4::Koha;
use C4::Biblio;
use C4::Items;
use C4::Members;
use C4::Dates;
use Date::Calc qw(
  Today
  Today_and_Now
  Add_Delta_YM
  Add_Delta_DHMS
  Date_to_Days
  Day_of_Week
  Add_Delta_Days	
);
use POSIX qw(strftime);
use C4::Branch; # GetBranches
use C4::Log; # logaction

use Data::Dumper;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

BEGIN {
	# set the version for version checking
	$VERSION = 3.01;
	@ISA    = qw(Exporter);

	# FIXME subs that should probably be elsewhere
	push @EXPORT, qw(
		&FixOverduesOnReturn
		&cuecatbarcodedecode
	);

	# subs to deal with issuing a book
	push @EXPORT, qw(
		&CanBookBeIssued
		&CanBookBeRenewed
		&AddIssue
		&AddRenewal
		&GetRenewCount
		&GetItemIssue
		&GetItemIssues
		&GetBorrowerIssues
		&GetIssuingCharges
		&GetBiblioIssues
		&AnonymiseIssueHistory
	);

	# subs to deal with returns
	push @EXPORT, qw(
		&AddReturn
	);

	# subs to deal with transfers
	push @EXPORT, qw(
		&transferbook
		&GetTransfers
		&GetTransfersFromTo
		&updateWrongTransfer
		&DeleteTransfer
	);
}

=head1 NAME

C4::Circulation - Koha circulation module

=head1 SYNOPSIS

use C4::Circulation;

=head1 DESCRIPTION

The functions in this module deal with circulation, issues, and
returns, as well as general information about the library.
Also deals with stocktaking.

=head1 FUNCTIONS

=head2 decode

=head3 $str = &decode($chunk);

=over 4

=item Decodes a segment of a string emitted by a CueCat barcode scanner and
returns it.

=back

=cut

# FIXME - At least, I'm pretty sure this is for decoding CueCat stuff.
# FIXME From Paul : i don't understand what this sub does & why it has to be called on every circ. Speak of this with chris maybe ?

sub cuecatbarcodedecode {
    my ($barcode) = @_;
    chomp($barcode);
    my @fields = split( /\./, $barcode );
    my @results = map( decode($_), @fields[ 1 .. $#fields ] );
    if ( $#results == 2 ) {
        return $results[2];
    }
    else {
        return $barcode;
    }
}

=head2 decode

=head3 $str = &decode($chunk);

=over 4

=item Decodes a segment of a string emitted by a CueCat barcode scanner and
returns it.

=back

=cut

sub decode {
    my ($encoded) = @_;
    my $seq =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-';
    my @s = map { index( $seq, $_ ); } split( //, $encoded );
    my $l = ( $#s + 1 ) % 4;
    if ($l) {
        if ( $l == 1 ) {
            warn "Error!";
            return;
        }
        $l = 4 - $l;
        $#s += $l;
    }
    my $r = '';
    while ( $#s >= 0 ) {
        my $n = ( ( $s[0] << 6 | $s[1] ) << 6 | $s[2] ) << 6 | $s[3];
        $r .=
            chr( ( $n >> 16 ) ^ 67 )
         .chr( ( $n >> 8 & 255 ) ^ 67 )
         .chr( ( $n & 255 ) ^ 67 );
        @s = @s[ 4 .. $#s ];
    }
    $r = substr( $r, 0, length($r) - $l );
    return $r;
}

=head2 transferbook

($dotransfer, $messages, $iteminformation) = &transferbook($newbranch, $barcode, $ignore_reserves);

Transfers an item to a new branch. If the item is currently on loan, it is automatically returned before the actual transfer.

C<$newbranch> is the code for the branch to which the item should be transferred.

C<$barcode> is the barcode of the item to be transferred.

If C<$ignore_reserves> is true, C<&transferbook> ignores reserves.
Otherwise, if an item is reserved, the transfer fails.

Returns three values:

=head3 $dotransfer 

is true if the transfer was successful.

=head3 $messages

is a reference-to-hash which may have any of the following keys:

=over 4

=item C<BadBarcode>

There is no item in the catalog with the given barcode. The value is C<$barcode>.

=item C<IsPermanent>

The item's home branch is permanent. This doesn't prevent the item from being transferred, though. The value is the code of the item's home branch.

=item C<DestinationEqualsHolding>

The item is already at the branch to which it is being transferred. The transfer is nonetheless considered to have failed. The value should be ignored.

=item C<WasReturned>

The item was on loan, and C<&transferbook> automatically returned it before transferring it. The value is the borrower number of the patron who had the item.

=item C<ResFound>

The item was reserved. The value is a reference-to-hash whose keys are fields from the reserves table of the Koha database, and C<biblioitemnumber>. It also has the key C<ResFound>, whose value is either C<Waiting> or C<Reserved>.

=item C<WasTransferred>

The item was eligible to be transferred. Barring problems communicating with the database, the transfer should indeed have succeeded. The value should be ignored.

=back

=cut

sub transferbook {
    my ( $tbr, $barcode, $ignoreRs ) = @_;
    my $messages;
    my $dotransfer      = 1;
    my $branches        = GetBranches();
    my $itemnumber = GetItemnumberFromBarcode( $barcode );
    my $issue      = GetItemIssue($itemnumber);
    my $biblio = GetBiblioFromItemNumber($itemnumber);

    # bad barcode..
    if ( not $itemnumber ) {
        $messages->{'BadBarcode'} = $barcode;
        $dotransfer = 0;
    }

    # get branches of book...
    my $hbr = $biblio->{'homebranch'};
    my $fbr = $biblio->{'holdingbranch'};

    # if is permanent...
    if ( $hbr && $branches->{$hbr}->{'PE'} ) {
        $messages->{'IsPermanent'} = $hbr;
    }

    # can't transfer book if is already there....
    if ( $fbr eq $tbr ) {
        $messages->{'DestinationEqualsHolding'} = 1;
        $dotransfer = 0;
    }

    # check if it is still issued to someone, return it...
    if ($issue->{borrowernumber}) {
        AddReturn( $barcode, $fbr );
        $messages->{'WasReturned'} = $issue->{borrowernumber};
    }

    # find reserves.....
    # That'll save a database query.
    my ( $resfound, $resrec ) =
      CheckReserves( $itemnumber );
    if ( $resfound and not $ignoreRs ) {
        $resrec->{'ResFound'} = $resfound;

        #         $messages->{'ResFound'} = $resrec;
        $dotransfer = 1;
    }

    #actually do the transfer....
    if ($dotransfer) {
        ModItemTransfer( $itemnumber, $fbr, $tbr );

        # don't need to update MARC anymore, we do it in batch now
        $messages->{'WasTransfered'} = 1;
		ModDateLastSeen( $itemnumber );
    }
    return ( $dotransfer, $messages, $biblio );
}

=head2 CanBookBeIssued

Check if a book can be issued.

my ($issuingimpossible,$needsconfirmation) = CanBookBeIssued($borrower,$barcode,$year,$month,$day);

=over 4

=item C<$borrower> hash with borrower informations (from GetMemberDetails)

=item C<$barcode> is the bar code of the book being issued.

=item C<$year> C<$month> C<$day> contains the date of the return (in case it's forced by "stickyduedate".

=back

Returns :

=over 4

=item C<$issuingimpossible> a reference to a hash. It contains reasons why issuing is impossible.
Possible values are :

=back

=head3 INVALID_DATE 

sticky due date is invalid

=head3 GNA

borrower gone with no address

=head3 CARD_LOST

borrower declared it's card lost

=head3 DEBARRED

borrower debarred

=head3 UNKNOWN_BARCODE

barcode unknown

=head3 NOT_FOR_LOAN

item is not for loan

=head3 WTHDRAWN

item withdrawn.

=head3 RESTRICTED

item is restricted (set by ??)

C<$issuingimpossible> a reference to a hash. It contains reasons why issuing is impossible.
Possible values are :

=head3 DEBT

borrower has debts.

=head3 RENEW_ISSUE

renewing, not issuing

=head3 ISSUED_TO_ANOTHER

issued to someone else.

=head3 RESERVED

reserved for someone else.

=head3 INVALID_DATE

sticky due date is invalid

=head3 TOO_MANY

if the borrower borrows to much things

=cut

# check if a book can be issued.


sub TooMany {
    my $borrower        = shift;
    my $biblionumber = shift;
	my $item		= shift;
    my $cat_borrower    = $borrower->{'categorycode'};
    my $dbh             = C4::Context->dbh;
	my $branch;
	# Get which branchcode we need
	if (C4::Context->preference('CircControl') eq 'PickupLibary'){
		$branch = C4::Context->userenv->{'branch'}; 
	}
	elsif (C4::Context->preference('CircControl') eq 'PatronLibary'){
        $branch = $borrower->{'branchcode'}; 
	}
	else {
		# items home library
		$branch = $item->{'homebranch'};
	}
	my $type = (C4::Context->preference('item-level_itypes')) 
  			? $item->{'itype'}         # item-level
			: $item->{'itemtype'};     # biblio-level
  
	my $sth =
      $dbh->prepare(
                'SELECT * FROM issuingrules 
                        WHERE categorycode = ? 
                            AND itemtype = ? 
                            AND branchcode = ?'
      );

    my $query2 = "SELECT  COUNT(*) FROM issues i, biblioitems s1, items s2 
                WHERE i.borrowernumber = ? 
                    AND i.returndate IS NULL 
                    AND i.itemnumber = s2.itemnumber 
                    AND s1.biblioitemnumber = s2.biblioitemnumber";
    if (C4::Context->preference('item-level_itypes')){
	   $query2.=" AND s2.itype=? ";
    } else { 
	   $query2.=" AND s1.itemtype= ? ";
    }
    my $sth2=  $dbh->prepare($query2);
    my $sth3 =
      $dbh->prepare(
            'SELECT COUNT(*) FROM issues
                WHERE borrowernumber = ?
                    AND returndate IS NULL'
            );
    my $alreadyissued;

    # check the 3 parameters (branch / itemtype / category code
    $sth->execute( $cat_borrower, $type, $branch );
    my $result = $sth->fetchrow_hashref;
#     warn "$cat_borrower, $type, $branch = ".Data::Dumper::Dumper($result);

    if ( $result->{maxissueqty} ne '' ) {
#         warn "checking on everything set";
        $sth2->execute( $borrower->{'borrowernumber'}, $type );
        my $alreadyissued = $sth2->fetchrow;
        if ( $result->{'maxissueqty'} <= $alreadyissued ) {
            return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on branch/category/itemtype failed)" );
        }
        # now checking for total
        $sth->execute( $cat_borrower, '*', $branch );
        my $result = $sth->fetchrow_hashref;
        if ( $result->{maxissueqty} ne '' ) {
            $sth2->execute( $borrower->{'borrowernumber'}, $type );
            my $alreadyissued = $sth2->fetchrow;
            if ( $result->{'maxissueqty'} <= $alreadyissued ) {
                return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on branch/category/total failed)"  );
            }
        }
    }

    # check the 2 parameters (branch / itemtype / default categorycode
    $sth->execute( '*', $type, $branch );
    $result = $sth->fetchrow_hashref;
#     warn "*, $type, $branch = ".Data::Dumper::Dumper($result);

    if ( $result->{maxissueqty} ne '' ) {
#         warn "checking on 2 parameters (default categorycode)";
        $sth2->execute( $borrower->{'borrowernumber'}, $type );
        my $alreadyissued = $sth2->fetchrow;
        if ( $result->{'maxissueqty'} <= $alreadyissued ) {
            return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on branch / default category / itemtype failed)"  );
        }
        # now checking for total
        $sth->execute( '*', '*', $branch );
        my $result = $sth->fetchrow_hashref;
        if ( $result->{maxissueqty} ne '' ) {
            $sth2->execute( $borrower->{'borrowernumber'}, $type );
            my $alreadyissued = $sth2->fetchrow;
            if ( $result->{'maxissueqty'} <= $alreadyissued ) {
                return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on branch / default category / total failed)" );
            }
        }
    }
    
    # check the 1 parameters (default branch / itemtype / categorycode
    $sth->execute( $cat_borrower, $type, '*' );
    $result = $sth->fetchrow_hashref;
#     warn "$cat_borrower, $type, * = ".Data::Dumper::Dumper($result);
    
    if ( $result->{maxissueqty} ne '' ) {
#         warn "checking on 1 parameter (default branch + categorycode)";
        $sth2->execute( $borrower->{'borrowernumber'}, $type );
        my $alreadyissued = $sth2->fetchrow;
        if ( $result->{'maxissueqty'} <= $alreadyissued ) {
            return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on default branch/category/itemtype failed)"  );
        }
        # now checking for total
        $sth->execute( $cat_borrower, '*', '*' );
        my $result = $sth->fetchrow_hashref;
        if ( $result->{maxissueqty} ne '' ) {
            $sth2->execute( $borrower->{'borrowernumber'}, $type );
            my $alreadyissued = $sth2->fetchrow;
            if ( $result->{'maxissueqty'} <= $alreadyissued ) {
                return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on default branch / category / total failed)"  );
            }
        }
    }

    # check the 0 parameters (default branch / itemtype / default categorycode
    $sth->execute( '*', $type, '*' );
    $result = $sth->fetchrow_hashref;
#     warn "*, $type, * = ".Data::Dumper::Dumper($result);

    if ( $result->{maxissueqty} ne '' ) {
#         warn "checking on default branch and default categorycode";
        $sth2->execute( $borrower->{'borrowernumber'}, $type );
        my $alreadyissued = $sth2->fetchrow;
        if ( $result->{'maxissueqty'} <= $alreadyissued ) {
            return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on default branch / default category / itemtype failed)"  );
        }
	}
    # now checking for total
    $sth->execute( '*', '*', '*' );
    $result = $sth->fetchrow_hashref;
    if ( $result->{maxissueqty} ne '' ) {
		warn "checking total";
		$sth2->execute( $borrower->{'borrowernumber'}, $type );
		my $alreadyissued = $sth2->fetchrow;
		if ( $result->{'maxissueqty'} <= $alreadyissued ) {
			return ( "$alreadyissued / ".( $result->{maxissueqty} + 0 )." (rule on default branch / default category / total failed)"  );
		}
	}

    # OK, the patron can issue !!!
    return;
}

=head2 itemissues

  @issues = &itemissues($biblioitemnumber, $biblio);

Looks up information about who has borrowed the bookZ<>(s) with the
given biblioitemnumber.

C<$biblio> is ignored.

C<&itemissues> returns an array of references-to-hash. The keys
include the fields from the C<items> table in the Koha database.
Additional keys include:

=over 4

=item C<date_due>

If the item is currently on loan, this gives the due date.

If the item is not on loan, then this is either "Available" or
"Cancelled", if the item has been withdrawn.

=item C<card>

If the item is currently on loan, this gives the card number of the
patron who currently has the item.

=item C<timestamp0>, C<timestamp1>, C<timestamp2>

These give the timestamp for the last three times the item was
borrowed.

=item C<card0>, C<card1>, C<card2>

The card number of the last three patrons who borrowed this item.

=item C<borrower0>, C<borrower1>, C<borrower2>

The borrower number of the last three patrons who borrowed this item.

=back

=cut

#'
sub itemissues {
    my ( $bibitem, $biblio ) = @_;
    my $dbh = C4::Context->dbh;
    my $sth =
      $dbh->prepare("Select * from items where items.biblioitemnumber = ?")
      || die $dbh->errstr;
    my $i = 0;
    my @results;

    $sth->execute($bibitem) || die $sth->errstr;

    while ( my $data = $sth->fetchrow_hashref ) {

        # Find out who currently has this item.
        # FIXME - Wouldn't it be better to do this as a left join of
        # some sort? Currently, this code assumes that if
        # fetchrow_hashref() fails, then the book is on the shelf.
        # fetchrow_hashref() can fail for any number of reasons (e.g.,
        # database server crash), not just because no items match the
        # search criteria.
        my $sth2 = $dbh->prepare(
            "SELECT * FROM issues
                LEFT JOIN borrowers ON issues.borrowernumber = borrowers.borrowernumber
                WHERE itemnumber = ?
                    AND returndate IS NULL
            "
        );

        $sth2->execute( $data->{'itemnumber'} );
        if ( my $data2 = $sth2->fetchrow_hashref ) {
            $data->{'date_due'} = $data2->{'date_due'};
            $data->{'card'}     = $data2->{'cardnumber'};
            $data->{'borrower'} = $data2->{'borrowernumber'};
        }
        else {
            $data->{'date_due'} = ($data->{'wthdrawn'} eq '1') ? 'Cancelled' : 'Available';
        }

        $sth2->finish;

        # Find the last 3 people who borrowed this item.
        $sth2 = $dbh->prepare(
            "SELECT * FROM issues
                LEFT JOIN borrowers ON  issues.borrowernumber = borrowers.borrowernumber
                WHERE itemnumber = ?
                AND returndate IS NOT NULL
                ORDER BY returndate DESC,timestamp DESC"
        );

        $sth2->execute( $data->{'itemnumber'} );
        for ( my $i2 = 0 ; $i2 < 2 ; $i2++ )
        {    # FIXME : error if there is less than 3 pple borrowing this item
            if ( my $data2 = $sth2->fetchrow_hashref ) {
                $data->{"timestamp$i2"} = $data2->{'timestamp'};
                $data->{"card$i2"}      = $data2->{'cardnumber'};
                $data->{"borrower$i2"}  = $data2->{'borrowernumber'};
            }    # if
        }    # for

        $sth2->finish;
        $results[$i] = $data;
        $i++;
    }

    $sth->finish;
    return (@results);
}

=head2 CanBookBeIssued

( $issuingimpossible, $needsconfirmation ) = 
        CanBookBeIssued( $borrower, $barcode, $duedatespec, $inprocess );
C<$duedatespec> is a C4::Dates object.
C<$issuingimpossible> and C<$needsconfirmation> are some hashref.

=cut

sub CanBookBeIssued {
    my ( $borrower, $barcode, $duedate, $inprocess ) = @_;
    my %needsconfirmation;    # filled with problems that needs confirmations
    my %issuingimpossible;    # filled with problems that causes the issue to be IMPOSSIBLE
    my $item = GetItem(GetItemnumberFromBarcode( $barcode ));
    my $issue = GetItemIssue($item->{itemnumber});
	my $biblioitem = GetBiblioItemData($item->{biblioitemnumber});
	$item->{'itemtype'}=$biblioitem->{'itemtype'};
    my $dbh             = C4::Context->dbh;

    #
    # DUE DATE is OK ? -- should already have checked.
    #
    #$issuingimpossible{INVALID_DATE} = 1 unless ($duedate);

    #
    # BORROWER STATUS
    #
    if ( $borrower->{flags}->{GNA} ) {
        $issuingimpossible{GNA} = 1;
    }
    if ( $borrower->{flags}->{'LOST'} ) {
        $issuingimpossible{CARD_LOST} = 1;
    }
    if ( $borrower->{flags}->{'DBARRED'} ) {
        $issuingimpossible{DEBARRED} = 1;
    }
    if ( $borrower->{'dateexpiry'} eq '0000-00-00') {
        $issuingimpossible{EXPIRED} = 1;
    } else {
        my @expirydate=  split /-/,$borrower->{'dateexpiry'};
        if($expirydate[0]==0 || $expirydate[1]==0|| $expirydate[2]==0 ||
            Date_to_Days(Today) > Date_to_Days( @expirydate )) {
            $issuingimpossible{EXPIRED} = 1;                                   
        }
    }
    #
    # BORROWER STATUS
    #

    # DEBTS
    my ($amount) =
      C4::Members::GetMemberAccountRecords( $borrower->{'borrowernumber'}, '' && $duedate->output('iso') );
    if ( C4::Context->preference("IssuingInProcess") ) {
        my $amountlimit = C4::Context->preference("noissuescharge");
        if ( $amount > $amountlimit && !$inprocess ) {
            $issuingimpossible{DEBT} = sprintf( "%.2f", $amount );
        }
        elsif ( $amount <= $amountlimit && !$inprocess ) {
            $needsconfirmation{DEBT} = sprintf( "%.2f", $amount );
        }
    }
    else {
        if ( $amount > 0 ) {
            $needsconfirmation{DEBT} = $amount;
        }
    }

    #
    # JB34 CHECKS IF BORROWERS DONT HAVE ISSUE TOO MANY BOOKS
    #
	my $toomany = TooMany( $borrower, $item->{biblionumber}, $item );
    $needsconfirmation{TOO_MANY} = $toomany if $toomany;

    #
    # ITEM CHECKING
    #
    unless ( $item->{barcode} ) {
        $issuingimpossible{UNKNOWN_BARCODE} = 1;
    }
    if (   $item->{'notforloan'}
        && $item->{'notforloan'} > 0 )
    {
        $issuingimpossible{NOT_FOR_LOAN} = 1;
    }
	elsif ( !$item->{'notforloan'} ){
		# we have to check itemtypes.notforloan also
		if (C4::Context->preference('item-level_itypes')){
			# this should probably be a subroutine
			my $sth = $dbh->prepare("SELECT notforloan FROM itemtypes WHERE itemtype = ?");
			$sth->execute($item->{'itemtype'});
			my $notforloan=$sth->fetchrow_hashref();
			$sth->finish();
			if ($notforloan->{'notforloan'} == 1){
				$issuingimpossible{NOT_FOR_LOAN} = 1;				
			}
		}
		elsif ($biblioitem->{'notforloan'} == 1){
			$issuingimpossible{NOT_FOR_LOAN} = 1;
		}
	}
    if ( $item->{'wthdrawn'} && $item->{'wthdrawn'} == 1 )
    {
        $issuingimpossible{WTHDRAWN} = 1;
    }
    if (   $item->{'restricted'}
        && $item->{'restricted'} == 1 )
    {
        $issuingimpossible{RESTRICTED} = 1;
    }
    if ( C4::Context->preference("IndependantBranches") ) {
        my $userenv = C4::Context->userenv;
        if ( ($userenv) && ( $userenv->{flags} != 1 ) ) {
            $issuingimpossible{NOTSAMEBRANCH} = 1
              if ( $item->{C4::Context->preference("HomeOrHoldingbranch")} ne $userenv->{branch} );
        }
    }

    #
    # CHECK IF BOOK ALREADY ISSUED TO THIS BORROWER
    #
    if ( $issue->{borrowernumber} && $issue->{borrowernumber} eq $borrower->{'borrowernumber'} )
    {

        # Already issued to current borrower. Ask whether the loan should
        # be renewed.
        my ($CanBookBeRenewed,$renewerror) = CanBookBeRenewed(
            $borrower->{'borrowernumber'},
            $item->{'itemnumber'}
        );
        if ( $CanBookBeRenewed == 0 ) {    # no more renewals allowed
            $issuingimpossible{NO_MORE_RENEWALS} = 1;
        }
        else {
            $needsconfirmation{RENEW_ISSUE} = 1;
        }
    }
    elsif ($issue->{borrowernumber}) {

        # issued to someone else
        my $currborinfo = GetMemberDetails( $issue->{borrowernumber} );

#        warn "=>.$currborinfo->{'firstname'} $currborinfo->{'surname'} ($currborinfo->{'cardnumber'})";
        $needsconfirmation{ISSUED_TO_ANOTHER} =
"$currborinfo->{'reservedate'} : $currborinfo->{'firstname'} $currborinfo->{'surname'} ($currborinfo->{'cardnumber'})";
    }

    # See if the item is on reserve.
    my ( $restype, $res ) = C4::Reserves::CheckReserves( $item->{'itemnumber'} );
    if ($restype) {
		my $resbor = $res->{'borrowernumber'};
		my ( $resborrower, $flags ) = GetMemberDetails( $resbor, 0 );
		my $branches  = GetBranches();
		my $branchname = $branches->{ $res->{'branchcode'} }->{'branchname'};
        if ( $resbor ne $borrower->{'borrowernumber'} && $restype eq "Waiting" )
        {
            # The item is on reserve and waiting, but has been
            # reserved by some other patron.
            $needsconfirmation{RESERVE_WAITING} =
"$resborrower->{'firstname'} $resborrower->{'surname'} ($resborrower->{'cardnumber'}, $branchname)";
        }
        elsif ( $restype eq "Reserved" ) {
            # The item is on reserve for someone else.
            $needsconfirmation{RESERVED} =
"$res->{'reservedate'} : $resborrower->{'firstname'} $resborrower->{'surname'} ($resborrower->{'cardnumber'})";
        }
    }
    if ( C4::Context->preference("LibraryName") eq "Horowhenua Library Trust" ) {
        if ( $borrower->{'categorycode'} eq 'W' ) {
            my %emptyhash;
            return ( \%emptyhash, \%needsconfirmation );
        }
	}
	return ( \%issuingimpossible, \%needsconfirmation );
}

=head2 AddIssue

Issue a book. Does no check, they are done in CanBookBeIssued. If we reach this sub, it means the user confirmed if needed.

&AddIssue($borrower,$barcode,$date)

=over 4

=item C<$borrower> hash with borrower informations (from GetMemberDetails)

=item C<$barcode> is the bar code of the book being issued.

=item C<$date> contains the max date of return. calculated if empty.

AddIssue does the following things :
- step 01: check that there is a borrowernumber & a barcode provided
- check for RENEWAL (book issued & being issued to the same patron)
    - renewal YES = Calculate Charge & renew
    - renewal NO  = 
        * BOOK ACTUALLY ISSUED ? do a return if book is actually issued (but to someone else)
        * RESERVE PLACED ?
            - fill reserve if reserve to this patron
            - cancel reserve or not, otherwise
        * TRANSFERT PENDING ?
            - complete the transfert
        * ISSUE THE BOOK

=back

=cut

sub AddIssue {
    my ( $borrower, $barcode, $date, $cancelreserve ) = @_;
    my $dbh = C4::Context->dbh;
	my $barcodecheck=CheckValidBarcode($barcode);
	if ($borrower and $barcode and $barcodecheck ne '0'){
		# find which item we issue
		my $item = GetItem('', $barcode);
		my $datedue; 
		
		my $branch;
		# Get which branchcode we need
		if (C4::Context->preference('CircControl') eq 'PickupLibary'){
			$branch = C4::Context->userenv->{'branchcode'}; 
		}
		elsif (C4::Context->preference('CircControl') eq 'PatronLibary'){
			$branch = $borrower->{'branchcode'}; 
		}
		else {
			# items home library
			$branch = $item->{'homebranch'};
		}
		
		# get actual issuing if there is one
		my $actualissue = GetItemIssue( $item->{itemnumber});
		
		# get biblioinformation for this item
		my $biblio = GetBiblioFromItemNumber($item->{itemnumber});
		
		#
		# check if we just renew the issue.
		#
		if ( $actualissue->{borrowernumber} eq $borrower->{'borrowernumber'} ) {
			AddRenewal(
				$borrower->{'borrowernumber'},
				$item->{'itemnumber'},
				$branch,
				$date
			);

		}
		else {
        # it's NOT a renewal
			if ( $actualissue->{borrowernumber}) {
				# This book is currently on loan, but not to the person
				# who wants to borrow it now. mark it returned before issuing to the new borrower
				AddReturn(
					$item->{'barcode'},
					C4::Context->userenv->{'branch'}
				);
			}

			# See if the item is on reserve.
			my ( $restype, $res ) =
			  C4::Reserves::CheckReserves( $item->{'itemnumber'} );
			if ($restype) {
				my $resbor = $res->{'borrowernumber'};
				if ( $resbor eq $borrower->{'borrowernumber'} ) {

					# The item is reserved by the current patron
					ModReserveFill($res);
				}
				elsif ( $restype eq "Waiting" ) {

					# warn "Waiting";
					# The item is on reserve and waiting, but has been
					# reserved by some other patron.
					my ( $resborrower, $flags ) = GetMemberDetails( $resbor, 0 );
					my $branches   = GetBranches();
					my $branchname =
					  $branches->{ $res->{'branchcode'} }->{'branchname'};
				}
				elsif ( $restype eq "Reserved" ) {

					# warn "Reserved";
					# The item is reserved by someone else.
					my ( $resborrower, $flags ) =
					  GetMemberDetails( $resbor, 0 );
					my $branches   = GetBranches();
					my $branchname =  $branches->{ $res->{'branchcode'} }->{'branchname'};
					if ($cancelreserve) { # cancel reserves on this item
						CancelReserve( 0, $res->{'itemnumber'},
							$res->{'borrowernumber'} );
					}
				}
				if ($cancelreserve) {
					CancelReserve( $res->{'biblionumber'}, 0,
                    $res->{'borrowernumber'} );
				}
				else {
					# set waiting reserve to first in reserve queue as book isn't waiting now
					ModReserve(1,
						$res->{'biblionumber'},
						$res->{'borrowernumber'},
						$res->{'branchcode'}
					);
				}
			}

			# Starting process for transfer job (checking transfert and validate it if we have one)
            my ($datesent) = GetTransfers($item->{'itemnumber'});
            if ($datesent) {
        # 	updating line of branchtranfert to finish it, and changing the to branch value, implement a comment for lisibility of this case (maybe for stats ....)
            my $sth =
                    $dbh->prepare(
                    "UPDATE branchtransfers 
                        SET datearrived = now(),
                        tobranch = ?,
                        comments = 'Forced branchtransfert'
                    WHERE itemnumber= ? AND datearrived IS NULL"
                    );
                    $sth->execute(C4::Context->userenv->{'branch'},$item->{'itemnumber'});
                    $sth->finish;
            }

        # Record in the database the fact that the book was issued.
        my $sth =
          $dbh->prepare(
                "INSERT INTO issues 
                    (borrowernumber, itemnumber,issuedate, date_due, branchcode)
                VALUES (?,?,?,?,?)"
          );
		my $dateduef;
        if ($date) {
            $dateduef = $date;
        } else {
			my $itype=(C4::Context->preference('item-level_itypes')) ?  $biblio->{'itype'} : $biblio->{'itemtype'} ;
        	my $loanlength = GetLoanLength(
        	    $borrower->{'categorycode'},
        	    $itype,
                $branch
        	);
        	$datedue  = time + ($loanlength) * 86400;
        	my @datearr  = localtime($datedue);
			$dateduef = C4::Dates->new( sprintf("%04d-%02d-%02d", 1900 + $datearr[5], $datearr[4] + 1, $datearr[3]), 'iso');
			$dateduef=CheckValidDatedue($dateduef,$item->{'itemnumber'},C4::Context->userenv->{'branch'});
		
		# if ReturnBeforeExpiry ON the datedue can't be after borrower expirydate
        	if ( C4::Context->preference('ReturnBeforeExpiry') && $dateduef->output('iso') gt $borrower->{dateexpiry} ) {
        	    $dateduef = C4::Dates->new($borrower->{dateexpiry},'iso');
        	}
        };
		$sth->execute(
            $borrower->{'borrowernumber'},
            $item->{'itemnumber'},
            strftime( "%Y-%m-%d", localtime ),$dateduef->output('iso'), C4::Context->userenv->{'branch'}
        );
        $sth->finish;
        $item->{'issues'}++;
        ModItem({ issues           => $item->{'issues'},
                  holdingbranch    => C4::Context->userenv->{'branch'},
                  itemlost         => 0,
                  datelastborrowed => C4::Dates->new()->output('iso'),
                  onloan           => $dateduef->output('iso'),
                }, $item->{'biblionumber'}, $item->{'itemnumber'});
        ModDateLastSeen( $item->{'itemnumber'} );
        
        # If it costs to borrow this book, charge it to the patron's account.
        my ( $charge, $itemtype ) = GetIssuingCharges(
            $item->{'itemnumber'},
            $borrower->{'borrowernumber'}
        );
        if ( $charge > 0 ) {
            AddIssuingCharge(
                $item->{'itemnumber'},
                $borrower->{'borrowernumber'}, $charge
            );
            $item->{'charge'} = $charge;
        }

        # Record the fact that this book was issued.
        &UpdateStats(
            C4::Context->userenv->{'branch'},
            'issue',                        $charge,
            '',                             $item->{'itemnumber'},
            $item->{'itemtype'}, $borrower->{'borrowernumber'}
        );
    }
    
    &logaction(C4::Context->userenv->{'number'},"CIRCULATION","ISSUE",$borrower->{'borrowernumber'},$biblio->{'biblionumber'}) 
        if C4::Context->preference("IssueLog");
    return ($datedue);
  }
}

=head2 GetLoanLength

Get loan length for an itemtype, a borrower type and a branch

my $loanlength = &GetLoanLength($borrowertype,$itemtype,branchcode)

=cut

sub GetLoanLength {
    my ( $borrowertype, $itemtype, $branchcode ) = @_;
    my $dbh = C4::Context->dbh;
    my $sth =
      $dbh->prepare(
"select issuelength from issuingrules where categorycode=? and itemtype=? and branchcode=? and issuelength is not null"
      );
# warn "in get loan lenght $borrowertype $itemtype $branchcode ";
# try to find issuelength & return the 1st available.
# check with borrowertype, itemtype and branchcode, then without one of those parameters
    $sth->execute( $borrowertype, $itemtype, $branchcode );
    my $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( $borrowertype, $itemtype, "*" );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( $borrowertype, "*", $branchcode );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( "*", $itemtype, $branchcode );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( $borrowertype, "*", "*" );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( "*", "*", $branchcode );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( "*", $itemtype, "*" );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    $sth->execute( "*", "*", "*" );
    $loanlength = $sth->fetchrow_hashref;
    return $loanlength->{issuelength}
      if defined($loanlength) && $loanlength->{issuelength} ne 'NULL';

    # if no rule is set => 21 days (hardcoded)
    return 21;
}

=head2 AddReturn

($doreturn, $messages, $iteminformation, $borrower) =
    &AddReturn($barcode, $branch, $exemptfine);

Returns a book.

C<$barcode> is the bar code of the book being returned. C<$branch> is
the code of the branch where the book is being returned.  C<$exemptfine>
indicates that overdue charges for the item will not be applied.

C<&AddReturn> returns a list of four items:

C<$doreturn> is true iff the return succeeded.

C<$messages> is a reference-to-hash giving the reason for failure:

=over 4

=item C<BadBarcode>

No item with this barcode exists. The value is C<$barcode>.

=item C<NotIssued>

The book is not currently on loan. The value is C<$barcode>.

=item C<IsPermanent>

The book's home branch is a permanent collection. If you have borrowed
this book, you are not allowed to return it. The value is the code for
the book's home branch.

=item C<wthdrawn>

This book has been withdrawn/cancelled. The value should be ignored.

=item C<ResFound>

The item was reserved. The value is a reference-to-hash whose keys are
fields from the reserves table of the Koha database, and
C<biblioitemnumber>. It also has the key C<ResFound>, whose value is
either C<Waiting>, C<Reserved>, or 0.

=back

C<$borrower> is a reference-to-hash, giving information about the
patron who last borrowed the book.

=cut

sub AddReturn {
    my ( $barcode, $branch, $exemptfine ) = @_;
    my $dbh      = C4::Context->dbh;
    my $messages;
    my $doreturn = 1;
    my $borrower;
    my $validTransfert = 0;
    my $reserveDone = 0;
    
    # get information on item
    my $iteminformation = GetItemIssue( GetItemnumberFromBarcode($barcode));
    my $biblio = GetBiblioItemData($iteminformation->{'biblioitemnumber'});
#     use Data::Dumper;warn Data::Dumper::Dumper($iteminformation);  
    unless ($iteminformation->{'itemnumber'} ) {
        $messages->{'BadBarcode'} = $barcode;
        $doreturn = 0;
    } else {
        # find the borrower
        if ( ( not $iteminformation->{borrowernumber} ) && $doreturn ) {
            $messages->{'NotIssued'} = $barcode;
            $doreturn = 0;
        }
    
        # check if the book is in a permanent collection....
        my $hbr      = $iteminformation->{'homebranch'};
        my $branches = GetBranches();
        if ( $hbr && $branches->{$hbr}->{'PE'} ) {
            $messages->{'IsPermanent'} = $hbr;
        }
		
		    # if independent branches are on and returning to different branch, refuse the return
        if ($hbr ne C4::Context->userenv->{'branch'} && C4::Context->preference("IndependantBranches")){
			  $messages->{'Wrongbranch'} = 1;
			  $doreturn=0;
		    }
			
        # check that the book has been cancelled
        if ( $iteminformation->{'wthdrawn'} ) {
            $messages->{'wthdrawn'} = 1;
            $doreturn = 0;
        }
    
    #     new op dev : if the book returned in an other branch update the holding branch
    
    # update issues, thereby returning book (should push this out into another subroutine
        $borrower = C4::Members::GetMemberDetails( $iteminformation->{borrowernumber}, 0 );
    
    # case of a return of document (deal with issues and holdingbranch)
    
        if ($doreturn) {
            my $sth =
            $dbh->prepare(
    "UPDATE issues SET returndate = now() WHERE (borrowernumber = ?) AND (itemnumber = ?) AND (returndate IS NULL)"
            );
            $sth->execute( $borrower->{'borrowernumber'},
                $iteminformation->{'itemnumber'} );
            $messages->{'WasReturned'} = 1;    # FIXME is the "= 1" right?
        }
    
    # continue to deal with returns cases, but not only if we have an issue
    
        # the holdingbranch is updated if the document is returned in an other location .
        if ( $iteminformation->{'holdingbranch'} ne C4::Context->userenv->{'branch'} ) {
		        UpdateHoldingbranch(C4::Context->userenv->{'branch'},$iteminformation->{'itemnumber'});	
		        #         	reload iteminformation holdingbranch with the userenv value
		        $iteminformation->{'holdingbranch'} = C4::Context->userenv->{'branch'};
        }
        ModDateLastSeen( $iteminformation->{'itemnumber'} );
        ModItem({ onloan => undef }, $biblio->{'biblionumber'}, $iteminformation->{'itemnumber'});
		    
		    if ($iteminformation->{borrowernumber}){
			  ($borrower) = C4::Members::GetMemberDetails( $iteminformation->{borrowernumber}, 0 );
        }       
        # fix up the accounts.....
        if ( $iteminformation->{'itemlost'} ) {
            $messages->{'WasLost'} = 1;
        }
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    #     check if we have a transfer for this document
        my ($datesent,$frombranch,$tobranch) = GetTransfers( $iteminformation->{'itemnumber'} );
    
    #     if we have a transfer to do, we update the line of transfers with the datearrived
        if ($datesent) {
            if ( $tobranch eq C4::Context->userenv->{'branch'} ) {
                    my $sth =
                    $dbh->prepare(
                            "UPDATE branchtransfers SET datearrived = now() WHERE itemnumber= ? AND datearrived IS NULL"
                    );
                    $sth->execute( $iteminformation->{'itemnumber'} );
                    $sth->finish;
    #         now we check if there is a reservation with the validate of transfer if we have one, we can         set it with the status 'W'
            C4::Reserves::ModReserveStatus( $iteminformation->{'itemnumber'},'W' );
            }
        else {
            $messages->{'WrongTransfer'} = $tobranch;
            $messages->{'WrongTransferItem'} = $iteminformation->{'itemnumber'};
        }
        $validTransfert = 1;
        }
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
        # fix up the accounts.....
        if ($iteminformation->{'itemlost'}) {
                FixAccountForLostAndReturned($iteminformation, $borrower);
                $messages->{'WasLost'} = 1;
        }
        # fix up the overdues in accounts...
        FixOverduesOnReturn( $borrower->{'borrowernumber'},
            $iteminformation->{'itemnumber'}, $exemptfine );
    
    # find reserves.....
    #     if we don't have a reserve with the status W, we launch the Checkreserves routine
        my ( $resfound, $resrec ) =
        C4::Reserves::CheckReserves( $iteminformation->{'itemnumber'} );
        if ($resfound) {
            $resrec->{'ResFound'}   = $resfound;
            $messages->{'ResFound'} = $resrec;
            $reserveDone = 1;
        }
    
        # update stats?
        # Record the fact that this book was returned.
        UpdateStats(
            $branch, 'return', '0', '',
            $iteminformation->{'itemnumber'},
            $biblio->{'itemtype'},
            $borrower->{'borrowernumber'}
        );
        
        &logaction(C4::Context->userenv->{'number'},"CIRCULATION","RETURN",$iteminformation->{borrowernumber},$iteminformation->{'biblionumber'}) 
            if C4::Context->preference("ReturnLog");
        
        #adding message if holdingbranch is non equal a userenv branch to return the document to homebranch
        #we check, if we don't have reserv or transfert for this document, if not, return it to homebranch .
        
        if ( ($iteminformation->{'holdingbranch'} ne $iteminformation->{'homebranch'}) and not $messages->{'WrongTransfer'} and ($validTransfert ne 1) and ($reserveDone ne 1) ){
			if (C4::Context->preference("AutomaticItemReturn") == 1) {
				ModItemTransfer($iteminformation->{'itemnumber'}, C4::Context->userenv->{'branch'}, $iteminformation->{'homebranch'});
				$messages->{'WasTransfered'} = 1;
			}
			else {
				$messages->{'NeedsTransfer'} = 1;
			}
        }
    }
    return ( $doreturn, $messages, $iteminformation, $borrower );
}

=head2 FixOverduesOnReturn

    &FixOverduesOnReturn($brn,$itm, $exemptfine);

C<$brn> borrowernumber

C<$itm> itemnumber

internal function, called only by AddReturn

=cut

sub FixOverduesOnReturn {
    my ( $borrowernumber, $item, $exemptfine ) = @_;
    my $dbh = C4::Context->dbh;

    # check for overdue fine
    my $sth =
      $dbh->prepare(
"SELECT * FROM accountlines WHERE (borrowernumber = ?) AND (itemnumber = ?) AND (accounttype='FU' OR accounttype='O')"
      );
    $sth->execute( $borrowernumber, $item );

    # alter fine to show that the book has been returned
   my $data; 
	if ($data = $sth->fetchrow_hashref) {
        my $uquery =($exemptfine)? "update accountlines set accounttype='FFOR', amountoutstanding=0":"update accountlines set accounttype='F' ";
	 	$uquery .= " where (borrowernumber = ?) and (itemnumber = ?) and (accountno = ?)";
        my $usth = $dbh->prepare($uquery);
        $usth->execute($borrowernumber,$item ,$data->{'accountno'});
        $usth->finish();
    }

    $sth->finish();
    return;
}

=head2 FixAccountForLostAndReturned

	&FixAccountForLostAndReturned($iteminfo,$borrower);

Calculates the charge for a book lost and returned (Not exported & used only once)

C<$iteminfo> is a hashref to iteminfo. Only {itemnumber} is used.

C<$borrower> is a hashref to borrower. Only {borrowernumber is used.

Internal function, called by AddReturn

=cut

sub FixAccountForLostAndReturned {
	my ($iteminfo, $borrower) = @_;
	my %env;
	my $dbh = C4::Context->dbh;
	my $itm = $iteminfo->{'itemnumber'};
	# check for charge made for lost book
	my $sth = $dbh->prepare("SELECT * FROM accountlines WHERE (itemnumber = ?) AND (accounttype='L' OR accounttype='Rep') ORDER BY date DESC");
	$sth->execute($itm);
	if (my $data = $sth->fetchrow_hashref) {
	# writeoff this amount
		my $offset;
		my $amount = $data->{'amount'};
		my $acctno = $data->{'accountno'};
		my $amountleft;
		if ($data->{'amountoutstanding'} == $amount) {
		$offset = $data->{'amount'};
		$amountleft = 0;
		} else {
		$offset = $amount - $data->{'amountoutstanding'};
		$amountleft = $data->{'amountoutstanding'} - $amount;
		}
		my $usth = $dbh->prepare("UPDATE accountlines SET accounttype = 'LR',amountoutstanding='0'
			WHERE (borrowernumber = ?)
			AND (itemnumber = ?) AND (accountno = ?) ");
		$usth->execute($data->{'borrowernumber'},$itm,$acctno);
		$usth->finish;
	#check if any credit is left if so writeoff other accounts
		my $nextaccntno = getnextacctno(\%env,$data->{'borrowernumber'},$dbh);
		if ($amountleft < 0){
		$amountleft*=-1;
		}
		if ($amountleft > 0){
		my $msth = $dbh->prepare("SELECT * FROM accountlines WHERE (borrowernumber = ?)
							AND (amountoutstanding >0) ORDER BY date");
		$msth->execute($data->{'borrowernumber'});
	# offset transactions
		my $newamtos;
		my $accdata;
		while (($accdata=$msth->fetchrow_hashref) and ($amountleft>0)){
			if ($accdata->{'amountoutstanding'} < $amountleft) {
			$newamtos = 0;
			$amountleft -= $accdata->{'amountoutstanding'};
			}  else {
			$newamtos = $accdata->{'amountoutstanding'} - $amountleft;
			$amountleft = 0;
			}
			my $thisacct = $accdata->{'accountno'};
			my $usth = $dbh->prepare("UPDATE accountlines SET amountoutstanding= ?
					WHERE (borrowernumber = ?)
					AND (accountno=?)");
			$usth->execute($newamtos,$data->{'borrowernumber'},'$thisacct');
			$usth->finish;
			$usth = $dbh->prepare("INSERT INTO accountoffsets
				(borrowernumber, accountno, offsetaccount,  offsetamount)
				VALUES
				(?,?,?,?)");
			$usth->execute($data->{'borrowernumber'},$accdata->{'accountno'},$nextaccntno,$newamtos);
			$usth->finish;
		}
		$msth->finish;
		}
		if ($amountleft > 0){
			$amountleft*=-1;
		}
		my $desc="Item Returned ".$iteminfo->{'barcode'};
		$usth = $dbh->prepare("INSERT INTO accountlines
			(borrowernumber,accountno,date,amount,description,accounttype,amountoutstanding)
			VALUES (?,?,now(),?,?,'CR',?)");
		$usth->execute($data->{'borrowernumber'},$nextaccntno,0-$amount,$desc,$amountleft);
		$usth->finish;
		$usth = $dbh->prepare("INSERT INTO accountoffsets
			(borrowernumber, accountno, offsetaccount,  offsetamount)
			VALUES (?,?,?,?)");
		$usth->execute($borrower->{'borrowernumber'},$data->{'accountno'},$nextaccntno,$offset);
		$usth->finish;
        ModItem({ paidfor => '' }, undef, $itm);
	}
	$sth->finish;
	return;
}

=head2 GetItemIssue

$issues = &GetItemIssue($itemnumber);

Returns patrons currently having a book. nothing if item is not issued atm

C<$itemnumber> is the itemnumber

Returns an array of hashes

=cut

sub GetItemIssue {
    my ( $itemnumber) = @_;
    return unless $itemnumber;
    my $dbh = C4::Context->dbh;
    my @GetItemIssues;
    
    # get today date
    my $today = POSIX::strftime("%Y%m%d", localtime);

    my $sth = $dbh->prepare(
        "SELECT * FROM issues 
        LEFT JOIN items ON issues.itemnumber=items.itemnumber
    WHERE
    issues.itemnumber=?  AND returndate IS NULL ");
    $sth->execute($itemnumber);
    my $data = $sth->fetchrow_hashref;
    my $datedue = $data->{'date_due'};
    $datedue =~ s/-//g;
    if ( $datedue < $today ) {
        $data->{'overdue'} = 1;
    }
    $data->{'itemnumber'} = $itemnumber; # fill itemnumber, in case item is not on issue
    $sth->finish;
    return ($data);
}

=head2 GetItemIssues

$issues = &GetItemIssues($itemnumber, $history);

Returns patrons that have issued a book

C<$itemnumber> is the itemnumber
C<$history> is 0 if you want actuel "issuer" (if it exist) and 1 if you want issues history

Returns an array of hashes

=cut

sub GetItemIssues {
    my ( $itemnumber,$history ) = @_;
    my $dbh = C4::Context->dbh;
    my @GetItemIssues;
    
    # get today date
    my $today = POSIX::strftime("%Y%m%d", localtime);

    my $sth = $dbh->prepare(
        "SELECT * FROM issues 
        LEFT JOIN borrowers ON borrowers.borrowernumber 
        LEFT JOIN items ON items.itemnumber=issues.itemnumber 
    WHERE
    issues.itemnumber=?".($history?"":" AND returndate IS NULL ").
    "ORDER BY issues.date_due DESC"
    );
    $sth->execute($itemnumber);
    while ( my $data = $sth->fetchrow_hashref ) {
        my $datedue = $data->{'date_due'};
        $datedue =~ s/-//g;
        if ( $datedue < $today ) {
            $data->{'overdue'} = 1;
        }
        my $itemnumber = $data->{'itemnumber'};
        push @GetItemIssues, $data;
    }
    $sth->finish;
    return ( \@GetItemIssues );
}

=head2 GetBiblioIssues

$issues = GetBiblioIssues($biblionumber);

this function get all issues from a biblionumber.

Return:
C<$issues> is a reference to array which each value is ref-to-hash. This ref-to-hash containts all column from
tables issues and the firstname,surname & cardnumber from borrowers.

=cut

sub GetBiblioIssues {
    my $biblionumber = shift;
    return undef unless $biblionumber;
    my $dbh   = C4::Context->dbh;
    my $query = "
        SELECT issues.*,items.barcode,biblio.biblionumber,biblio.title, biblio.author,borrowers.cardnumber,borrowers.surname,borrowers.firstname
        FROM issues
            LEFT JOIN borrowers ON borrowers.borrowernumber = issues.borrowernumber
            LEFT JOIN items ON issues.itemnumber = items.itemnumber
            LEFT JOIN biblioitems ON items.itemnumber = biblioitems.biblioitemnumber
            LEFT JOIN biblio ON biblio.biblionumber = items.biblioitemnumber
        WHERE biblio.biblionumber = ?
        ORDER BY issues.timestamp
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute($biblionumber);

    my @issues;
    while ( my $data = $sth->fetchrow_hashref ) {
        push @issues, $data;
    }
    return \@issues;
}

=head2 CanBookBeRenewed

($ok,$error) = &CanBookBeRenewed($borrowernumber, $itemnumber);

Find out whether a borrowed item may be renewed.

C<$dbh> is a DBI handle to the Koha database.

C<$borrowernumber> is the borrower number of the patron who currently
has the item on loan.

C<$itemnumber> is the number of the item to renew.

C<$CanBookBeRenewed> returns a true value iff the item may be renewed. The
item must currently be on loan to the specified borrower; renewals
must be allowed for the item's type; and the borrower must not have
already renewed the loan. $error will contain the reason the renewal can not proceed

=cut

sub CanBookBeRenewed {

    # check renewal status
    my ( $borrowernumber, $itemnumber ) = @_;
    my $dbh       = C4::Context->dbh;
    my $renews    = 1;
    my $renewokay = 0;
	my $error;

    # Look in the issues table for this item, lent to this borrower,
    # and not yet returned.

    # FIXME - I think this function could be redone to use only one SQL call.
    my $sth1 = $dbh->prepare(
        "SELECT * FROM issues
            WHERE borrowernumber = ?
            AND itemnumber = ?
            AND returndate IS NULL"
    );
    $sth1->execute( $borrowernumber, $itemnumber );
    if ( my $data1 = $sth1->fetchrow_hashref ) {

        # Found a matching item

        # See if this item may be renewed. This query is convoluted
        # because it's a bit messy: given the item number, we need to find
        # the biblioitem, which gives us the itemtype, which tells us
        # whether it may be renewed.
        my $sth2 = $dbh->prepare(
            "SELECT renewalsallowed FROM items
                LEFT JOIN biblioitems on items.biblioitemnumber = biblioitems.biblioitemnumber
                LEFT JOIN itemtypes ON biblioitems.itemtype = itemtypes.itemtype
                WHERE items.itemnumber = ?
                "
        );
        $sth2->execute($itemnumber);
        if ( my $data2 = $sth2->fetchrow_hashref ) {
            $renews = $data2->{'renewalsallowed'};
        }
        if ( $renews && $renews > $data1->{'renewals'} ) {
            $renewokay = 1;
        }
        else {
			$error="too_many";
		}
        $sth2->finish;
        my ( $resfound, $resrec ) = C4::Reserves::CheckReserves($itemnumber);
        if ($resfound) {
            $renewokay = 0;
			$error="on_reserve"
        }

    }
    $sth1->finish;
    return ($renewokay,$error);
}

=head2 AddRenewal

&AddRenewal($borrowernumber, $itemnumber, $datedue);

Renews a loan.

C<$borrowernumber> is the borrower number of the patron who currently
has the item.

C<$itemnumber> is the number of the item to renew.

C<$datedue> can be used to set the due date. If C<$datedue> is the
empty string, C<&AddRenewal> will calculate the due date automatically
from the book's item type. If you wish to set the due date manually,
C<$datedue> should be in the form YYYY-MM-DD.

=cut

sub AddRenewal {

    my ( $borrowernumber, $itemnumber, $branch ,$datedue ) = @_;
    my $dbh = C4::Context->dbh;
	
	my $biblio = GetBiblioFromItemNumber($itemnumber);
    # If the due date wasn't specified, calculate it by adding the
    # book's loan length to today's date.
    unless ( $datedue ) {


        my $borrower = C4::Members::GetMemberDetails( $borrowernumber, 0 );
        my $loanlength = GetLoanLength(
            $borrower->{'categorycode'},
             (C4::Context->preference('item-level_itypes')) ? $biblio->{'itype'} : $biblio->{'itemtype'} ,
			$borrower->{'branchcode'}
        );
		#FIXME --  choose issuer or borrower branch.
		#FIXME -- where's the calendar ?
		#FIXME -- $debug-ify the (0)
        my @darray = Add_Delta_DHMS( Today_and_Now(), $loanlength, 0, 0, 0 );
        $datedue = C4::Dates->new( sprintf("%04d-%02d-%02d",@darray[0..2]), 'iso');
		(0) and print STDERR  "C4::Dates->new->output = " . C4::Dates->new()->output()
		 		. "\ndatedue->output = " . $datedue->output()
		 		. "\n(Y,M,D) = " . join ',', @darray;
		$datedue=CheckValidDatedue($datedue,$itemnumber,$branch);
    }

    # Find the issues record for this book
    my $sth =
      $dbh->prepare("SELECT * FROM issues
                        WHERE borrowernumber=? 
                        AND itemnumber=? 
                        AND returndate IS NULL"
      );
    $sth->execute( $borrowernumber, $itemnumber );
    my $issuedata = $sth->fetchrow_hashref;
    $sth->finish;

    # Update the issues record to have the new due date, and a new count
    # of how many times it has been renewed.
    my $renews = $issuedata->{'renewals'} + 1;
    $sth = $dbh->prepare("UPDATE issues SET date_due = ?, renewals = ?
                            WHERE borrowernumber=? 
                            AND itemnumber=? 
                            AND returndate IS NULL"
    );
    $sth->execute( $datedue->output('iso'), $renews, $borrowernumber, $itemnumber );
    $sth->finish;

    # Update the renewal count on the item, and tell zebra to reindex
    $renews = $biblio->{'renewals'} + 1;
    ModItem({ renewals => $renews }, $biblio->{'biblionumber'}, $itemnumber);

    # Charge a new rental fee, if applicable?
    my ( $charge, $type ) = GetIssuingCharges( $itemnumber, $borrowernumber );
    if ( $charge > 0 ) {
        my $accountno = getnextacctno( $borrowernumber );
        my $item = GetBiblioFromItemNumber($itemnumber);
        $sth = $dbh->prepare(
                "INSERT INTO accountlines
                    (borrowernumber,accountno,date,amount,
                        description,accounttype,amountoutstanding,
                    itemnumber)
                    VALUES (?,?,now(),?,?,?,?,?)"
        );
        $sth->execute( $borrowernumber, $accountno, $charge,
            "Renewal of Rental Item $item->{'title'} $item->{'barcode'}",
            'Rent', $charge, $itemnumber );
        $sth->finish;
    }
    # Log the renewal
    UpdateStats( $branch, 'renew', $charge, '', $itemnumber );
}

sub GetRenewCount {
    # check renewal status
    my ($bornum,$itemno)=@_;
    my $dbh = C4::Context->dbh;
    my $renewcount = 0;
        my $renewsallowed = 0;
        my $renewsleft = 0;
    # Look in the issues table for this item, lent to this borrower,
    # and not yet returned.

    # FIXME - I think this function could be redone to use only one SQL call.
    my $sth = $dbh->prepare("select * from issues
                                where (borrowernumber = ?)
                                and (itemnumber = ?)
                                and returndate is null");
    $sth->execute($bornum,$itemno);
        my $data = $sth->fetchrow_hashref;
        $renewcount = $data->{'renewals'} if $data->{'renewals'};
    my $sth2 = $dbh->prepare("select renewalsallowed from items,biblioitems,itemtypes
        where (items.itemnumber = ?)
                and (items.biblioitemnumber = biblioitems.biblioitemnumber)
        and (biblioitems.itemtype = itemtypes.itemtype)");
    $sth2->execute($itemno);
        my $data2 = $sth2->fetchrow_hashref();
        $renewsallowed = $data2->{'renewalsallowed'};
        $renewsleft = $renewsallowed - $renewcount;
#         warn "Renewcount:$renewcount RenewsAll:$renewsallowed RenewLeft:$renewsleft";
        return ($renewcount,$renewsallowed,$renewsleft);
}
=head2 GetIssuingCharges

($charge, $item_type) = &GetIssuingCharges($itemnumber, $borrowernumber);

Calculate how much it would cost for a given patron to borrow a given
item, including any applicable discounts.

C<$itemnumber> is the item number of item the patron wishes to borrow.

C<$borrowernumber> is the patron's borrower number.

C<&GetIssuingCharges> returns two values: C<$charge> is the rental charge,
and C<$item_type> is the code for the item's item type (e.g., C<VID>
if it's a video).

=cut

sub GetIssuingCharges {

    # calculate charges due
    my ( $itemnumber, $borrowernumber ) = @_;
    my $charge = 0;
    my $dbh    = C4::Context->dbh;
    my $item_type;

    # Get the book's item type and rental charge (via its biblioitem).
    my $qcharge =     "SELECT itemtypes.itemtype,rentalcharge FROM items
            LEFT JOIN biblioitems ON biblioitems.biblioitemnumber = items.biblioitemnumber";
	$qcharge .= (C4::Context->preference('item-level_itypes'))
                ? " LEFT JOIN itemtypes ON items.itype = itemtypes.itemtype "
                : " LEFT JOIN itemtypes ON biblioitems.itemtype = itemtypes.itemtype ";
	
    $qcharge .=      "WHERE items.itemnumber =?";
   
    my $sth1 = $dbh->prepare($qcharge);
    $sth1->execute($itemnumber);
    if ( my $data1 = $sth1->fetchrow_hashref ) {
        $item_type = $data1->{'itemtype'};
        $charge    = $data1->{'rentalcharge'};
        my $q2 = "SELECT rentaldiscount FROM borrowers
            LEFT JOIN issuingrules ON borrowers.categorycode = issuingrules.categorycode
            WHERE borrowers.borrowernumber = ?
            AND issuingrules.itemtype = ?";
        my $sth2 = $dbh->prepare($q2);
        $sth2->execute( $borrowernumber, $item_type );
        if ( my $data2 = $sth2->fetchrow_hashref ) {
            my $discount = $data2->{'rentaldiscount'};
            if ( $discount eq 'NULL' ) {
                $discount = 0;
            }
            $charge = ( $charge * ( 100 - $discount ) ) / 100;
        }
        $sth2->finish;
    }

    $sth1->finish;
    return ( $charge, $item_type );
}

=head2 AddIssuingCharge

&AddIssuingCharge( $itemno, $borrowernumber, $charge )

=cut

sub AddIssuingCharge {
    my ( $itemnumber, $borrowernumber, $charge ) = @_;
    my $dbh = C4::Context->dbh;
    my $nextaccntno = getnextacctno( $borrowernumber );
    my $query ="
        INSERT INTO accountlines
            (borrowernumber, itemnumber, accountno,
            date, amount, description, accounttype,
            amountoutstanding)
        VALUES (?, ?, ?,now(), ?, 'Rental', 'Rent',?)
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute( $borrowernumber, $itemnumber, $nextaccntno, $charge, $charge );
    $sth->finish;
}

=head2 GetTransfers

GetTransfers($itemnumber);

=cut

sub GetTransfers {
    my ($itemnumber) = @_;

    my $dbh = C4::Context->dbh;

    my $query = '
        SELECT datesent,
               frombranch,
               tobranch
        FROM branchtransfers
        WHERE itemnumber = ?
          AND datearrived IS NULL
        ';
    my $sth = $dbh->prepare($query);
    $sth->execute($itemnumber);
    my @row = $sth->fetchrow_array();
    $sth->finish;
    return @row;
}


=head2 GetTransfersFromTo

@results = GetTransfersFromTo($frombranch,$tobranch);

Returns the list of pending transfers between $from and $to branch

=cut

sub GetTransfersFromTo {
    my ( $frombranch, $tobranch ) = @_;
    return unless ( $frombranch && $tobranch );
    my $dbh   = C4::Context->dbh;
    my $query = "
        SELECT itemnumber,datesent,frombranch
        FROM   branchtransfers
        WHERE  frombranch=?
          AND  tobranch=?
          AND datearrived IS NULL
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute( $frombranch, $tobranch );
    my @gettransfers;

    while ( my $data = $sth->fetchrow_hashref ) {
        push @gettransfers, $data;
    }
    $sth->finish;
    return (@gettransfers);
}

=head2 DeleteTransfer

&DeleteTransfer($itemnumber);

=cut

sub DeleteTransfer {
    my ($itemnumber) = @_;
    my $dbh          = C4::Context->dbh;
    my $sth          = $dbh->prepare(
        "DELETE FROM branchtransfers
         WHERE itemnumber=?
         AND datearrived IS NULL "
    );
    $sth->execute($itemnumber);
    $sth->finish;
}

=head2 AnonymiseIssueHistory

$rows = AnonymiseIssueHistory($borrowernumber,$date)

This function write NULL instead of C<$borrowernumber> given on input arg into the table issues.
if C<$borrowernumber> is not set, it will delete the issue history for all borrower older than C<$date>.

return the number of affected rows.

=cut

sub AnonymiseIssueHistory {
    my $date           = shift;
    my $borrowernumber = shift;
    my $dbh            = C4::Context->dbh;
    my $query          = "
        UPDATE issues
        SET    borrowernumber = NULL
        WHERE  returndate < '".$date."'
          AND borrowernumber IS NOT NULL
    ";
    $query .= " AND borrowernumber = '".$borrowernumber."'" if defined $borrowernumber;
    my $rows_affected = $dbh->do($query);
    return $rows_affected;
}

=head2 updateWrongTransfer

$items = updateWrongTransfer($itemNumber,$borrowernumber,$waitingAtLibrary,$FromLibrary);

This function validate the line of brachtransfer but with the wrong destination (mistake from a librarian ...), and create a new line in branchtransfer from the actual library to the original library of reservation 

=cut

sub updateWrongTransfer {
	my ( $itemNumber,$waitingAtLibrary,$FromLibrary ) = @_;
	my $dbh = C4::Context->dbh;	
# first step validate the actual line of transfert .
	my $sth =
        	$dbh->prepare(
			"update branchtransfers set datearrived = now(),tobranch=?,comments='wrongtransfer' where itemnumber= ? AND datearrived IS NULL"
          	);
        	$sth->execute($FromLibrary,$itemNumber);
        	$sth->finish;

# second step create a new line of branchtransfer to the right location .
	ModItemTransfer($itemNumber, $FromLibrary, $waitingAtLibrary);

#third step changing holdingbranch of item
	UpdateHoldingbranch($FromLibrary,$itemNumber);
}

=head2 UpdateHoldingbranch

$items = UpdateHoldingbranch($branch,$itmenumber);
Simple methode for updating hodlingbranch in items BDD line

=cut

sub UpdateHoldingbranch {
	my ( $branch,$itemnumber ) = @_;
    ModItem({ holdingbranch => $branch }, undef, $itemnumber);
}

=head2 CheckValidDatedue

$newdatedue = CheckValidDatedue($date_due,$itemnumber,$branchcode);
this function return a new date due after checked if it's a repeatable or special holiday
C<$date_due>   = returndate calculate with no day check
C<$itemnumber>  = itemnumber
C<$branchcode>  = localisation of issue 

=cut

# Why not create calendar object?  - 
# TODO add 'duedate' option to useDaysMode .
sub CheckValidDatedue { 
my ($date_due,$itemnumber,$branchcode)=@_;
my @datedue=split('-',$date_due->output('iso'));
my $years=$datedue[0];
my $month=$datedue[1];
my $day=$datedue[2];
# die "Item# $itemnumber ($branchcode) due: " . ${date_due}->output() . "\n(Y,M,D) = ($years,$month,$day)":
my $dow;
for (my $i=0;$i<2;$i++){
	$dow=Day_of_Week($years,$month,$day);
	($dow=0) if ($dow>6);
	my $result=CheckRepeatableHolidays($itemnumber,$dow,$branchcode);
	my $countspecial=CheckSpecialHolidays($years,$month,$day,$itemnumber,$branchcode);
	my $countspecialrepeatable=CheckRepeatableSpecialHolidays($month,$day,$itemnumber,$branchcode);
		if (($result ne '0') or ($countspecial ne '0') or ($countspecialrepeatable ne '0') ){
		$i=0;
		(($years,$month,$day) = Add_Delta_Days($years,$month,$day, 1))if ($i ne '1');
		}
	}
	my $newdatedue=C4::Dates->new(sprintf("%04d-%02d-%02d",$years,$month,$day),'iso');
return $newdatedue;
}

=head2 CheckRepeatableHolidays

$countrepeatable = CheckRepeatableHoliday($itemnumber,$week_day,$branchcode);
this function check if the date due is a repeatable holiday
C<$date_due>   = returndate calculate with no day check
C<$itemnumber>  = itemnumber
C<$branchcode>  = localisation of issue 

=cut

sub CheckRepeatableHolidays{
my($itemnumber,$week_day,$branchcode)=@_;
my $dbh = C4::Context->dbh;
my $query = qq|SELECT count(*)  
	FROM repeatable_holidays 
	WHERE branchcode=?
	AND weekday=?|;
my $sth = $dbh->prepare($query);
$sth->execute($branchcode,$week_day);
my $result=$sth->fetchrow;
$sth->finish;
return $result;
}


=head2 CheckSpecialHolidays

$countspecial = CheckSpecialHolidays($years,$month,$day,$itemnumber,$branchcode);
this function check if the date is a special holiday
C<$years>   = the years of datedue
C<$month>   = the month of datedue
C<$day>     = the day of datedue
C<$itemnumber>  = itemnumber
C<$branchcode>  = localisation of issue 

=cut

sub CheckSpecialHolidays{
my ($years,$month,$day,$itemnumber,$branchcode) = @_;
my $dbh = C4::Context->dbh;
my $query=qq|SELECT count(*) 
	     FROM `special_holidays`
	     WHERE year=?
	     AND month=?
	     AND day=?
             AND branchcode=?
	    |;
my $sth = $dbh->prepare($query);
$sth->execute($years,$month,$day,$branchcode);
my $countspecial=$sth->fetchrow ;
$sth->finish;
return $countspecial;
}

=head2 CheckRepeatableSpecialHolidays

$countspecial = CheckRepeatableSpecialHolidays($month,$day,$itemnumber,$branchcode);
this function check if the date is a repeatble special holidays
C<$month>   = the month of datedue
C<$day>     = the day of datedue
C<$itemnumber>  = itemnumber
C<$branchcode>  = localisation of issue 

=cut

sub CheckRepeatableSpecialHolidays{
my ($month,$day,$itemnumber,$branchcode) = @_;
my $dbh = C4::Context->dbh;
my $query=qq|SELECT count(*) 
	     FROM `repeatable_holidays`
	     WHERE month=?
	     AND day=?
             AND branchcode=?
	    |;
my $sth = $dbh->prepare($query);
$sth->execute($month,$day,$branchcode);
my $countspecial=$sth->fetchrow ;
$sth->finish;
return $countspecial;
}



sub CheckValidBarcode{
my ($barcode) = @_;
my $dbh = C4::Context->dbh;
my $query=qq|SELECT count(*) 
	     FROM items 
             WHERE barcode=?
	    |;
my $sth = $dbh->prepare($query);
$sth->execute($barcode);
my $exist=$sth->fetchrow ;
$sth->finish;
return $exist;
}

1;

__END__

=head1 AUTHOR

Koha Developement team <info@koha.org>

=cut

