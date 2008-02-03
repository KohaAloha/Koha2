package C4::Koha;

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
use vars qw($VERSION @ISA @EXPORT $DEBUG);

BEGIN {
	$VERSION = 3.01;
	require Exporter;
	@ISA    = qw(Exporter);
	@EXPORT = qw(
		&slashifyDate
		&DisplayISBN
		&subfield_is_koha_internal_p
		&GetPrinters &GetPrinter
		&GetItemTypes &getitemtypeinfo
		&GetCcodes
		&get_itemtypeinfos_of
		&getframeworks &getframeworkinfo
		&getauthtypes &getauthtype
		&getallthemes
		&getFacets
		&displayServers
		&getnbpages
		&getitemtypeimagesrcfromurl
		&get_infos_of
		&get_notforloan_label_of
		&getitemtypeimagedir
		&getitemtypeimagesrc
		&GetAuthorisedValues
		&GetKohaAuthorisedValues
		&GetAuthValCode
		&GetManagedTagSubfields

		$DEBUG
	);
	$DEBUG = 0;
}

=head1 NAME

    C4::Koha - Perl Module containing convenience functions for Koha scripts

=head1 SYNOPSIS

  use C4::Koha;


=head1 DESCRIPTION

    Koha.pm provides many functions for Koha scripts.

=head1 FUNCTIONS

=over 2

=cut
=head2 slashifyDate

  $slash_date = &slashifyDate($dash_date);

    Takes a string of the form "DD-MM-YYYY" (or anything separated by
    dashes), converts it to the form "YYYY/MM/DD", and returns the result.

=cut

sub slashifyDate {

    # accepts a date of the form xx-xx-xx[xx] and returns it in the
    # form xx/xx/xx[xx]
    my @dateOut = split( '-', shift );
    return ("$dateOut[2]/$dateOut[1]/$dateOut[0]");
}


=head2 DisplayISBN

    my $string = DisplayISBN( $isbn );

=cut

sub DisplayISBN {
    my ($isbn) = @_;
    if (length ($isbn)<13){
    my $seg1;
    if ( substr( $isbn, 0, 1 ) <= 7 ) {
        $seg1 = substr( $isbn, 0, 1 );
    }
    elsif ( substr( $isbn, 0, 2 ) <= 94 ) {
        $seg1 = substr( $isbn, 0, 2 );
    }
    elsif ( substr( $isbn, 0, 3 ) <= 995 ) {
        $seg1 = substr( $isbn, 0, 3 );
    }
    elsif ( substr( $isbn, 0, 4 ) <= 9989 ) {
        $seg1 = substr( $isbn, 0, 4 );
    }
    else {
        $seg1 = substr( $isbn, 0, 5 );
    }
    my $x = substr( $isbn, length($seg1) );
    my $seg2;
    if ( substr( $x, 0, 2 ) <= 19 ) {

        # if(sTmp2 < 10) sTmp2 = "0" sTmp2;
        $seg2 = substr( $x, 0, 2 );
    }
    elsif ( substr( $x, 0, 3 ) <= 699 ) {
        $seg2 = substr( $x, 0, 3 );
    }
    elsif ( substr( $x, 0, 4 ) <= 8399 ) {
        $seg2 = substr( $x, 0, 4 );
    }
    elsif ( substr( $x, 0, 5 ) <= 89999 ) {
        $seg2 = substr( $x, 0, 5 );
    }
    elsif ( substr( $x, 0, 6 ) <= 9499999 ) {
        $seg2 = substr( $x, 0, 6 );
    }
    else {
        $seg2 = substr( $x, 0, 7 );
    }
    my $seg3 = substr( $x, length($seg2) );
    $seg3 = substr( $seg3, 0, length($seg3) - 1 );
    my $seg4 = substr( $x, -1, 1 );
    return "$seg1-$seg2-$seg3-$seg4";
    } else {
      my $seg1;
      $seg1 = substr( $isbn, 0, 3 );
      my $seg2;
      if ( substr( $isbn, 3, 1 ) <= 7 ) {
          $seg2 = substr( $isbn, 3, 1 );
      }
      elsif ( substr( $isbn, 3, 2 ) <= 94 ) {
          $seg2 = substr( $isbn, 3, 2 );
      }
      elsif ( substr( $isbn, 3, 3 ) <= 995 ) {
          $seg2 = substr( $isbn, 3, 3 );
      }
      elsif ( substr( $isbn, 3, 4 ) <= 9989 ) {
          $seg2 = substr( $isbn, 3, 4 );
      }
      else {
          $seg2 = substr( $isbn, 3, 5 );
      }
      my $x = substr( $isbn, length($seg2) +3);
      my $seg3;
      if ( substr( $x, 0, 2 ) <= 19 ) {
  
          # if(sTmp2 < 10) sTmp2 = "0" sTmp2;
          $seg3 = substr( $x, 0, 2 );
      }
      elsif ( substr( $x, 0, 3 ) <= 699 ) {
          $seg3 = substr( $x, 0, 3 );
      }
      elsif ( substr( $x, 0, 4 ) <= 8399 ) {
          $seg3 = substr( $x, 0, 4 );
      }
      elsif ( substr( $x, 0, 5 ) <= 89999 ) {
          $seg3 = substr( $x, 0, 5 );
      }
      elsif ( substr( $x, 0, 6 ) <= 9499999 ) {
          $seg3 = substr( $x, 0, 6 );
      }
      else {
          $seg3 = substr( $x, 0, 7 );
      }
      my $seg4 = substr( $x, length($seg3) );
      $seg4 = substr( $seg4, 0, length($seg4) - 1 );
      my $seg5 = substr( $x, -1, 1 );
      return "$seg1-$seg2-$seg3-$seg4-$seg5";       
    }    
}

