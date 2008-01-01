package C4::Acquisition;

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
use C4::Dates qw(format_date);
use MARC::Record;
use C4::Suggestions;
use Time::localtime;

use vars qw($VERSION @ISA @EXPORT);

# set the version for version checking
$VERSION = 3.01;

# used in receiveorder subroutine
# to provide library specific handling
my $library_name = C4::Context->preference("LibraryName");

=head1 NAME

C4::Acquisition - Koha functions for dealing with orders and acquisitions

=head1 SYNOPSIS

use C4::Acquisition;

=head1 DESCRIPTION

The functions in this module deal with acquisitions, managing book
orders, basket and parcels.

=head1 FUNCTIONS

=over 2

=cut

@ISA    = qw(Exporter);
@EXPORT = qw(
  &GetBasket &NewBasket &CloseBasket
  &GetPendingOrders &GetOrder &GetOrders
  &GetOrderNumber &GetLateOrders &NewOrder &DelOrder
  &SearchOrder &GetHistory &GetRecentAcqui
  &ModOrder &ModReceiveOrder &ModOrderBiblioNumber
  &GetParcels &GetParcel
);

=head2 FUNCTIONS ABOUT BASKETS

=over 2

=cut

#------------------------------------------------------------#

=head3 GetBasket

=over 4

$aqbasket = &GetBasket($basketnumber);

get all basket informations in aqbasket for a given basket

return :
informations for a given basket returned as a hashref.

=back

=back

=cut

sub GetBasket {
    my ($basketno) = @_;
    my $dbh        = C4::Context->dbh;
    my $query = "
        SELECT  aqbasket.*,
                concat( b.firstname,' ',b.surname) AS authorisedbyname,
                b.branchcode AS branch
        FROM    aqbasket
        LEFT JOIN borrowers b ON aqbasket.authorisedby=b.borrowernumber
        WHERE basketno=?
    ";
    my $sth=$dbh->prepare($query);
    $sth->execute($basketno);
    my $basket = $sth->fetchrow_hashref;
	return ( $basket );
}

#------------------------------------------------------------#

=head3 NewBasket

=over 4

$basket = &NewBasket();

Create a new basket in aqbasket table

=back

=cut

# FIXME : this function seems to be unused.

sub NewBasket {
    my ( $booksellerid, $authorisedby ) = @_;
    my $dbh = C4::Context->dbh;
    my $query = "
        INSERT INTO aqbasket
                (creationdate,booksellerid,authorisedby)
        VALUES  (now(),'$booksellerid','$authorisedby')
    ";
    my $sth =
      $dbh->do($query);

#find & return basketno MYSQL dependant, but $dbh->last_insert_id always returns null :-(
    my $basket = $dbh->{'mysql_insertid'};
    return $basket;
}

#------------------------------------------------------------#

=head3 CloseBasket

=over 4

&CloseBasket($basketno);

close a basket (becomes unmodifiable,except for recieves)

=back

=cut

sub CloseBasket {
    my ($basketno) = @_;
    my $dbh        = C4::Context->dbh;
    my $query = "
        UPDATE aqbasket
        SET    closedate=now()
        WHERE  basketno=?
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute($basketno);
}

#------------------------------------------------------------#

=back

=head2 FUNCTIONS ABOUT ORDERS

=over 2

=cut

#------------------------------------------------------------#

=head3 GetPendingOrders

=over 4

$orders = &GetPendingOrders($booksellerid, $grouped);

Finds pending orders from the bookseller with the given ID. Ignores
completed and cancelled orders.

C<$orders> is a reference-to-array; each element is a
reference-to-hash with the following fields:
C<$grouped> is a boolean that, if set to 1 will group all order lines of the same basket
in a single result line 

=over 2

=item C<authorizedby>

=item C<entrydate>

=item C<basketno>

These give the value of the corresponding field in the aqorders table
of the Koha database.

=back

=back

Results are ordered from most to least recent.

=cut

sub GetPendingOrders {
    my ($supplierid,$grouped) = @_;
    my $dbh = C4::Context->dbh;
    my $strsth = "
        SELECT    ".($grouped?"count(*),":"")."aqbasket.basketno,
                    surname,firstname,aqorders.*,
                    aqbasket.closedate, aqbasket.creationdate
        FROM      aqorders
        LEFT JOIN aqbasket ON aqbasket.basketno=aqorders.basketno
        LEFT JOIN borrowers ON aqbasket.authorisedby=borrowers.borrowernumber
        WHERE booksellerid=?
            AND (quantity > quantityreceived OR quantityreceived is NULL)
            AND datecancellationprinted IS NULL
            AND (to_days(now())-to_days(closedate) < 180 OR closedate IS NULL)
    ";
    ## FIXME  Why 180 days ???
    if ( C4::Context->preference("IndependantBranches") ) {
        my $userenv = C4::Context->userenv;
        if ( ($userenv) && ( $userenv->{flags} != 1 ) ) {
            $strsth .=
                " and (borrowers.branchcode = '"
              . $userenv->{branch}
              . "' or borrowers.branchcode ='')";
        }
    }
    $strsth .= " group by aqbasket.basketno" if $grouped;
    $strsth .= " order by aqbasket.basketno";

    my $sth = $dbh->prepare($strsth);
    $sth->execute($supplierid);
    my $results = $sth->fetchall_arrayref({});
    $sth->finish;
    return $results;
}

