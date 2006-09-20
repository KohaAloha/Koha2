#!/usr/bin/perl

# $Id$

#script to show suppliers and orders
#written by chris@katipo.co.nz 23/2/2000


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
use C4::Auth;
use C4::Biblio;
use CGI;
use C4::Interface::CGI::Output;
use C4::Context;
use C4::Date;
use C4::Acquisition;

my $query=new CGI;
my $dbh = C4::Context->dbh;
my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "acqui/select-late.tmpl",
			     query => $query,
			     type => "intranet",
			     authnotrequired => 0,
			     flagsrequired => {acquisition => 1},
			     debug => 1,
			     });

my $supplier=$query->param('id');
my @suppliers=GetBookSeller($supplier);
my $count = scalar @suppliers;

my $sth = $dbh->prepare("select s.serialseq from serial s, subscription u where s.subscriptionid = u.subscriptionid and u.aqbooksellerid = ? and s.status = 2");

$sth->execute($supplier);
my  @final;
while (my $sol = $sth->fetchrow_hashref)
{
    push @final, $sol;
}

$template->param(@loop_sol => \@final);

my $colour='#EEEEEE';
my $toggle=0;
my @loop_suppliers;
for (my $i=0; $i<$count; $i++) {
	my $orders = GetPendingOrders($suppliers[$i]->{'id'});
    my $ordcount = scalar @$orders;
    
	my %line;
	if ($toggle==0){
		$line{color}='#EEEEEE';
		$toggle=1;
	} else {
		$line{color}='white';
		$toggle=0;
	}
	$line{id} =$suppliers[$i]->{'id'};
	$line{name} = $suppliers[$i]->{'name'};
	$line{active} = $suppliers[$i]->{'active'};
	$line{total} = $orders->[0]->{'count(*)'};
	$line{authorisedby} = $orders->[0]->{'authorisedby'};
	$line{entrydate} = $orders->[0]->{'entrydate'};
	my @loop_basket;
	for (my $i2=0;$i2<$ordcount;$i2++){
		my %inner_line;
		$inner_line{basketno} =$orders->[$i2]->{'basketno'};
		$inner_line{total} =$orders->[$i2]->{'count(*)'};
		$inner_line{authorisedby} = $orders->[$i2]->{'authorisedby'};
		$inner_line{entrydate} = format_date($orders->[$i2]->{'entrydate'});
		push @loop_basket, \%inner_line;
	}
	$line{loop_basket} = \@loop_basket;
	push @loop_suppliers, \%line;
}
$template->param(loop_suppliers => \@loop_suppliers,
						supplier => $supplier,
						count => $count,
						intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
						);

output_html_with_http_headers $query, $cookie, $template->output;