# FIXME.. this should be moved to a MARC-specific module
sub subfield_is_koha_internal_p ($) {
    my ($subfield) = @_;

    # We could match on 'lib' and 'tab' (and 'mandatory', & more to come!)
    # But real MARC subfields are always single-character
    # so it really is safer just to check the length

    return length $subfield != 1;
}

=head2 GetItemTypes

  $itemtypes = &GetItemTypes();

Returns information about existing itemtypes.

build a HTML select with the following code :

=head3 in PERL SCRIPT

    my $itemtypes = GetItemTypes;
    my @itemtypesloop;
    foreach my $thisitemtype (sort keys %$itemtypes) {
        my $selected = 1 if $thisitemtype eq $itemtype;
        my %row =(value => $thisitemtype,
                    selected => $selected,
                    description => $itemtypes->{$thisitemtype}->{'description'},
                );
        push @itemtypesloop, \%row;
    }
    $template->param(itemtypeloop => \@itemtypesloop);

=head3 in TEMPLATE

    <form action='<!-- TMPL_VAR name="script_name" -->' method=post>
        <select name="itemtype">
            <option value="">Default</option>
        <!-- TMPL_LOOP name="itemtypeloop" -->
            <option value="<!-- TMPL_VAR name="value" -->" <!-- TMPL_IF name="selected" -->selected<!-- /TMPL_IF -->><!-- TMPL_VAR name="description" --></option>
        <!-- /TMPL_LOOP -->
        </select>
        <input type=text name=searchfield value="<!-- TMPL_VAR name="searchfield" -->">
        <input type="submit" value="OK" class="button">
    </form>

=cut

sub GetItemTypes {

    # returns a reference to a hash of references to branches...
    my %itemtypes;
    my $dbh   = C4::Context->dbh;
    my $query = qq|
        SELECT *
        FROM   itemtypes
    |;
    my $sth = $dbh->prepare($query);
    $sth->execute;
    while ( my $IT = $sth->fetchrow_hashref ) {
        $itemtypes{ $IT->{'itemtype'} } = $IT;
    }
    return ( \%itemtypes );
}