#------------------------------------------------------------#

=head3 GetOrders

=over 4

@orders = &GetOrders($basketnumber, $orderby);

Looks up the pending (non-cancelled) orders with the given basket
number. If C<$booksellerID> is non-empty, only orders from that seller
are returned.

return :
C<&basket> returns a two-element array. C<@orders> is an array of
references-to-hash, whose keys are the fields from the aqorders,
biblio, and biblioitems tables in the Koha database.

=back

=cut

sub GetOrders {
    my ( $basketno, $orderby ) = @_;
    my $dbh   = C4::Context->dbh;
    my $query  ="
         SELECT  aqorderbreakdown.*,
                biblio.*,biblioitems.publishercode,
                aqorders.*,
                aqbookfund.bookfundname,
                biblio.title
        FROM    aqorders
            LEFT JOIN aqorderbreakdown ON aqorders.ordernumber=aqorderbreakdown.ordernumber
            LEFT JOIN aqbookfund       ON aqbookfund.bookfundid=aqorderbreakdown.bookfundid
            LEFT JOIN biblio           ON biblio.biblionumber=aqorders.biblionumber
            LEFT JOIN biblioitems      ON biblioitems.biblionumber=biblio.biblionumber
        WHERE   basketno=?
            AND (datecancellationprinted IS NULL OR datecancellationprinted='0000-00-00')
    ";

    $orderby = "biblioitems.publishercode,biblio.title" unless $orderby;
    $query .= " ORDER BY $orderby";
    my $sth = $dbh->prepare($query);
    $sth->execute($basketno);
    my @results;

    while ( my $data = $sth->fetchrow_hashref ) {
        push @results, $data;
    }
    $sth->finish;
    return @results;
}

#------------------------------------------------------------#

=head3 GetOrderNumber

=over 4

$ordernumber = &GetOrderNumber($biblioitemnumber, $biblionumber);

Looks up the ordernumber with the given biblionumber and biblioitemnumber.

Returns the number of this order.

=item C<$ordernumber> is the order number.

=back

=cut
sub GetOrderNumber {
    my ( $biblionumber,$biblioitemnumber ) = @_;
    my $dbh = C4::Context->dbh;
    my $query = "
        SELECT ordernumber
        FROM   aqorders
        WHERE  biblionumber=?
        AND    biblioitemnumber=?
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute( $biblionumber, $biblioitemnumber );

    return $sth->fetchrow;
}

#------------------------------------------------------------#

=head3 GetOrder

=over 4

$order = &GetOrder($ordernumber);

Looks up an order by order number.

Returns a reference-to-hash describing the order. The keys of
C<$order> are fields from the biblio, biblioitems, aqorders, and
aqorderbreakdown tables of the Koha database.

=back

=cut

sub GetOrder {
    my ($ordnum) = @_;
    my $dbh      = C4::Context->dbh;
    my $query = "
        SELECT *
        FROM   aqorders
        LEFT JOIN aqorderbreakdown ON aqorders.ordernumber=aqorderbreakdown.ordernumber
        LEFT JOIN biblio on           biblio.biblionumber=aqorders.biblionumber
        LEFT JOIN biblioitems on       biblioitems.biblionumber=aqorders.biblionumber
        WHERE aqorders.ordernumber=?

    ";
    my $sth= $dbh->prepare($query);
    $sth->execute($ordnum);
    my $data = $sth->fetchrow_hashref;
    $sth->finish;
    return $data;
}

#------------------------------------------------------------#

=head3 NewOrder

=over 4

  &NewOrder($basket, $biblionumber, $title, $quantity, $listprice,
    $booksellerid, $who, $notes, $bookfund, $biblioitemnumber, $rrp,
    $ecost, $gst, $budget, $unitprice, $subscription,
    $booksellerinvoicenumber, $purchaseorder);

Adds a new order to the database. Any argument that isn't described
below is the new value of the field with the same name in the aqorders
table of the Koha database.

C<$ordnum> is a "minimum order number." After adding the new entry to
the aqorders table, C<&neworder> finds the first entry in aqorders
with order number greater than or equal to C<$ordnum>, and adds an
entry to the aqorderbreakdown table, with the order number just found,
and the book fund ID of the newly-added order.

