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


use strict;
require Exporter;
use CGI;
use C4::Auth;
use C4::Branch;
use C4::Koha;
use C4::Serials;    #uses getsubscriptionfrom biblionumber
use C4::Output;
use C4::Biblio;
use C4::Items;
use C4::Dates qw/format_date/;
use C4::XISBN qw(get_xisbns get_biblionumber_from_isbn get_biblio_from_xisbn);
use C4::Amazon;
use C4::Review;
use C4::Serials;
use C4::Members;
use C4::XSLT;

my $query = new CGI;
my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-detail.tmpl",
        query           => $query,
        type            => "opac",
        authnotrequired => 1,
        flagsrequired   => { borrow => 1 },
    }
);

my $biblionumber = $query->param('biblionumber') || $query->param('bib');
$template->param( biblionumber => $biblionumber );
# XSLT processing of some stuff
if (C4::Context->preference("XSLTResultsDisplay") ) {
    my $newxmlrecord = XSLTParse4Display($biblionumber,'Detail');
    $template->param('XSLTBloc' => $newxmlrecord);
}

# change back when ive fixed request.pl
my @all_items = &GetItemsInfo( $biblionumber, 'opac' );
my @items;
@items = @all_items unless C4::Context->preference('hidelostitems');

if (C4::Context->preference('hidelostitems')) {
    # Hide host items
    for my $itm (@all_items) {
        push @items, $itm unless $itm->{itemlost};
    }
}
my $dat = &GetBiblioData($biblionumber);

if (!$dat) {
    print $query->redirect("/cgi-bin/koha/koha-tmpl/errors/404.pl");
    exit;
}
my $imgdir = getitemtypeimagesrc();
my $itemtypes = GetItemTypes();
# imageurl:
my $itemtype = $dat->{'itemtype'};
if ( $itemtype ) {
    $dat->{'imageurl'}    = $imgdir."/".$itemtypes->{$itemtype}->{'imageurl'};
    $dat->{'description'} = $itemtypes->{$itemtype}->{'description'};
}

#coping with subscriptions
my $subscriptionsnumber = CountSubscriptionFromBiblionumber($biblionumber);
my @subscriptions       =
  GetSubscriptions( $dat->{title}, $dat->{issn}, $biblionumber );
my @subs;
$dat->{'serial'}=1 if $subscriptionsnumber;
foreach my $subscription (@subscriptions) {
    my %cell;
    $cell{subscriptionid}    = $subscription->{subscriptionid};
    $cell{subscriptionnotes} = $subscription->{notes};
    $cell{branchcode}        = $subscription->{branchcode};
    $cell{hasalert}          = $subscription->{hasalert};
    #get the three latest serials.
    $cell{latestserials} =
      GetLatestSerials( $subscription->{subscriptionid}, 3 );
    push @subs, \%cell;
}

$dat->{'count'} = scalar(@items);

#adding RequestOnOpac filter to allow or not the display of plce reserve button
# FIXME - use me or delete me.
my $RequestOnOpac;
if (C4::Context->preference("RequestOnOpac")) {
    $RequestOnOpac = 1;
}

my $norequests = 1;
foreach my $itm (@items) {
     $norequests = 0 && $norequests
       if ( (not $itm->{'wthdrawn'} )
         || (not $itm->{'itemlost'} )
         || (not $itm->{'itemnotforloan'} )
         || ($itm->{'itemnumber'} ) );
        $itm->{ $itm->{'publictype'} } = 1;
    $itm->{datedue} = format_date($itm->{datedue});
    $itm->{datelastseen} = format_date($itm->{datelastseen});

    #get collection code description, too
    $itm->{'ccode'}  = GetAuthorisedValueDesc('','',   $itm->{'ccode'} ,'','','CCODE');
    $itm->{'location_description'} = GetAuthorisedValueDesc('','',   $itm->{'location'} ,'','','LOC');
    $itm->{'imageurl'}    = $imgdir."/".$itemtypes->{ $itm->{itype} }->{'imageurl'};     
    $itm->{'description'} = $itemtypes->{$itemtype}->{'description'};

}

$template->param( norequests => $norequests, RequestOnOpac=>$RequestOnOpac );