sub get_itemtypeinfos_of {
    my @itemtypes = @_;

    my $query = '
SELECT itemtype,
       description,
       imageurl,
       notforloan
  FROM itemtypes
  WHERE itemtype IN (' . join( ',', map( { "'" . $_ . "'" } @itemtypes ) ) . ')
';

    return get_infos_of( $query, 'itemtype' );
}

# this is temporary until we separate collection codes and item types
sub GetCcodes {
    my $count = 0;
    my @results;
    my $dbh = C4::Context->dbh;
    my $sth =
      $dbh->prepare(
        "SELECT * FROM authorised_values ORDER BY authorised_value");
    $sth->execute;
    while ( my $data = $sth->fetchrow_hashref ) {
        if ( $data->{category} eq "CCODE" ) {
            $count++;
            $results[$count] = $data;

            #warn "data: $data";
        }
    }
    $sth->finish;
    return ( $count, @results );
}

=head2 getauthtypes

  $authtypes = &getauthtypes();

Returns information about existing authtypes.

build a HTML select with the following code :

=head3 in PERL SCRIPT

my $authtypes = getauthtypes;
my @authtypesloop;
foreach my $thisauthtype (keys %$authtypes) {
    my $selected = 1 if $thisauthtype eq $authtype;
    my %row =(value => $thisauthtype,
                selected => $selected,
                authtypetext => $authtypes->{$thisauthtype}->{'authtypetext'},
            );
    push @authtypesloop, \%row;
}
$template->param(itemtypeloop => \@itemtypesloop);

=head3 in TEMPLATE

<form action='<!-- TMPL_VAR name="script_name" -->' method=post>
    <select name="authtype">
    <!-- TMPL_LOOP name="authtypeloop" -->
        <option value="<!-- TMPL_VAR name="value" -->" <!-- TMPL_IF name="selected" -->selected<!-- /TMPL_IF -->><!-- TMPL_VAR name="authtypetext" --></option>
    <!-- /TMPL_LOOP -->
    </select>
    <input type=text name=searchfield value="<!-- TMPL_VAR name="searchfield" -->">
    <input type="submit" value="OK" class="button">
</form>


=cut

sub getauthtypes {

    # returns a reference to a hash of references to authtypes...
    my %authtypes;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("select * from auth_types order by authtypetext");
    $sth->execute;
    while ( my $IT = $sth->fetchrow_hashref ) {
        $authtypes{ $IT->{'authtypecode'} } = $IT;
    }
    return ( \%authtypes );
}

sub getauthtype {
    my ($authtypecode) = @_;

    # returns a reference to a hash of references to authtypes...
    my %authtypes;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("select * from auth_types where authtypecode=?");
    $sth->execute($authtypecode);
    my $res = $sth->fetchrow_hashref;
    return $res;
}

=head2 getframework

  $frameworks = &getframework();

Returns information about existing frameworks

build a HTML select with the following code :

=head3 in PERL SCRIPT

my $frameworks = frameworks();
my @frameworkloop;
foreach my $thisframework (keys %$frameworks) {
    my $selected = 1 if $thisframework eq $frameworkcode;
    my %row =(value => $thisframework,
                selected => $selected,
                description => $frameworks->{$thisframework}->{'frameworktext'},
            );
    push @frameworksloop, \%row;
}
$template->param(frameworkloop => \@frameworksloop);

=head3 in TEMPLATE

<form action='<!-- TMPL_VAR name="script_name" -->' method=post>
    <select name="frameworkcode">
        <option value="">Default</option>
    <!-- TMPL_LOOP name="frameworkloop" -->
        <option value="<!-- TMPL_VAR name="value" -->" <!-- TMPL_IF name="selected" -->selected<!-- /TMPL_IF -->><!-- TMPL_VAR name="frameworktext" --></option>
    <!-- /TMPL_LOOP -->
    </select>
    <input type=text name=searchfield value="<!-- TMPL_VAR name="searchfield" -->">
    <input type="submit" value="OK" class="button">