C<$budget> is effectively ignored.

C<$subscription> may be either "yes", or anything else for "no".

=back

=cut

sub NewOrder {
   my (
        $basketno,  $bibnum,       $title,        $quantity,
        $listprice, $booksellerid, $authorisedby, $notes,
        $bookfund,  $bibitemnum,   $rrp,          $ecost,
        $gst,       $budget,       $cost,         $sub,
        $invoice,   $sort1,        $sort2,        $purchaseorder
      )
      = @_;

    my $year  = localtime->year() + 1900;
    my $month = localtime->mon() + 1;       # months starts at 0, add 1

    if ( !$budget || $budget eq 'now' ) {
        $budget = "now()";
    }

    # if month is july or more, budget start is 1 jul, next year.
    elsif ( $month >= '7' ) {
        ++$year;                            # add 1 to year , coz its next year
        $budget = "'$year-07-01'";
    }
    else {

        # START OF NEW BUDGET, 1ST OF JULY, THIS YEAR
        $budget = "'$year-07-01'";
    }

    if ( $sub eq 'yes' ) {
        $sub = 1;
    }
    else {
        $sub = 0;
    }

    # if $basket empty, it's also a new basket, create it
    unless ($basketno) {
        $basketno = NewBasket( $booksellerid, $authorisedby );
    }

    my $dbh = C4::Context->dbh;
    my $query = "
        INSERT INTO aqorders
           ( biblionumber,title,basketno,quantity,listprice,notes,
           biblioitemnumber,rrp,ecost,gst,unitprice,subscription,sort1,sort2,budgetdate,entrydate,purchaseordernumber)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,$budget,now(),? )
    ";
    my $sth = $dbh->prepare($query);

    $sth->execute(
        $bibnum, $title,      $basketno, $quantity, $listprice,
        $notes,  $bibitemnum, $rrp,      $ecost,    $gst,
        $cost,   $sub,        $sort1,    $sort2,	$purchaseorder
    );
    $sth->finish;

    #get ordnum MYSQL dependant, but $dbh->last_insert_id returns null
    my $ordnum = $dbh->{'mysql_insertid'};
    $query = "
        INSERT INTO aqorderbreakdown (ordernumber,bookfundid)
        VALUES (?,?)
    ";
    $sth = $dbh->prepare($query);
    $sth->execute( $ordnum, $bookfund );
    $sth->finish;
    return ( $basketno, $ordnum );
}

#------------------------------------------------------------#

=head3 ModOrder

=over 4

&ModOrder($title, $ordernumber, $quantity, $listprice,
    $biblionumber, $basketno, $supplier, $who, $notes,
    $bookfundid, $bibitemnum, $rrp, $ecost, $gst, $budget,
    $unitprice, $booksellerinvoicenumber);

Modifies an existing order. Updates the order with order number
C<$ordernumber> and biblionumber C<$biblionumber>. All other arguments
update the fields with the same name in the aqorders table of the Koha
database.

Entries with order number C<$ordernumber> in the aqorderbreakdown
table are also updated to the new book fund ID.

=back

=cut

sub ModOrder {
    my (
        $title,      $ordnum,   $quantity, $listprice, $bibnum,
        $basketno,   $supplier, $who,      $notes,     $bookfund,
        $bibitemnum, $rrp,      $ecost,    $gst,       $budget,
        $cost,       $invoice,  $sort1,    $sort2,     $purchaseorder
      )
      = @_;
    my $dbh = C4::Context->dbh;
    my $query = "
        UPDATE aqorders
        SET    title=?,
               quantity=?,listprice=?,basketno=?,
               rrp=?,ecost=?,unitprice=?,booksellerinvoicenumber=?,
               notes=?,sort1=?, sort2=?, purchaseordernumber=?
        WHERE  ordernumber=? AND biblionumber=?
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute(
        $title, $quantity, $listprice, $basketno, $rrp,
        $ecost, $cost,     $invoice,   $notes,    $sort1,
        $sort2, $purchaseorder,
		$ordnum,   $bibnum
    );
    $sth->finish;
    $query = "
        UPDATE aqorderbreakdown
        SET    bookfundid=?
        WHERE  ordernumber=?
    ";
    $sth = $dbh->prepare($query);

    unless ( $sth->execute( $bookfund, $ordnum ) )
    {    # zero rows affected [Bug 734]
        my $query ="
            INSERT INTO aqorderbreakdown
                     (ordernumber,bookfundid)
            VALUES   (?,?)
        ";
        $sth = $dbh->prepare($query);
        $sth->execute( $ordnum, $bookfund );
    }
    $sth->finish;
}

#------------------------------------------------------------#

=head3 ModOrderBiblioNumber

