#!/usr/bin/perl

#script to provide virtualshelf management
# WARNING: This file uses 4-character tabs!
#
# $Header$
#
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
use C4::Biblio;
use CGI;
use C4::VirtualShelves;
use C4::Circulation;
use C4::Auth;
use C4::Output;

my $query        = new CGI;
my $biblionumber = $query->param('biblionumber');
my $shelfnumber  = $query->param('shelfnumber');
my $newvirtualshelf = $query->param('newvirtualshelf');
my $category     = $query->param('category');

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-addbybiblionumber.tmpl",
        query           => $query,
        type            => "opac",
        authnotrequired => 1,
    }
);

$shelfnumber = AddShelf( '', $newvirtualshelf, $loggedinuser, $category ) if $newvirtualshelf;

# to know if we had to add more than one biblio.
my $multiple = 0;
$multiple = 1 if $biblionumber =~ /^(\d*\/)*$/;


if ($shelfnumber) {

    if ($multiple){
        foreach (split /\//,$biblionumber){
            &AddToShelfFromBiblio($_,$shelfnumber);
        }
    }
    else {
        &AddToShelfFromBiblio( $biblionumber, $shelfnumber );
    }
    print $query->header;
    print "<html><body onload=\"window.close();\"></body></html>";
    exit;
}
else {
    my ($shelflist) = GetShelves( $loggedinuser, 3 );
    my @shelvesloop;
    my %shelvesloop;
    foreach my $element ( sort keys %$shelflist ) {
        push( @shelvesloop, $element );
            $shelvesloop{$element} = $shelflist->{$element}->{'shelfname'};
    }

    my $CGIvirtualshelves;
    if ( @shelvesloop > 0 ) {
        $CGIvirtualshelves = CGI::scrolling_list (
            -name     => 'shelfnumber',
            -values   => \@shelvesloop,
            -labels   => \%shelvesloop,
            -size     => 1,
            -tabindex => '',
            -multiple => 0
        );
    }

    if ( $multiple ) {
        my @biblios;
        foreach (split /\//,$biblionumber){
            my $data = GetBiblioData($_);
            push @biblios,$data;
        }
        $template->param (
            multiple => 1,
            biblionumber => $biblionumber,
            total    => scalar @biblios,
            biblios  => \@biblios,
        );
    }
    else { # just one to add.
        my $data = GetBiblioData( $biblionumber );
        $template->param (
            biblionumber => $biblionumber,
            title        => $data->{'title'},
            author       => $data->{'author'},
        );
    }

    $template->param (
        CGIvirtualshelves       => $CGIvirtualshelves,
    );

    output_html_with_http_headers $query, $cookie, $template->output;
}