</form>


=cut

sub getframeworks {

    # returns a reference to a hash of references to branches...
    my %itemtypes;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("select * from biblio_framework");
    $sth->execute;
    while ( my $IT = $sth->fetchrow_hashref ) {
        $itemtypes{ $IT->{'frameworkcode'} } = $IT;
    }
    return ( \%itemtypes );
}

=head2 getframeworkinfo

  $frameworkinfo = &getframeworkinfo($frameworkcode);

Returns information about an frameworkcode.

=cut

sub getframeworkinfo {
    my ($frameworkcode) = @_;
    my $dbh             = C4::Context->dbh;
    my $sth             =
      $dbh->prepare("select * from biblio_framework where frameworkcode=?");
    $sth->execute($frameworkcode);
    my $res = $sth->fetchrow_hashref;
    return $res;
}

=head2 getitemtypeinfo

  $itemtype = &getitemtype($itemtype);

Returns information about an itemtype.

=cut

sub getitemtypeinfo {
    my ($itemtype) = @_;
    my $dbh        = C4::Context->dbh;
    my $sth        = $dbh->prepare("select * from itemtypes where itemtype=?");
    $sth->execute($itemtype);
    my $res = $sth->fetchrow_hashref;

    $res->{imageurl} = getitemtypeimagesrcfromurl( $res->{imageurl} );

    return $res;
}

sub getitemtypeimagesrcfromurl {
    my ($imageurl) = @_;

    if ( defined $imageurl and $imageurl !~ m/^http/ ) {
        $imageurl = getitemtypeimagesrc() . '/' . $imageurl;
    }

    return $imageurl;
}

sub getitemtypeimagedir {
	my $src = shift;
	if ($src eq 'intranet') {
		return C4::Context->config('intrahtdocs') . '/' .C4::Context->preference('template') . '/img/itemtypeimg';
	}
	else {
		return C4::Context->config('opachtdocs') . '/' . C4::Context->preference('template') . '/itemtypeimg';
	}
}

sub getitemtypeimagesrc {
	 my $src = shift;
	if ($src eq 'intranet') {
		return '/intranet-tmpl' . '/' .	C4::Context->preference('template') . '/img/itemtypeimg';
	} 
	else {
		return '/opac-tmpl' . '/' . C4::Context->preference('template') . '/itemtypeimg';
	}
}

=head2 GetPrinters

  $printers = &GetPrinters();
  @queues = keys %$printers;

Returns information about existing printer queues.

C<$printers> is a reference-to-hash whose keys are the print queues
defined in the printers table of the Koha database. The values are
references-to-hash, whose keys are the fields in the printers table.

=cut

sub GetPrinters {
    my %printers;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("select * from printers");
    $sth->execute;
    while ( my $printer = $sth->fetchrow_hashref ) {
        $printers{ $printer->{'printqueue'} } = $printer;
    }
    return ( \%printers );
}

=head2 GetPrinter

$printer = GetPrinter( $query, $printers );

=cut

sub GetPrinter ($$) {
    my ( $query, $printers ) = @_;    # get printer for this query from printers
    my $printer = $query->param('printer');
    my %cookie = $query->cookie('userenv');
    ($printer) || ( $printer = $cookie{'printer'} ) || ( $printer = '' );
    ( $printers->{$printer} ) || ( $printer = ( keys %$printers )[0] );
    return $printer;
}

=item getnbpages

Returns the number of pages to display in a pagination bar, given the number
of items and the number of items per page.

=cut

sub getnbpages {
    my ( $nb_items, $nb_items_per_page ) = @_;

    return int( ( $nb_items - 1 ) / $nb_items_per_page ) + 1;
}