=over 4

&ModOrderBiblioNumber($biblioitemnumber,$ordnum, $biblionumber);

Modifies the biblioitemnumber for an existing order.
Updates the order with order number C<$ordernum> and biblionumber C<$biblionumber>.

=back

=cut

sub ModOrderBiblioNumber {
    my ($biblioitemnumber,$ordnum, $biblionumber) = @_;
    my $dbh = C4::Context->dbh;
    my $query = "
      UPDATE aqorders
      SET    biblioitemnumber = ?
      WHERE  ordernumber = ?
      AND biblionumber =  ?";
    my $sth = $dbh->prepare($query);
    $sth->execute( $biblioitemnumber, $ordnum, $biblionumber );
}

#------------------------------------------------------------#

=head3 ModReceiveOrder

=over 4

&ModReceiveOrder($biblionumber, $ordernumber, $quantityreceived, $user,
    $unitprice, $booksellerinvoicenumber, $biblioitemnumber,
    $freight, $bookfund, $rrp);

Updates an order, to reflect the fact that it was received, at least
in part. All arguments not mentioned below update the fields with the
same name in the aqorders table of the Koha database.

If a partial order is received, splits the order into two.  The received
portion must have a booksellerinvoicenumber.  

Updates the order with bibilionumber C<$biblionumber> and ordernumber
C<$ordernumber>.

Also updates the book fund ID in the aqorderbreakdown table.

=back

=cut