## get notes and subjects from MARC record
    my $dbh              = C4::Context->dbh;
    my $marcflavour      = C4::Context->preference("marcflavour");
    my $record           = GetMarcBiblio($biblionumber);
    my $marcnotesarray   = GetMarcNotes( $record, $marcflavour );
    my $marcauthorsarray = GetMarcAuthors( $record, $marcflavour );
    my $marcsubjctsarray = GetMarcSubjects( $record, $marcflavour );
    my $marcseriesarray  = GetMarcSeries($record,$marcflavour);
    my $marcurlsarray   = GetMarcUrls($record,$marcflavour);

    $template->param(
        MARCNOTES   => $marcnotesarray,
        MARCSUBJCTS => $marcsubjctsarray,
        MARCAUTHORS => $marcauthorsarray,
        MARCSERIES  => $marcseriesarray,
        MARCURLS    => $marcurlsarray,
    );

foreach ( keys %{$dat} ) {
    $template->param( "$_" => $dat->{$_} . "" );
}

# COinS format FIXME: for books Only
my $coins_format;
my $fmt = substr $record->leader(), 6,2;
my $fmts;
$fmts->{'am'} = 'book';
$coins_format = $fmts->{$fmt};
$template->param(
	ocoins_format => $coins_format,
);

my $reviews = getreviews( $biblionumber, 1 );
foreach ( @$reviews ) {
    my $borrower_number_review = $_->{borrowernumber};
    my $borrowerData           = GetMember($borrower_number_review,'borrowernumber');
    # setting some borrower info into this hash
    $_->{title}     = $borrowerData->{'title'};
    $_->{surname}   = $borrowerData->{'surname'};
    $_->{firstname} = $borrowerData->{'firstname'};
    $_->{datereviewed} = format_date($_->{datereviewed});
}


if(C4::Context->preference("ISBD")) {
	$template->param(ISBD => 1);
}

$template->param(
    ITEM_RESULTS        => \@items,
    subscriptionsnumber => $subscriptionsnumber,
    biblionumber        => $biblionumber,
    subscriptions       => \@subs,
    subscriptionsnumber => $subscriptionsnumber,
    reviews             => $reviews
);

