#!/usr/bin/perl

# $Id$

#script to recieve orders
#written by chris@katipo.co.nz 24/2/2000


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


=head1 NAME

parcel.pl

=head1 DESCRIPTION
This script shows all orders receipt or pending for a given supplier.
It allows to write an order as 'received' when he arrives.

=head1 CGI PARAMETERS

=over 4

=item supplierid
To know the supplier this script has to show orders.

=item code
is the bookseller invoice number.

=item freight


=item gst


=item datereceived
To filter the results list on this given date.

=back

=cut

use C4::Auth;
use C4::Acquisition;
use C4::Bookseller;
use C4::Biblio;
use CGI;
use C4::Output;
use C4::Date;

use strict;

my $input=new CGI;
my $supplierid=$input->param('supplierid');
my @booksellers=GetBookSeller($supplierid);
my $count = scalar @booksellers;

my $invoice=$input->param('invoice') || '';
my $freight=$input->param('freight');
my $gst=$input->param('gst');
my $datereceived=$input->param('datereceived') || format_date(join "-",Date::Calc::Today());
my $code=$input->param('code');

my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "acqui/parcel.tmpl",
                 query => $input,
                 type => "intranet",
                 authnotrequired => 0,
                 flagsrequired => {acquisition => 1},
                 debug => 1,
});
my @parcelitems=GetParcel($supplierid,$invoice,$datereceived);
my $countlines = scalar @parcelitems;

my $totalprice=0;
my $totalfreight=0;
my $totalquantity=0;
my $total;
my $tototal;
my $toggle;
my @loop_received = ();
for (my $i=0;$i<$countlines;$i++){
    $total=($parcelitems[$i]->{'unitprice'} + $parcelitems[$i]->{'freight'}) * $parcelitems[$i]->{'quantityreceived'};   #weird, are the freight fees counted by book? (pierre)
    $parcelitems[$i]->{'unitprice'}+=0;
    my %line;
    if ($toggle==0){
        $line{color}='#EEEEEE';
        $toggle=1;
    } else {
            $line{color}='white';
            $toggle=0;
    }
    %line = %{$parcelitems[$i]};
    $line{invoice} = $invoice;
    $line{gst} = $gst;
    $line{total} = $total;
    $line{supplierid} = $supplierid;
    push @loop_received, \%line;
    $totalprice+=$parcelitems[$i]->{'unitprice'};
    $totalfreight+=$parcelitems[$i]->{'freight'};
    $totalquantity+=$parcelitems[$i]->{'quantityreceived'};
    $tototal+=$total;
}
my $pendingorders = GetPendingOrders($supplierid);
my $countpendings = scalar @$pendingorders;

my @loop_orders = ();
for (my $i=0;$i<$countpendings;$i++){
    my %line;
    if ($toggle==0){
        $line{color}='#EEEEEE';
        $toggle=1;
    } else {
            $line{color}='white';
            $toggle=0;
    }
    %line = %{$pendingorders->[$i]};
    $line{ecost} = sprintf("%.2f",$line{ecost});
    $line{unitprice} = sprintf("%.2f",$line{unitprice});
    $line{invoice} = $invoice;
    $line{gst} = $gst;
    $line{total} = $total;
    $line{supplierid} = $supplierid;
    push @loop_orders, \%line;
}

$totalfreight=$freight;
$tototal=$tototal+$freight;

$template->param(invoice => $invoice,
						datereceived => $datereceived,
						formatteddatereceived => format_date($datereceived),
                        name => $booksellers[0]->{'name'},
                        supplierid => $supplierid,
                        gst => $gst,
                        freight => $freight,
                        invoice => $invoice,
                        countreceived => $countlines,
                        loop_received => \@loop_received,
                        countpending => $countpendings,
                        loop_orders => \@loop_orders,
                        totalprice => $totalprice,
                        totalfreight => $totalfreight,
                        totalquantity => $totalquantity,
                        tototal => $tototal,
                        gst => $gst,
                        grandtot => $tototal+$gst,
                        intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
        intranetstylesheet => C4::Context->preference("intranetstylesheet"),
        IntranetNav => C4::Context->preference("IntranetNav"),
                        );
output_html_with_http_headers $input, $cookie, $template->output;