sub ModReceiveOrder {
    my (
        $biblionumber,    $ordnum,  $quantrec, $user, $cost,
        $invoiceno, $freight, $rrp, $bookfund, $datereceived
      )
      = @_;
    my $dbh = C4::Context->dbh;
#     warn "DATE BEFORE : $daterecieved";
#    $daterecieved=POSIX::strftime("%Y-%m-%d",CORE::localtime) unless $daterecieved;
#     warn "DATE REC : $daterecieved";
	$datereceived = C4::Dates->output('iso') unless $datereceived;
   
	my $sth=$dbh->prepare("SELECT * FROM aqorders  LEFT JOIN aqorderbreakdown ON aqorders.ordernumber=aqorderbreakdown.ordernumber
							WHERE biblionumber=? AND aqorders.ordernumber=?");
    $sth->execute($biblionumber,$ordnum);
    my $order = $sth->fetchrow_hashref();
    $sth->finish();
	
	if ( $order->{quantity} > $quantrec ) {
        $sth=$dbh->prepare("update aqorders 
							set quantityreceived=?,datereceived=?,booksellerinvoicenumber=?, 
								unitprice=?,freight=?,rrp=?,quantity=?
                            where biblionumber=? and ordernumber=?");
        $sth->execute($quantrec,$datereceived,$invoiceno,$cost,$freight,$rrp,$quantrec,$biblionumber,$ordnum);
        $sth->finish;
        # create a new order for the remaining items, and set its bookfund.
        my $newOrder = NewOrder($order->{'basketno'},$order->{'biblionumber'},$order->{'title'}, $order->{'quantity'} - $quantrec,    
                    $order->{'listprice'},$order->{'booksellerid'},$order->{'authorisedby'},$order->{'notes'},   
                    $order->{'bookfundid'},$order->{'biblioitemnumber'},$order->{'rrp'},$order->{'ecost'},$order->{'gst'},
                    $order->{'budget'},$order->{'unitcost'},$order->{'sub'},'',$order->{'sort1'},$order->{'sort2'},$order->{'purchaseordernumber'});
    
        $sth = $dbh->prepare("select branchcode, bookfundid from aqorderbreakdown where ordernumber=?");
        $sth->execute($ordnum);
        my ($branch,$bookfund) = $sth->fetchrow_array;
        $sth->finish;
        $sth=$dbh->prepare(" insert into aqorderbreakdown (ordernumber, branchcode, bookfundid) values (?,?,?)"); 
        $sth->execute($newOrder,$branch,$bookfund);
    } else {
        $sth=$dbh->prepare("update aqorders 
							set quantityreceived=?,datereceived=?,booksellerinvoicenumber=?, 
								unitprice=?,freight=?,rrp=?
                            where biblionumber=? and ordernumber=?");
        $sth->execute($quantrec,$datereceived,$invoiceno,$cost,$freight,$rrp,$biblionumber,$ordnum);
        $sth->finish;
    }
    my $suggestionid = GetSuggestionFromBiblionumber( $dbh, $biblionumber );
    if ($suggestionid) {
        ModStatus( $suggestionid, 'AVAILABLE', '', $biblionumber );
    }
    # Allows libraries to change their bookfund during receiving orders
    # allows them to adjust budgets
    if ( C4::Context->preference("LooseBudgets") ) {
        my $query = "
            UPDATE aqorderbreakdown
            SET    bookfundid=?
            WHERE  ordernumber=?
        ";
        my $sth = $dbh->prepare($query);
        $sth->execute( $bookfund, $ordnum );
        $sth->finish;
    }
    return $datereceived;
}
#------------------------------------------------------------#

=head3 SearchOrder

@results = &SearchOrder($search, $biblionumber, $complete);

Searches for orders.

C<$search> may take one of several forms: if it is an ISBN,
C<&ordersearch> returns orders with that ISBN. If C<$search> is an
order number, C<&ordersearch> returns orders with that order number
and biblionumber C<$biblionumber>. Otherwise, C<$search> is considered
to be a space-separated list of search terms; in this case, all of the
terms must appear in the title (matching the beginning of title
words).

If C<$complete> is C<yes>, the results will include only completed
orders. In any case, C<&ordersearch> ignores cancelled orders.

C<&ordersearch> returns an array.
C<@results> is an array of references-to-hash with the following keys:

=over 4

=item C<author>

=item C<seriestitle>

=item C<branchcode>

=item C<bookfundid>

=back

=cut

sub SearchOrder {
    my ( $search, $id, $biblionumber, $catview ) = @_;
    my $dbh = C4::Context->dbh;
    my @data = split( ' ', $search );
    my @searchterms;
    if ($id) {
        @searchterms = ($id);
    }
    map { push( @searchterms, "$_%", "%$_%" ) } @data;
    push( @searchterms, $search, $search, $biblionumber );
    my $query;
  ### FIXME  THIS CAN raise a problem if more THAN ONE biblioitem is linked to one biblio  
    if ($id) {  
        $query =
          "SELECT *,biblio.title 
           FROM aqorders 
           LEFT JOIN biblio ON aqorders.biblionumber=biblio.biblionumber 
           LEFT JOIN biblioitems ON biblioitems.biblionumber=biblio.biblionumber 
           LEFT JOIN aqbasket ON aqorders.basketno = aqbasket.basketno
            WHERE aqbasket.booksellerid = ?
            AND ((datecancellationprinted is NULL)
            OR (datecancellationprinted = '0000-00-00'))
            AND (("
          . (
            join( " AND ",
                map { "(biblio.title like ? or biblio.title like ?)" } @data )
          )
          . ") OR biblioitems.isbn=? OR (aqorders.ordernumber=? AND aqorders.biblionumber=?)) ";

    }
    else {
        $query =
          " SELECT *,biblio.title
            FROM   aqorders
            LEFT JOIN biblio ON biblio.biblionumber=aqorders.biblionumber
            LEFT JOIN aqbasket on aqorders.basketno=aqbasket.basketno
            LEFT JOIN biblioitems ON biblioitems.biblionumber=biblio.biblionumber      
            WHERE  ((datecancellationprinted is NULL)
            OR     (datecancellationprinted = '0000-00-00'))
            AND    (aqorders.quantityreceived < aqorders.quantity OR aqorders.quantityreceived is NULL)
            AND (("
          . (
            join( " AND ",
                map { "(biblio.title like ? OR biblio.title like ?)" } @data )
          )
          . ") or biblioitems.isbn=? OR (aqorders.ordernumber=? AND aqorders.biblionumber=?)) ";
    }
    $query .= " GROUP BY aqorders.ordernumber";
    ### $query
    my $sth = $dbh->prepare($query);
    $sth->execute(@searchterms);
    my @results = ();
    my $query2 = "
        SELECT *
        FROM   biblio
        WHERE  biblionumber=?
    ";
    my $sth2 = $dbh->prepare($query2);
    my $query3 = "
        SELECT *
        FROM   aqorderbreakdown
        WHERE  ordernumber=?
    ";
    my $sth3 = $dbh->prepare($query3);

    while ( my $data = $sth->fetchrow_hashref ) {
        $sth2->execute( $data->{'biblionumber'} );
        my $data2 = $sth2->fetchrow_hashref;
        $data->{'author'}      = $data2->{'author'};
        $data->{'seriestitle'} = $data2->{'seriestitle'};
        $sth3->execute( $data->{'ordernumber'} );
        my $data3 = $sth3->fetchrow_hashref;
        $data->{'branchcode'} = $data3->{'branchcode'};
        $data->{'bookfundid'} = $data3->{'bookfundid'};
        push( @results, $data );
    }
    ### @results
    $sth->finish;
    $sth2->finish;
    $sth3->finish;
    return @results;
}

#------------------------------------------------------------#

=head3 DelOrder

=over 4

&DelOrder($biblionumber, $ordernumber);

Cancel the order with the given order and biblio numbers. It does not
delete any entries in the aqorders table, it merely marks them as
cancelled.

=back

=cut

sub DelOrder {
    my ( $bibnum, $ordnum ) = @_;
    my $dbh = C4::Context->dbh;
    my $query = "
        UPDATE aqorders
        SET    datecancellationprinted=now()
        WHERE  biblionumber=? AND ordernumber=?
    ";
    my $sth = $dbh->prepare($query);
    $sth->execute( $bibnum, $ordnum );
    $sth->finish;
}


=back

=head2 FUNCTIONS ABOUT PARCELS

=over 2

=cut

#------------------------------------------------------------#

=head3 GetParcel

=over 4

@results = &GetParcel($booksellerid, $code, $date);

Looks up all of the received items from the supplier with the given
bookseller ID at the given date, for the given code (bookseller Invoice number). Ignores cancelled and completed orders.

C<@results> is an array of references-to-hash. The keys of each element are fields from
the aqorders, biblio, and biblioitems tables of the Koha database.

C<@results> is sorted alphabetically by book title.

=back

=cut

sub GetParcel {
    #gets all orders from a certain supplier, orders them alphabetically
    my ( $supplierid, $code, $datereceived ) = @_;
    my $dbh     = C4::Context->dbh;
    my @results = ();
    $code .= '%'
      if $code;  # add % if we search on a given code (otherwise, let him empty)
    my $strsth ="
        SELECT  authorisedby,
                creationdate,
                aqbasket.basketno,
                closedate,surname,
                firstname,
                aqorders.biblionumber,
                aqorders.title,
                aqorders.ordernumber,
                aqorders.quantity,
                aqorders.quantityreceived,
                aqorders.unitprice,
                aqorders.listprice,
                aqorders.rrp,
                aqorders.ecost
        FROM aqorders 
        LEFT JOIN aqbasket ON aqbasket.basketno=aqorders.basketno
        LEFT JOIN borrowers ON aqbasket.authorisedby=borrowers.borrowernumber
        WHERE 
            aqbasket.booksellerid=?
            AND aqorders.booksellerinvoicenumber LIKE  \"$code\"
            AND aqorders.datereceived= \'$datereceived\'";

    if ( C4::Context->preference("IndependantBranches") ) {
        my $userenv = C4::Context->userenv;
        if ( ($userenv) && ( $userenv->{flags} != 1 ) ) {
            $strsth .=
                " AND (borrowers.branchcode = '"
              . $userenv->{branch}
              . "' OR borrowers.branchcode ='')";
        }
    }
    $strsth .= " ORDER BY aqbasket.basketno";
    ### parcelinformation : $strsth
    warn "STH : $strsth";
    my $sth = $dbh->prepare($strsth);
    $sth->execute($supplierid);
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @results, $data );
    }
    ### countparcelbiblio: scalar(@results)
    $sth->finish;

    return @results;
}

#------------------------------------------------------------#

=head3 GetParcels

=over 4

$results = &GetParcels($bookseller, $order, $code, $datefrom, $dateto);
get a lists of parcels.

* Input arg :

=item $bookseller
is the bookseller this function has to get parcels.

=item $order
To know on what criteria the results list has to be ordered.

=item $code
is the booksellerinvoicenumber.

=item $datefrom & $dateto
to know on what date this function has to filter its search.

* return:
a pointer on a hash list containing parcel informations as such :

=item Creation date

=item Last operation

=item Number of biblio

=item Number of items

=back

=cut

sub GetParcels {
    my ($bookseller,$order, $code, $datefrom, $dateto) = @_;
    my $dbh    = C4::Context->dbh;
    my $strsth ="
        SELECT  aqorders.booksellerinvoicenumber,
                datereceived,purchaseordernumber,
                count(DISTINCT biblionumber) AS biblio,
                sum(quantity) AS itemsexpected,
                sum(quantityreceived) AS itemsreceived
        FROM   aqorders LEFT JOIN aqbasket ON aqbasket.basketno = aqorders.basketno
        WHERE aqbasket.booksellerid = $bookseller and datereceived IS NOT NULL
    ";

    $strsth .= "and aqorders.booksellerinvoicenumber like \"$code%\" " if ($code);

    $strsth .= "and datereceived >=" . $dbh->quote($datefrom) . " " if ($datefrom);

    $strsth .= "and datereceived <=" . $dbh->quote($dateto) . " " if ($dateto);

    $strsth .= "group by aqorders.booksellerinvoicenumber,datereceived ";
    $strsth .= "order by $order " if ($order);
### $strsth
    my $sth = $dbh->prepare($strsth);

    $sth->execute;
    my $results = $sth->fetchall_arrayref({});
    $sth->finish;
    return @$results;
}

#------------------------------------------------------------#

=head3 GetLateOrders

=over 4

@results = &GetLateOrders;

Searches for bookseller with late orders.

return:
the table of supplier with late issues. This table is full of hashref.

=back

=cut

sub GetLateOrders {
    my $delay      = shift;
    my $supplierid = shift;
    my $branch     = shift;

    my $dbh = C4::Context->dbh;

    #BEWARE, order of parenthesis and LEFT JOIN is important for speed
    my $strsth;
    my $dbdriver = C4::Context->config("db_scheme") || "mysql";

    #    warn " $dbdriver";
    if ( $dbdriver eq "mysql" ) {
        $strsth = "
            SELECT aqbasket.basketno,aqorders.ordernumber,
                DATE(aqbasket.closedate) AS orderdate,
                aqorders.quantity - IFNULL(aqorders.quantityreceived,0) AS quantity,
                aqorders.rrp AS unitpricesupplier,
                aqorders.ecost AS unitpricelib,
                (aqorders.quantity - IFNULL(aqorders.quantityreceived,0)) * aqorders.rrp AS subtotal,
                aqbookfund.bookfundname AS budget,
                borrowers.branchcode AS branch,
                aqbooksellers.name AS supplier,
                aqorders.title,
                biblio.author,
                biblioitems.publishercode AS publisher,
                biblioitems.publicationyear,
                DATEDIFF(CURDATE( ),closedate) AS latesince
            FROM  (((
                (aqorders LEFT JOIN biblio ON biblio.biblionumber = aqorders.biblionumber)
            LEFT JOIN biblioitems ON  biblioitems.biblionumber=biblio.biblionumber)
            LEFT JOIN aqorderbreakdown ON aqorders.ordernumber = aqorderbreakdown.ordernumber)
            LEFT JOIN aqbookfund ON aqorderbreakdown.bookfundid = aqbookfund.bookfundid),
            (aqbasket LEFT JOIN borrowers ON aqbasket.authorisedby = borrowers.borrowernumber)
            LEFT JOIN aqbooksellers ON aqbasket.booksellerid = aqbooksellers.id
            WHERE aqorders.basketno = aqbasket.basketno
            AND (closedate < DATE_SUB(CURDATE( ),INTERVAL $delay DAY))
            AND ((datereceived = '' OR datereceived is null)
            OR (aqorders.quantityreceived < aqorders.quantity) )
        ";
        $strsth .= " AND aqbasket.booksellerid = $supplierid " if ($supplierid);
        $strsth .= " AND borrowers.branchcode like \'" . $branch . "\'"
          if ($branch);
        $strsth .=
          " AND borrowers.branchcode like \'"
          . C4::Context->userenv->{branch} . "\'"
          if ( C4::Context->preference("IndependantBranches")
            && C4::Context->userenv
            && C4::Context->userenv->{flags} != 1 );
        $strsth .=" HAVING quantity<>0
                    AND unitpricesupplier<>0
                    AND unitpricelib<>0
                    ORDER BY latesince,basketno,borrowers.branchcode, supplier
        ";
    }
    else {
        $strsth = "
            SELECT aqbasket.basketno,
                   DATE(aqbasket.closedate) AS orderdate,
                    aqorders.quantity, aqorders.rrp AS unitpricesupplier,
                    aqorders.ecost as unitpricelib,
                    aqorders.quantity * aqorders.rrp AS subtotal
                    aqbookfund.bookfundname AS budget,
                    borrowers.branchcode AS branch,
                    aqbooksellers.name AS supplier,
                    biblio.title,
                    biblio.author,
                    biblioitems.publishercode AS publisher,
                    biblioitems.publicationyear,
                    (CURDATE -  closedate) AS latesince
                    FROM(( (
                        (aqorders LEFT JOIN biblio on biblio.biblionumber = aqorders.biblionumber)
                        LEFT JOIN biblioitems on  biblioitems.biblionumber=biblio.biblionumber)
                        LEFT JOIN aqorderbreakdown on aqorders.ordernumber = aqorderbreakdown.ordernumber)
                        LEFT JOIN aqbookfund ON aqorderbreakdown.bookfundid = aqbookfund.bookfundid),
                        (aqbasket LEFT JOIN borrowers on aqbasket.authorisedby = borrowers.borrowernumber) LEFT JOIN aqbooksellers ON aqbasket.booksellerid = aqbooksellers.id
                    WHERE aqorders.basketno = aqbasket.basketno
                    AND (closedate < (CURDATE -(INTERVAL $delay DAY))
                    AND ((datereceived = '' OR datereceived is null)
                    OR (aqorders.quantityreceived < aqorders.quantity) ) ";
        $strsth .= " AND aqbasket.booksellerid = $supplierid " if ($supplierid);

        $strsth .= " AND borrowers.branchcode like \'" . $branch . "\'" if ($branch);
        $strsth .=" AND borrowers.branchcode like \'". C4::Context->userenv->{branch} . "\'"
            if (C4::Context->preference("IndependantBranches") && C4::Context->userenv->{flags} != 1 );
        $strsth .=" ORDER BY latesince,basketno,borrowers.branchcode, supplier";
    }
    my $sth = $dbh->prepare($strsth);
    $sth->execute;
    my @results;
    my $hilighted = 1;
    while ( my $data = $sth->fetchrow_hashref ) {
        $data->{hilighted} = $hilighted if ( $hilighted > 0 );
        $data->{orderdate} = format_date( $data->{orderdate} );
        push @results, $data;
        $hilighted = -$hilighted;
    }
    $sth->finish;
    return @results;
}

#------------------------------------------------------------#

=head3 GetHistory

=over 4

(\@order_loop, $total_qty, $total_price, $total_qtyreceived)=&GetHistory( $title, $author, $name, $from_placed_on, $to_placed_on )

this function get the search history.

=back

=cut

sub GetHistory {
    my ( $title, $author, $name, $from_placed_on, $to_placed_on ) = @_;
    my @order_loop;
    my $total_qty         = 0;
    my $total_qtyreceived = 0;
    my $total_price       = 0;

# don't run the query if there are no parameters (list would be too long for sure !)
    if ( $title || $author || $name || $from_placed_on || $to_placed_on ) {
        my $dbh   = C4::Context->dbh;
        my $query ="
            SELECT
                biblio.title,
                biblio.author,
                aqorders.basketno,
                name,aqbasket.creationdate,
                aqorders.datereceived,
                aqorders.quantity,
                aqorders.quantityreceived,
                aqorders.ecost,
                aqorders.ordernumber,
                aqorders.booksellerinvoicenumber as invoicenumber,
                aqbooksellers.id as id,
                aqorders.biblionumber
            FROM aqorders 
            LEFT JOIN aqbasket ON aqorders.basketno=aqbasket.basketno 
            LEFT JOIN aqbooksellers ON aqbasket.booksellerid=aqbooksellers.id
            LEFT JOIN biblio ON biblio.biblionumber=aqorders.biblionumber";

        $query .= " LEFT JOIN borrowers ON aqbasket.authorisedby=borrowers.borrowernumber"
          if ( C4::Context->preference("IndependantBranches") );

        $query .= " WHERE 1 ";
        $query .= " AND biblio.title LIKE " . $dbh->quote( "%" . $title . "%" )
          if $title;

        $query .=
          " AND biblio.author LIKE " . $dbh->quote( "%" . $author . "%" )
          if $author;

        $query .= " AND name LIKE " . $dbh->quote( "%" . $name . "%" ) if $name;

        $query .= " AND creationdate >" . $dbh->quote($from_placed_on)
          if $from_placed_on;

        $query .= " AND creationdate<" . $dbh->quote($to_placed_on)
          if $to_placed_on;
        $query .= " AND (datecancellationprinted is NULL or datecancellationprinted='0000-00-00')";

        if ( C4::Context->preference("IndependantBranches") ) {
            my $userenv = C4::Context->userenv;
            if ( ($userenv) && ( $userenv->{flags} != 1 ) ) {
                $query .=
                    " AND (borrowers.branchcode = '"
                  . $userenv->{branch}
                  . "' OR borrowers.branchcode ='')";
            }
        }
        $query .= " ORDER BY booksellerid";
        my $sth = $dbh->prepare($query);
        $sth->execute;
        my $cnt = 1;
        while ( my $line = $sth->fetchrow_hashref ) {
            $line->{count} = $cnt++;
            $line->{toggle} = 1 if $cnt % 2;
            push @order_loop, $line;
            $line->{creationdate} = format_date( $line->{creationdate} );
            $line->{datereceived} = format_date( $line->{datereceived} );
            $total_qty         += $line->{'quantity'};
            $total_qtyreceived += $line->{'quantityreceived'};
            $total_price       += $line->{'quantity'} * $line->{'ecost'};
        }
    }
    return \@order_loop, $total_qty, $total_price, $total_qtyreceived;
}

=head2 GetRecentAcqui

   $results = GetRecentAcqui($days);

   C<$results> is a ref to a table which containts hashref

=cut

sub GetRecentAcqui {
    my $limit  = shift;
    my $dbh    = C4::Context->dbh;
    my $query = "
        SELECT *
        FROM   biblio
        ORDER BY timestamp DESC
        LIMIT  0,".$limit;

    my $sth = $dbh->prepare($query);
    $sth->execute;
    my @results;
    while(my $data = $sth->fetchrow_hashref){
        push @results,$data;
    }
    return \@results;
}

END { }    # module clean-up code here (global destructor)

1;

__END__

=back

=head1 AUTHOR

Koha Developement team <info@koha.org>

=cut