=item getallthemes

  (@themes) = &getallthemes('opac');
  (@themes) = &getallthemes('intranet');

Returns an array of all available themes.

=cut

sub getallthemes {
    my $type = shift;
    my $htdocs;
    my @themes;
    if ( $type eq 'intranet' ) {
        $htdocs = C4::Context->config('intrahtdocs');
    }
    else {
        $htdocs = C4::Context->config('opachtdocs');
    }
    opendir D, "$htdocs";
    my @dirlist = readdir D;
    foreach my $directory (@dirlist) {
        -d "$htdocs/$directory/en" and push @themes, $directory;
    }
    return @themes;
}

sub getFacets {
    my $facets;
    if ( C4::Context->preference("marcflavour") eq "UNIMARC" ) {
        $facets = [
            {
                link_value  => 'su-to',
                label_value => 'Topics',
                tags        =>
                  [ '600', '601', '602', '603', '604', '605', '606', '610' ],
                subfield => 'a',
            },
            {
                link_value  => 'su-geo',
                label_value => 'Places',
                tags        => ['651'],
                subfield    => 'a',
            },
            {
                link_value  => 'su-ut',
                label_value => 'Titles',
                tags        => [ '500', '501', '502', '503', '504', ],
                subfield    => 'a',
            },
            {
                link_value  => 'au',
                label_value => 'Authors',
                tags        => [ '700', '701', '702', ],
                subfield    => 'a',
            },
            {
                link_value  => 'se',
                label_value => 'Series',
                tags        => ['225'],
                subfield    => 'a',
            },
            {
                link_value  => 'branch',
                label_value => 'Libraries',
                tags        => [ '995', ],
                subfield    => 'b',
                expanded    => '1',
            },
        ];
    }
    else {
        $facets = [
            {
                link_value  => 'su-to',
                label_value => 'Topics',
                tags        => ['650'],
                subfield    => 'a',
            },

            #        {
            #        link_value => 'su-na',
            #        label_value => 'People and Organizations',
            #        tags => ['600', '610', '611'],
            #        subfield => 'a',
            #        },
            {
                link_value  => 'su-geo',
                label_value => 'Places',
                tags        => ['651'],
                subfield    => 'a',
            },
            {
                link_value  => 'su-ut',
                label_value => 'Titles',
                tags        => ['630'],
                subfield    => 'a',
            },
            {
                link_value  => 'au',
                label_value => 'Authors',
                tags        => [ '100', '110', '700', ],
                subfield    => 'a',
            },
            {
                link_value  => 'se',
                label_value => 'Series',
                tags        => [ '440', '490', ],
                subfield    => 'a',
            },
            {
                link_value  => 'branch',
                label_value => 'Libraries',
                tags        => [ '952', ],
                subfield    => 'b',
                expanded    => '1',
            },
        ];
    }
    return $facets;
}

=head2 get_infos_of

Return a href where a key is associated to a href. You give a query, the
name of the key among the fields returned by the query. If you also give as
third argument the name of the value, the function returns a href of scalar.

  my $query = '
SELECT itemnumber,
       notforloan,
       barcode
  FROM items
';

  # generic href of any information on the item, href of href.
  my $iteminfos_of = get_infos_of($query, 'itemnumber');
  print $iteminfos_of->{$itemnumber}{barcode};

  # specific information, href of scalar
  my $barcode_of_item = get_infos_of($query, 'itemnumber', 'barcode');
  print $barcode_of_item->{$itemnumber};

=cut

sub get_infos_of {
    my ( $query, $key_name, $value_name ) = @_;

    my $dbh = C4::Context->dbh;

    my $sth = $dbh->prepare($query);
    $sth->execute();

    my %infos_of;
    while ( my $row = $sth->fetchrow_hashref ) {
        if ( defined $value_name ) {
            $infos_of{ $row->{$key_name} } = $row->{$value_name};
        }
        else {
            $infos_of{ $row->{$key_name} } = $row;
        }
    }
    $sth->finish;

    return \%infos_of;
}