# XISBN Stuff
my $xisbn=$dat->{'isbn'};
$xisbn =~ s/(p|-| |:)//g;
$template->param(amazonisbn => $xisbn);
if (C4::Context->preference("OPACFRBRizeEditions")==1) {
    eval {
        $template->param(
            xisbn => $xisbn,
            XISBNS => get_xisbns($xisbn)
        );
    };
    if ($@) { warn "XISBN Failed $@"; }
}
# Amazon.com Stuff
if ( C4::Context->preference("OPACAmazonContent") == 1 ) {
    my $similar_products_exist;
    my $amazon_details = &get_amazon_details( $xisbn );
    my $item_attributes = \%{$amazon_details->{Items}->{Item}->{ItemAttributes}};
    my $customer_reviews = \@{$amazon_details->{Items}->{Item}->{CustomerReviews}->{Review}};
    for my $one_review (@$customer_reviews) {
        $one_review->{Date} = format_date($one_review->{Date});
    }
    my @similar_products;
    for my $similar_product (@{$amazon_details->{Items}->{Item}->{SimilarProducts}->{SimilarProduct}}) {
        # do we have any of these isbns in our collection?
        my $similar_biblionumbers = get_biblionumber_from_isbn($similar_product->{ASIN});
        # verify that there is at least one similar item
        $similar_products_exist++ if ${@$similar_biblionumbers}[0];
        push @similar_products, +{ similar_biblionumbers => $similar_biblionumbers, title => $similar_product->{Title}, ASIN => $similar_product->{ASIN}  };
    }
    my $editorial_reviews = \@{$amazon_details->{Items}->{Item}->{EditorialReviews}->{EditorialReview}};
    my $average_rating = $amazon_details->{Items}->{Item}->{CustomerReviews}->{AverageRating};
    $template->param( OPACAmazonSimilarItems => $similar_products_exist );
    $template->param( amazon_average_rating => $average_rating * 20);
    $template->param( AMAZON_CUSTOMER_REVIEWS    => $customer_reviews );
    $template->param( AMAZON_SIMILAR_PRODUCTS => \@similar_products );
    $template->param( AMAZON_EDITORIAL_REVIEWS    => $editorial_reviews );
}
# Shelf Browser Stuff
if (C4::Context->preference("OPACShelfBrowser")) {
# pick the first itemnumber unless one was selected by the user
my $starting_itemnumber = $query->param('shelfbrowse_itemnumber'); # || $items[0]->{itemnumber};
$template->param( OpenOPACShelfBrowser => 1) if $starting_itemnumber;
# find the right cn_sort value for this item
my ($starting_cn_sort, $starting_homebranch, $starting_location);
my $sth_get_cn_sort = $dbh->prepare("SELECT cn_sort,homebranch,location from items where itemnumber=?");
$sth_get_cn_sort->execute($starting_itemnumber);
my $branches = GetBranches();
while (my $result = $sth_get_cn_sort->fetchrow_hashref()) {
    $starting_cn_sort = $result->{'cn_sort'};
    $starting_homebranch->{code} = $result->{'homebranch'};
    $starting_homebranch->{description} = $branches->{$result->{'homebranch'}}{branchname};
    $starting_location->{code} = $result->{'location'};
    $starting_location->{description} = GetAuthorisedValueDesc('','',   $result->{'location'} ,'','','LOC');

}

## List of Previous Items
# order by cn_sort, which should include everything we need for ordering purposes (though not
# for limits, those need to be handled separately
my $sth_shelfbrowse_previous = $dbh->prepare("SELECT * FROM items WHERE CONCAT(cn_sort,itemnumber) <= ? AND homebranch=? AND location=? ORDER BY CONCAT(cn_sort,itemnumber) DESC LIMIT 3");
$sth_shelfbrowse_previous->execute($starting_cn_sort.$starting_itemnumber, $starting_homebranch->{code}, $starting_location->{code});
my @previous_items;
while (my $this_item = $sth_shelfbrowse_previous->fetchrow_hashref()) {
    my $sth_get_biblio = $dbh->prepare("SELECT biblio.*,biblioitems.isbn AS isbn FROM biblio LEFT JOIN biblioitems ON biblio.biblionumber=biblioitems.biblionumber WHERE biblio.biblionumber=?");
    $sth_get_biblio->execute($this_item->{biblionumber});
    while (my $this_biblio = $sth_get_biblio->fetchrow_hashref()) {
        $this_item->{'title'} = $this_biblio->{'title'};
        $this_item->{'isbn'} = $this_biblio->{'isbn'};
    }
    unshift @previous_items, $this_item;
}
my $throwaway = pop @previous_items;
## List of Next Items
my $sth_shelfbrowse_next = $dbh->prepare("SELECT * FROM items WHERE CONCAT(cn_sort,itemnumber) >= ? AND homebranch=? AND location=? ORDER BY CONCAT(cn_sort,itemnumber) ASC LIMIT 3");
$sth_shelfbrowse_next->execute($starting_cn_sort.$starting_itemnumber, $starting_homebranch->{code}, $starting_location->{code});
my @next_items;
while (my $this_item = $sth_shelfbrowse_next->fetchrow_hashref()) {
    my $sth_get_biblio = $dbh->prepare("SELECT biblio.*,biblioitems.isbn AS isbn FROM biblio LEFT JOIN biblioitems ON biblio.biblionumber=biblioitems.biblionumber WHERE biblio.biblionumber=?");
    $sth_get_biblio->execute($this_item->{biblionumber});
    while (my $this_biblio = $sth_get_biblio->fetchrow_hashref()) {
        $this_item->{'title'} = $this_biblio->{'title'};
        $this_item->{'isbn'} = $this_biblio->{'isbn'};
    }
    push @next_items, $this_item;
}

# alas, these won't auto-vivify, see http://www.perlmonks.org/?node_id=508481
my $shelfbrowser_next_itemnumber = $next_items[-1]->{itemnumber} if @next_items;
my $shelfbrowser_next_biblionumber = $next_items[-1]->{biblionumber} if @next_items;

$template->param(
    starting_homebranch => $starting_homebranch->{description},
    starting_location => $starting_location->{description},
    shelfbrowser_prev_itemnumber => $previous_items[0]->{itemnumber},
    shelfbrowser_next_itemnumber => $shelfbrowser_next_itemnumber,
    shelfbrowser_prev_biblionumber => $previous_items[0]->{biblionumber},
    shelfbrowser_next_biblionumber => $shelfbrowser_next_biblionumber,
    PREVIOUS_SHELF_BROWSE => \@previous_items,
    NEXT_SHELF_BROWSE => \@next_items,
);
}

output_html_with_http_headers $query, $cookie, $template->output;
