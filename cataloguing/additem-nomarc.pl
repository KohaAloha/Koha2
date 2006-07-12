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

# $Log$
# Revision 1.2  2006/07/12 17:17:12  toins
# getitemtypes renamed to GetItemTypes
#
# Revision 1.1  2006/01/17 16:40:54  tipaul
# moving acqui.simple directory to cataloguing, as acqui.simple contains cataloguing scripts...
#
# Revision 1.8  2005/10/26 09:11:34  tipaul
# big commit, still breaking things...
#
# * synch with rel_2_2. Probably the last non manual synch, as rel_2_2 should not be modified deeply.
# * code cleaning (cleaning warnings from perl -w) continued
#
# Revision 1.4.2.1  2005/03/25 12:52:44  tipaul
# needs "editcatalogue" flag, not "catalogue"
#
# Revision 1.4  2004/11/19 16:41:49  tipaul
# improving behaviour when MARC=OFF
#
# Revision 1.3  2004/08/13 16:37:25  tipaul
# adding frameworkcode to API in some subs
#
# Revision 1.2  2003/05/11 06:59:11  rangi
# Mostly templated.
# Still needs some work
#

use CGI;
use strict;
use C4::Biblio;
use C4::Koha;
use C4::Output;
use HTML::Template;
use C4::Auth;
use C4::Interface::CGI::Output;

my $input        = new CGI;
my $biblionumber = $input->param('biblionumber');
my $error        = $input->param('error');
my $maxbarcode;
my $isbn;
my $bibliocount;
my @biblios;
my $biblioitemcount;
my @biblioitems;
my $branchcount;
# my @branches;
# my %branchnames;
my $itemcount;
my @items;

if ( !$biblionumber ) {
	print $input->redirect('addbooks.pl');
}
else {
	my $input = new CGI;
	my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
		{
			template_name   => "acqui.simple/additem-nomarc.tmpl",
			query           => $input,
			type            => "intranet",
			authnotrequired => 0,
			flagsrequired   => { editcatalogue => 1 },
			debug           => 1,
		}
	);
	( $bibliocount, @biblios ) = &getbiblio($biblionumber);

	if ( !$bibliocount ) {
		print $input->redirect('addbooks.pl');
	}
	else {
		( $biblioitemcount, @biblioitems ) = &getbiblioitembybiblionumber($biblionumber);
		my $branches = getbranches;
		my @branchloop;
		foreach my $thisbranch (sort keys %$branches) {
			my %row =(value => $thisbranch,
						branchname => $branches->{$thisbranch}->{'branchname'},
					);
			push @branchloop, \%row;
		}
		my $itemtypes = &GetItemTypes;
		my @itemtypeloop;
		foreach my $thisitemtype (sort keys %$itemtypes) {
			my %row =(value => $thisitemtype,
						description => $itemtypes->{$thisitemtype}->{'description'},
					);
			push @itemtypeloop, \%row;
		}
		if ( $error eq "nobarcode" ) {
			$template->param( NOBARCODE => 1 );
		}
		elsif ( $error eq "nobiblioitem" ) {
			$template->param( NOBIBLIOITEM => 1 );
		}
		elsif ( $error eq "barcodeinuse" ) {
			$template->param( BARCODEINUSE => 1 );
		}    # elsif

		for ( my $i = 0 ; $i < $biblioitemcount ; $i++ ) {
			if ( $biblioitems[$i]->{'itemtype'} eq "WEB" ) {
				$biblioitems[$i]->{'WEB'} = 1;
			}
			$biblioitems[$i]->{'dewey'} =~ /(\d*\.\d\d)/;
			$biblioitems[$i]->{'dewey'} = $1;
			( $itemcount, @items ) = &getitemsbybiblioitem( $biblioitems[$i]->{'biblioitemnumber'} );
			$biblioitems[$i]->{'items'} = \@items;
		}    # for
		$template->param(
			BIBNUM    => $biblionumber,
			AUTHOR    => $biblios[0]->{'author'},
			TITLE     => $biblios[0]->{'title'},
			COPYRIGHT => $biblios[0]->{'copyrightdate'},
			SERIES    => $biblios[0]->{'seriestitle'},
			NOTES     => $biblios[0]->{'notes'},
			BIBITEMS  => \@biblioitems,
			branchloop  => \@branchloop,
			itemtypeloop => \@itemtypeloop,

    ( $bibliocount, @biblios ) = &getbiblio($biblionumber);

    if ( !$bibliocount ) {
        print $input->redirect('addbooks.pl');
    }
    else {

        ( $biblioitemcount, @biblioitems ) =
          &getbiblioitembybiblionumber($biblionumber);
        ( $branchcount,   @branches )  = &branches;
        ( $itemtypecount, @itemtypes ) = &GetItemTypes;

        for ( my $i = 0 ; $i < $itemtypecount ; $i++ ) {
            $itemtypedescriptions{ $itemtypes[$i]->{'itemtype'} } =
              $itemtypes[$i]->{'description'};
        }    # for

        for ( my $i = 0 ; $i < $branchcount ; $i++ ) {
            $branchnames{ $branches[$i]->{'branchcode'} } =
              $branches[$i]->{'branchname'};
        }    # for

        #	print $input->header;
        #	print startpage();
        #	print startmenu('acquisitions');
        my $input = new CGI;
        my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
            {
                template_name   => "acqui.simple/additem-nomarc.tmpl",
                query           => $input,
                type            => "intranet",
                authnotrequired => 0,
                flagsrequired   => { editcatalogue => 1 },
                debug           => 1,
            }
        );

        if ( $error eq "nobarcode" ) {
            $template->param( NOBARCODE => 1 );
        }
        elsif ( $error eq "nobiblioitem" ) {
            $template->param( NOBIBLIOITEM => 1 );
        }
        elsif ( $error eq "barcodeinuse" ) {
            $template->param( BARCODEINUSE => 1 );
        }    # elsif

        for ( my $i = 0 ; $i < $biblioitemcount ; $i++ ) {
            if ( $biblioitems[$i]->{'itemtype'} eq "WEB" ) {
                $biblioitems[$i]->{'WEB'} = 1;

            }
            $biblioitems[$i]->{'dewey'} =~ /(\d*\.\d\d)/;
            $biblioitems[$i]->{'dewey'} = $1;
            ( $itemcount, @items ) =
              &getitemsbybiblioitem( $biblioitems[$i]->{'biblioitemnumber'} );
            $biblioitems[$i]->{'items'} = \@items;
        }    # for
        $template->param(
            BIBNUM    => $biblionumber,
            AUTHOR    => $biblios[0]->{'author'},
            TITLE     => $biblios[0]->{'title'},
            COPYRIGHT => $biblios[0]->{'copyrightdate'},
            SERIES    => $biblios[0]->{'seriestitle'},
            NOTES     => $biblios[0]->{'notes'},
            BIBITEMS  => \@biblioitems,
            BRANCHES  => \@branches,
            ITEMTYPES => \@itemtypes,

        );

        output_html_with_http_headers $input, $cookie, $template->output;
    }    # if
}    # if