=head2 get_notforloan_label_of

  my $notforloan_label_of = get_notforloan_label_of();

Each authorised value of notforloan (information available in items and
itemtypes) is link to a single label.

Returns a href where keys are authorised values and values are corresponding
labels.

  foreach my $authorised_value (keys %{$notforloan_label_of}) {
    printf(
        "authorised_value: %s => %s\n",
        $authorised_value,
        $notforloan_label_of->{$authorised_value}
    );
  }

=cut

# FIXME - why not use GetAuthorisedValues ??
#
sub get_notforloan_label_of {
    my $dbh = C4::Context->dbh;

    my $query = '
SELECT authorised_value
  FROM marc_subfield_structure
  WHERE kohafield = \'items.notforloan\'
  LIMIT 0, 1
';
    my $sth = $dbh->prepare($query);
    $sth->execute();
    my ($statuscode) = $sth->fetchrow_array();

    $query = '
SELECT lib,
       authorised_value
  FROM authorised_values
  WHERE category = ?
';
    $sth = $dbh->prepare($query);
    $sth->execute($statuscode);
    my %notforloan_label_of;
    while ( my $row = $sth->fetchrow_hashref ) {
        $notforloan_label_of{ $row->{authorised_value} } = $row->{lib};
    }
    $sth->finish;

    return \%notforloan_label_of;
}

sub displayServers {
    my ( $position, $type ) = @_;
    my $dbh    = C4::Context->dbh;
    my $strsth = "SELECT * FROM z3950servers where 1";
    $strsth .= " AND position=\"$position\"" if ($position);
    $strsth .= " AND type=\"$type\""         if ($type);
    my $rq = $dbh->prepare($strsth);
    $rq->execute;
    my @primaryserverloop;

    while ( my $data = $rq->fetchrow_hashref ) {
        my %cell;
        $cell{label} = $data->{'description'};
        $cell{id}    = $data->{'name'};
        $cell{value} =
            $data->{host}
          . ( $data->{port} ? ":" . $data->{port} : "" ) . "/"
          . $data->{database}
          if ( $data->{host} );
        $cell{checked} = $data->{checked};
        push @primaryserverloop,
          {
            label => $data->{description},
            id    => $data->{name},
            name  => "server",
            value => $data->{host} . ":"
              . $data->{port} . "/"
              . $data->{database},
            encoding   => ($data->{encoding}?$data->{encoding}:"iso-5426"),
            checked    => "checked",
            icon       => $data->{icon},
            zed        => $data->{type} eq 'zed',
            opensearch => $data->{type} eq 'opensearch'
          };
    }
    return \@primaryserverloop;
}

sub displaySecondaryServers {

# 	my $secondary_servers_loop = [
# 		{ inner_sup_servers_loop => [
#         	{label => "Google", id=>"GOOG", value=>"google",icon => "google.ico",opensearch => "1"},
#         	{label => "Yahoo", id=>"YAH", value=>"yahoo", icon =>"yahoo.ico", zed => "1"},
#         	{label => "Worldcat", id=>"WCT", value=>"worldcat", icon => "worldcat.gif", zed => "1"},
#         	{label => "Library of Congress", id=>"LOC", name=> "server", value=>"z3950.loc.gov:7090/Voyager", icon =>"loc.ico", zed => "1"},
#     	],
#     	},
# 	];
    return;    #$secondary_servers_loop;
}

=head2 GetAuthValCode

$authvalcode = GetAuthValCode($kohafield,$frameworkcode);

=cut

sub GetAuthValCode {
	my ($kohafield,$fwcode) = @_;
	my $dbh = C4::Context->dbh;
	$fwcode='' unless $fwcode;
	my $sth = $dbh->prepare('select authorised_value from marc_subfield_structure where kohafield=? and frameworkcode=?');
	$sth->execute($kohafield,$fwcode);
	my ($authvalcode) = $sth->fetchrow_array;
	return $authvalcode;
}

=head2 GetAuthorisedValues

$authvalues = GetAuthorisedValues($category);

this function get all authorised values from 'authosied_value' table into a reference to array which
each value containt an hashref.

Set C<$category> on input args if you want to limits your query to this one. This params is not mandatory.

=cut

sub GetAuthorisedValues {
    my ($category,$selected) = @_;
	my $count = 0;
	my @results;
    my $dbh      = C4::Context->dbh;
    my $query    = "SELECT * FROM authorised_values";
    $query .= " WHERE category = '" . $category . "'" if $category;

    my $sth = $dbh->prepare($query);
    $sth->execute;
	while (my $data=$sth->fetchrow_hashref) {
		if ($selected eq $data->{'authorised_value'} ) {
			$data->{'selected'} = 1;
		}
		$results[$count] = $data;
		$count++;
	}
    #my $data = $sth->fetchall_arrayref({});
    return \@results; #$data;
}

=head2 GetKohaAuthorisedValues
	
	Takes $dbh , $kohafield as parameters.
	returns hashref of authvalCode => liblibrarian
	or undef if no authvals defined for kohafield.

=cut

sub GetKohaAuthorisedValues {
  my ($kohafield,$fwcode) = @_;
  $fwcode='' unless $fwcode;
  my %values;
  my $dbh = C4::Context->dbh;
  my $avcode = GetAuthValCode($kohafield,$fwcode);
  if ($avcode) {  
    my $sth = $dbh->prepare("select authorised_value, lib from authorised_values where category=? ");
    $sth->execute($avcode);
	while ( my ($val, $lib) = $sth->fetchrow_array ) { 
   		$values{$val}= $lib;
   	}
  }
  return \%values;
}

=head2 GetManagedTagSubfields

=over 4

$res = GetManagedTagSubfields();

=back

Returns a reference to a big hash of hash, with the Marc structure fro the given frameworkcode

NOTE: This function is used only by the (incomplete) bulk editing feature.  Since
that feature currently does not deal with items and biblioitems changes 
correctly, those tags are specifically excluded from the list prepared
by this function.

For future reference, if a bulk item editing feature is implemented at some point, it
needs some design thought -- for example, circulation status fields should not 
be changed willy-nilly.

=cut

sub GetManagedTagSubfields{
  my $dbh=C4::Context->dbh;
  my $rq=$dbh->prepare(qq|
SELECT 
  DISTINCT CONCAT( marc_subfield_structure.tagfield, tagsubfield ) AS tagsubfield, 
  marc_subfield_structure.liblibrarian as subfielddesc, 
  marc_tag_structure.liblibrarian as tagdesc
FROM marc_subfield_structure
  LEFT JOIN marc_tag_structure 
    ON marc_tag_structure.tagfield = marc_subfield_structure.tagfield
    AND marc_tag_structure.frameworkcode = marc_subfield_structure.frameworkcode
WHERE marc_subfield_structure.tab>=0
AND marc_tag_structure.tagfield NOT IN (SELECT tagfield FROM marc_subfield_structure WHERE kohafield like 'items.%')
AND marc_tag_structure.tagfield NOT IN (SELECT tagfield FROM marc_subfield_structure WHERE kohafield = 'biblioitems.itemtype')
AND marc_subfield_structure.kohafield <> 'biblio.biblionumber'
AND marc_subfield_structure.kohafield <>  'biblioitems.biblioitemnumber'
ORDER BY marc_subfield_structure.tagfield, tagsubfield|);
  $rq->execute;
  my $data=$rq->fetchall_arrayref({});
  return $data;
}

1;

__END__

=head1 AUTHOR

Koha Team

=cut
