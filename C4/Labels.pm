package C4::Labels;

# Copyright 2006 Katipo Communications.
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

use vars qw($VERSION @ISA @EXPORT);

use PDF::Reuse;
use Text::Wrap;
use Algorithm::CheckDigits;
# use Data::Dumper;
# use Smart::Comments;

$VERSION = 0.01;

=head1 NAME

C4::Labels - Functions for printing spine labels and barcodes in Koha

=head1 FUNCTIONS

=over 2

=cut

@ISA    = qw(Exporter);
@EXPORT = qw(
  &get_label_options &get_label_items
  &build_circ_barcode &draw_boundaries
  &drawbox &GetActiveLabelTemplate
  &GetAllLabelTemplates &DeleteTemplate
  &GetSingleLabelTemplate &SaveTemplate
  &CreateTemplate &SetActiveTemplate
  &SaveConf &DrawSpineText &GetTextWrapCols
  &GetUnitsValue &DrawBarcode
  &get_printingtypes
  &get_layouts
  &get_barcode_types
  &get_batches &delete_batch
  &add_batch &SetFontSize &printText
  &GetItemFields
  &get_text_fields
  get_layout &save_layout &add_layout
  &set_active_layout &by_order
  &build_text_dropbox
  &delete_layout &get_active_layout
&get_highest_batch
);

=item get_label_options;

	$options = get_label_options()


Return a pointer on a hash list containing info from labels_conf table in Koha DB.

=cut

#'
sub get_label_options {
    my $dbh    = C4::Context->dbh;
    my $query2 = " SELECT * FROM labels_conf where active = 1";
    my $sth    = $dbh->prepare($query2);
    $sth->execute();
    my $conf_data = $sth->fetchrow_hashref;
    $sth->finish;
    return $conf_data;
}

sub get_layouts {

## FIXME: this if/else could be compacted...
    my $dbh = C4::Context->dbh;
    my @data;
    my $query = " Select * from labels_conf";
    my $sth   = $dbh->prepare($query);
    $sth->execute();
    my @resultsloop;
    while ( my $data = $sth->fetchrow_hashref ) {

        $data->{'fieldlist'} = get_text_fields( $data->{'id'} );
        push( @resultsloop, $data );
    }
    $sth->finish;

    # @resultsloop

    return @resultsloop;
}

sub get_layout {
    my ($layout_id) = @_;
    my $dbh = C4::Context->dbh;

    # get the actual items to be printed.
    my $query = " Select * from labels_conf where id = ?";
    my $sth   = $dbh->prepare($query);
    $sth->execute($layout_id);
    my $data = $sth->fetchrow_hashref;
    $sth->finish;
    return $data;
}

sub get_active_layout {
    my ($layout_id) = @_;
    my $dbh = C4::Context->dbh;

    # get the actual items to be printed.
    my $query = " Select * from labels_conf where active = 1";
    my $sth   = $dbh->prepare($query);
    $sth->execute();
    my $data = $sth->fetchrow_hashref;
    $sth->finish;
    return $data;
}

sub delete_layout {
    my ($layout_id) = @_;
    my $dbh = C4::Context->dbh;

    # get the actual items to be printed.
    my $query = "delete from  labels_conf where id = ?";
    my $sth   = $dbh->prepare($query);
    $sth->execute($layout_id);
    $sth->finish;
}

sub get_printingtypes {
    my ($layout_id) = @_;
    my @printtypes;

    push( @printtypes, { code => 'BAR',    desc => "barcode" } );
    push( @printtypes, { code => 'BIB',    desc => "biblio" } );
    push( @printtypes, { code => 'BARBIB', desc => "barcode / biblio" } );
    push( @printtypes, { code => 'BIBBAR', desc => "biblio / barcode" } );
    push( @printtypes, { code => 'ALT',    desc => "alternating labels" } );

    my $conf             = get_layout($layout_id);
    my $active_printtype = $conf->{'printingtype'};

    # lop thru layout, insert selected to hash

    foreach my $printtype (@printtypes) {
        if ( $printtype->{'code'} eq $active_printtype ) {
            $printtype->{'active'} = 'MOO';
        }
    }
    return @printtypes;
}

sub build_text_dropbox {
    my ($order) = @_;

    #  my @fields      = get_text_fields();
    #    my $field_count = scalar @fields;
    my $field_count = 10;    # <-----------       FIXME hard coded

    my @lines;
    !$order
      ? push( @lines, { num => '', selected => '1' } )
      : push( @lines, { num => '' } );
    for ( my $i = 1 ; $i <= $field_count ; $i++ ) {
        my $line = { num => "$i" };
        $line->{'selected'} = 1 if $i eq $order;
        push( @lines, $line );
    }

    # add a blank row too

    return @lines;
}

sub get_text_fields {
    my ($layout_id, $sorttype) = @_;

    my ( $a, $b, $c, $d, $e, $f, $g, $h, $i ,$j, $k );

    my $sortorder = get_layout($layout_id);

    # $sortorder

    $a = {
        code  => 'itemtype',
        desc  => "Item Type",
        order => $sortorder->{'itemtype'}
    };
    $b = {
        code  => 'dewey',
        desc  => "Dewey",
        order => $sortorder->{'dewey'}
    };
    $c = { code => 'issn', desc => "ISSN", 
        order => $sortorder->{'issn'} };
    $d = { code => 'isbn', desc => "ISBN", 
            order => $sortorder->{'isbn'} };
    $e = {
        code  => 'class',
        desc  => "Classification",
        order => $sortorder->{'class'}
    };
    $f = {
        code  => 'subclass',
        desc  => "Sub-Class",
        order => $sortorder->{'subclass'}
    };
    $g = {
        code  => 'barcode',
        desc  => "Barcode",
        order => $sortorder->{'barcode'}
    };
    $h =
      { code => 'author', desc => "Author", order => $sortorder->{'author'} };
    $i = { code => 'title', desc => "Title", order => $sortorder->{'title'} };
    $j = { code => 'itemcallnumber', desc => "Call Number", order => $sortorder->{'itemcallnumber'} };
	$k = { code => 'subtitle', desc => "Subtitle", order => $sortorder->{'subtitle'} }; 
    
	my @text_fields = ( $a, $b, $c, $d, $e, $f, $g, $h, $i ,$j, $k );

    my @new_fields;
    foreach my $field (@text_fields) {
        push( @new_fields, $field ) if $field->{'order'} > 0;
    }

    my @sorted_fields = sort by_order @new_fields;
    my $active_fields;
    foreach my $field (@sorted_fields) {
     $sorttype eq 'codes' ?   $active_fields .= "$field->{'code'} " :
          $active_fields .= "$field->{'desc'} ";
    }
    return $active_fields;

}

sub by_order {
    $$a{order} <=> $$b{order};
}

sub add_batch {
    my $new_batch;
    my $dbh = C4::Context->dbh;
    my $q =
      "select distinct batch_id from labels order by batch_id desc limit 1";
    my $sth = $dbh->prepare($q);
    $sth->execute();
    my $data = $sth->fetchrow_hashref;
    $sth->finish;

    if ( !$data->{'batch_id'} ) {
        $new_batch = 1;
    }
    else {
        $new_batch = ( $data->{'batch_id'} + 1 );
    }

    return $new_batch;
}


sub get_highest_batch {
    my $new_batch;
    my $dbh = C4::Context->dbh;
    my $q =
      "select distinct batch_id from labels order by batch_id desc limit 1";
    my $sth = $dbh->prepare($q);
    $sth->execute();
    my $data = $sth->fetchrow_hashref;
    $sth->finish;

    if ( !$data->{'batch_id'} ) {
        $new_batch = 1;
    }
    else {
        $new_batch =  $data->{'batch_id'};
    }

    return $new_batch;
}


sub get_batches {
    my $dbh = C4::Context->dbh;
    my $q   = "select batch_id, count(*) as num from labels group by batch_id";
    my $sth = $dbh->prepare($q);
    $sth->execute();
    my @resultsloop;
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @resultsloop, $data );
    }
    $sth->finish;

    # adding a dummy batch=1 value , if none exists in the db
    if ( !scalar(@resultsloop) ) {
        push( @resultsloop, { batch_id => '1' , num => '0' } );
    }
    return @resultsloop;
}

sub delete_batch {
    my ($batch_id) = @_;
    my $dbh        = C4::Context->dbh;
    my $q          = "DELETE FROM labels where batch_id  = ?";
    my $sth        = $dbh->prepare($q);
    $sth->execute($batch_id);
    $sth->finish;
}

sub get_barcode_types {
    my ($layout_id) = @_;
    my $layout      = get_layout($layout_id);
    my $barcode     = $layout->{'barcodetype'};
    my @array;

    push( @array, { code => 'CODE39',    desc => 'Code 39' } );
    push( @array, { code => 'CODE39MOD', desc => 'Code39 + Modulo43' } );
    push( @array, { code => 'CODE39MOD10', desc => 'Code39 + Modulo10' } ); 
	push( @array, { code => 'ITF',       desc => 'Interleaved 2 of 5' } );

    foreach my $line (@array) {
        if ( $line->{'code'} eq $barcode ) {
            $line->{'active'} = 1;
        }

    }
    return @array;
}

sub GetUnitsValue {
    my ($units) = @_;
    my $unitvalue;

    $unitvalue = '1'          if ( $units eq 'POINT' );
    $unitvalue = '2.83464567' if ( $units eq 'MM' );
    $unitvalue = '28.3464567' if ( $units eq 'CM' );
    $unitvalue = 72           if ( $units eq 'INCH' );
    return $unitvalue;
}

sub GetTextWrapCols {
    my ( $fontsize, $label_width ) = @_;
    my $string           = "0";
    my $left_text_margin = 3;
    my ( $strtmp, $strwidth );
    my $count     = 0;
    my $textlimit = $label_width - $left_text_margin;

    while ( $strwidth < $textlimit ) {
        $strwidth = prStrWidth( $string, 'C', $fontsize );
        $string = $string . '0';

        #	warn "strwidth $strwidth, $textlimit, $string";
        $count++;
    }
    return $count;
}

sub GetActiveLabelTemplate {
    my $dbh   = C4::Context->dbh;
    my $query = " SELECT * FROM labels_templates where active = 1 limit 1";
    my $sth   = $dbh->prepare($query);
    $sth->execute();
    my $active_tmpl = $sth->fetchrow_hashref;
    $sth->finish;
    return $active_tmpl;
}

sub GetSingleLabelTemplate {
    my ($tmpl_id) = @_;
    my $dbh       = C4::Context->dbh;
    my $query     = " SELECT * FROM labels_templates where tmpl_id = ?";
    my $sth       = $dbh->prepare($query);
    $sth->execute($tmpl_id);
    my $template = $sth->fetchrow_hashref;
    $sth->finish;
    return $template;
}

sub SetActiveTemplate {

    my ($tmpl_id) = @_;
  
    my $dbh   = C4::Context->dbh;
    my $query = " UPDATE labels_templates SET active = NULL";
    my $sth   = $dbh->prepare($query);
    $sth->execute();

    my $query = "UPDATE labels_templates SET active = 1 WHERE tmpl_id = ?";
    my $sth   = $dbh->prepare($query);
    $sth->execute($tmpl_id);
    $sth->finish;
}

sub set_active_layout {

    my ($layout_id) = @_;
    my $dbh         = C4::Context->dbh;
    my $query       = " UPDATE labels_conf SET active = NULL";
    my $sth         = $dbh->prepare($query);
    $sth->execute();

    my $query = "UPDATE labels_conf SET active = 1 WHERE id = ?";
    my $sth   = $dbh->prepare($query);
    $sth->execute($layout_id);
    $sth->finish;
}

sub DeleteTemplate {
    my ($tmpl_id) = @_;
    my $dbh       = C4::Context->dbh;
    my $query     = " DELETE  FROM labels_templates where tmpl_id = ?";
    my $sth       = $dbh->prepare($query);
    $sth->execute($tmpl_id);
    $sth->finish;
}

sub SaveTemplate {
    my (
        $tmpl_id,     $tmpl_code,   $tmpl_desc,    $page_width,
        $page_height, $label_width, $label_height, $topmargin,
        $leftmargin,  $cols,        $rows,         $colgap,
        $rowgap,      $fontsize,     $units
    ) = @_;
    my $dbh = C4::Context->dbh;
    my $query =
      " UPDATE labels_templates SET tmpl_code=?, tmpl_desc=?, page_width=?,
               page_height=?, label_width=?, label_height=?, topmargin=?,
               leftmargin=?, cols=?, rows=?, colgap=?, rowgap=?, fontsize=?,
	  		   units=? 
                  WHERE tmpl_id = ?";

    my $sth = $dbh->prepare($query);
    $sth->execute(
        $tmpl_code,   $tmpl_desc,    $page_width, $page_height,
        $label_width, $label_height, $topmargin,  $leftmargin,
        $cols,        $rows,         $colgap,     $rowgap,
        $fontsize,    $units,        $tmpl_id
    );
    $sth->finish;
}

sub CreateTemplate {
    my $tmpl_id;
    my (
        $tmpl_code,   $tmpl_desc,    $page_width, $page_height,
        $label_width, $label_height, $topmargin,  $leftmargin,
        $cols,        $rows,         $colgap,     $rowgap,
        $fontsize,     $units
    ) = @_;

    my $dbh = C4::Context->dbh;

    my $query = "INSERT INTO labels_templates (tmpl_code, tmpl_desc, page_width,
                         page_height, label_width, label_height, topmargin,
                         leftmargin, cols, rows, colgap, rowgap, fontsize, units)
                         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

    my $sth = $dbh->prepare($query);
    $sth->execute(
        $tmpl_code,   $tmpl_desc,    $page_width, $page_height,
        $label_width, $label_height, $topmargin,  $leftmargin,
        $cols,        $rows,         $colgap,     $rowgap,
        $fontsize,    $units
    );
}

sub GetAllLabelTemplates {
    my $dbh = C4::Context->dbh;

    # get the actual items to be printed.
    my @data;
    my $query = " Select * from labels_templates ";
    my $sth   = $dbh->prepare($query);
    $sth->execute();
    my @resultsloop;
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @resultsloop, $data );
    }
    $sth->finish;

    #warn Dumper @resultsloop;
    return @resultsloop;
}

#sub SaveConf {
sub add_layout {

    my (
        $barcodetype,  $title,         	$subtitle, 	$isbn,       $issn,
        $itemtype,     $bcn,            $dcn,        $classif,
        $subclass,     $itemcallnumber, $author,     $tmpl_id,
        $printingtype, $guidebox,       $startlabel, $layoutname
    ) = @_;

    my $dbh    = C4::Context->dbh;
    my $query2 = "update labels_conf set active = NULL";
    my $sth2   = $dbh->prepare($query2);
    $sth2->execute();
    my $query2 = "INSERT INTO labels_conf
            ( barcodetype, title, subtitle, isbn,issn, itemtype, barcode,
              dewey, class, subclass, itemcallnumber, author, printingtype,
                guidebox, startlabel, layoutname, active )
               values ( ?, ?, ?, ?, ?, ?, ?,  ?,?, ?, ?, ?, ?, ?,?,?, 1 )";
    my $sth2 = $dbh->prepare($query2);
    $sth2->execute(
        $barcodetype, $title, $subtitle, $isbn, $issn,

        $itemtype, $bcn,            $dcn,    $classif,
        $subclass, $itemcallnumber, $author, $printingtype,
        $guidebox, $startlabel,     $layoutname
    );
    $sth2->finish;

    SetActiveTemplate($tmpl_id);
    return;
}

sub save_layout {

    my (
        $barcodetype,  $title,          $subtitle,	$isbn,       $issn,
        $itemtype,     $bcn,            $dcn,        $classif,
        $subclass,     $itemcallnumber, $author,     $tmpl_id,
        $printingtype, $guidebox,       $startlabel, $layoutname,
        $layout_id
    ) = @_;
### $layoutname
### $layout_id

    my $dbh    = C4::Context->dbh;
    my $query2 = "update labels_conf set 
             barcodetype=?, title=?, subtitle=?, isbn=?,issn=?, 
            itemtype=?, barcode=?,    dewey=?, class=?,
             subclass=?, itemcallnumber=?, author=?,  printingtype=?,  
               guidebox=?, startlabel=?, layoutname=? where id = ?";
    my $sth2 = $dbh->prepare($query2);
    $sth2->execute(
        $barcodetype, $title,          $subtitle,	$isbn,       $issn,
        $itemtype,    $bcn,            $dcn,        $classif,
        $subclass,    $itemcallnumber, $author,     $printingtype,
        $guidebox,    $startlabel,     $layoutname, $layout_id
    );
    $sth2->finish;

    return;
}

=item get_label_items;

        $options = get_label_items()


Returns an array of references-to-hash, whos keys are the field from the biblio, biblioitems, items and labels tables in the Koha database.

=cut

#'
sub get_label_items {
    my ($batch_id) = @_;
    my $dbh = C4::Context->dbh;

    my @resultsloop = ();
    my $count;
    my @data;
    my $sth;

    if ($batch_id) {
        my $query3 = "Select * from labels where batch_id = ? order by labelid ";
        $sth = $dbh->prepare($query3);
        $sth->execute($batch_id);

    }
    else {

        my $query3 = "Select * from labels";
        $sth = $dbh->prepare($query3);
        $sth->execute();
    }
    my $cnt = $sth->rows;
    my $i1  = 1;
    while ( my $data = $sth->fetchrow_hashref ) {

        # lets get some summary info from each item
        my $query1 = " 
	 select i.*, bi.*, b.*  from items i,biblioitems bi,biblio b 
		where itemnumber=? and  i.biblioitemnumber=bi.biblioitemnumber and                  
		bi.biblionumber=b.biblionumber"; 
     
	 my $sth1 = $dbh->prepare($query1);
        $sth1->execute( $data->{'itemnumber'} );

        my $data1 = $sth1->fetchrow_hashref();

        $data1->{'labelno'}  = $i1;
        $data1->{'batch_id'} = $batch_id;
        $data1->{'summary'} =
          "$data1->{'barcode'}, $data1->{'title'}, $data1->{'isbn'}";

        push( @resultsloop, $data1 );
        $sth1->finish;

        $i1++;
    }
    $sth->finish;
    return @resultsloop;

}

sub GetItemFields {
    my @fields = qw (
      barcode title subtitle
      dewey isbn issn author class
      itemtype subclass itemcallnumber

    );
    return @fields;
}

sub DrawSpineText {

    my ( $y_pos, $label_height, $fontsize, $x_pos, $left_text_margin,
        $text_wrap_cols, $item, $conf_data )
      = @_;
# hack to fix column name mismatch betwen labels_conf.class, and bibitems.classification
	$$item->{'class'} = $$item->{'classification'};
 
    $Text::Wrap::columns   = $text_wrap_cols;
    $Text::Wrap::separator = "\n";

    my $str;
    ##      $item

    my $top_text_margin = ( $fontsize + 3 );
    my $line_spacer = ($fontsize);    # number of pixels between text rows.

    # add your printable fields manually in here

my $layout_id = $$conf_data->{'id'};

#    my @fields = GetItemFields();

my $str_fields = get_text_fields($layout_id, 'codes' );
my @fields = split(/ /, $str_fields);
### @fields

    my $vPos   = ( $y_pos + ( $label_height - $top_text_margin ) );
    my $hPos   = ( $x_pos + $left_text_margin );

    # warn Dumper $conf_data;
    #warn Dumper $item;

    foreach my $field (@fields) {

        # testing hack
#     $$item->{"$field"} = $field . ": " . $$item->{"$field"};

        # if the display option for this field is selected in the DB,
        # and the item record has some values for this field, display it.
        if ( $$conf_data->{"$field"} && $$item->{"$field"} ) {

            #            warn "CONF_TYPE = $field";

            # get the string
            $str = $$item->{"$field"};
            # strip out naughty existing nl/cr's
            $str =~ s/\n//g;
            $str =~ s/\r//g;

            # chop the string up into _upto_ 12 chunks
            # and seperate the chunks with newlines

            $str = wrap( "", "", "$str" );
            $str = wrap( "", "", "$str" );

            # split the chunks between newline's, into an array
            my @strings = split /\n/, $str;

            # then loop for each string line
            foreach my $str (@strings) {

                #warn "HPOS ,  VPOS $hPos, $vPos ";
                # set the font size A

                #   prText( $hPos, $vPos, $str );
                PrintText( $hPos, $vPos, $fontsize, $str );
                $vPos = $vPos - $line_spacer;
            }
        }    # if field is     }    #foreach feild
    }
}

sub PrintText {
    my ( $hPos, $vPos, $fontsize, $text ) = @_;
    my $str = "BT /Ft1 $fontsize Tf $hPos $vPos Td ($text) Tj ET";
    prAdd($str);
}

sub SetFontSize {

    my ($fontsize) = @_;
### fontsize
    my $str = "BT/F13 30 Tf288 720 Td( AAAAAAAAAA ) TjET";
    prAdd($str);
}

sub DrawBarcode {

    # x and y are from the top-left :)
    my ( $x_pos, $y_pos, $height, $width, $barcode, $barcodetype ) = @_;
    my $num_of_bars = length($barcode);
    my $bar_width   = $width * .8;        # %80 of length of label width
    my $tot_bar_length;
    my $bar_length;
    my $guard_length = 10;
    my $xsize_ratio;

    if ( $barcodetype eq 'CODE39' ) {
        $bar_length = '17.5';
        $tot_bar_length =
          ( $bar_length * $num_of_bars ) + ( $guard_length * 2 );
        $xsize_ratio = ( $bar_width / $tot_bar_length );
        eval {
            PDF::Reuse::Barcode::Code39(
                x => ( $x_pos + ( $width / 10 ) ),
                y => ( $y_pos + ( $height / 10 ) ),
                value         => "*$barcode*",
                ySize         => ( .02 * $height ),
                xSize         => $xsize_ratio,
                hide_asterisk => 1,
            );
        };
        if ($@) {
            warn "$barcodetype, $barcode FAILED:$@";
        }
    }

    elsif ( $barcodetype eq 'CODE39MOD' ) {

        # get modulo43 checksum
        my $c39 = CheckDigits('code_39');
        $barcode = $c39->complete($barcode);

        $bar_length = '19';
        $tot_bar_length =
          ( $bar_length * $num_of_bars ) + ( $guard_length * 2 );
        $xsize_ratio = ( $bar_width / $tot_bar_length );
        eval {
            PDF::Reuse::Barcode::Code39(
                x => ( $x_pos + ( $width / 10 ) ),
                y => ( $y_pos + ( $height / 10 ) ),
                value         => "*$barcode*",
                ySize         => ( .02 * $height ),
                xSize         => $xsize_ratio,
                hide_asterisk => 1,
            );
        };

        if ($@) {
            warn "$barcodetype, $barcode FAILED:$@";
        }
    }
    elsif ( $barcodetype eq 'CODE39MOD10' ) {
 
        # get modulo43 checksum
        my $c39_10 = CheckDigits('visa');
        $barcode = $c39_10->complete($barcode);

        $bar_length = '19';
        $tot_bar_length =
          ( $bar_length * $num_of_bars ) + ( $guard_length * 2 );
        $xsize_ratio = ( $bar_width / $tot_bar_length );
        eval {
            PDF::Reuse::Barcode::Code39(
                x => ( $x_pos + ( $width / 10 ) ),
                y => ( $y_pos + ( $height / 10 ) ),
                value         => "*$barcode*",
                ySize         => ( .02 * $height ),
                xSize         => $xsize_ratio,
                hide_asterisk => 1,
				text         => 0, 
            );
        };

        if ($@) {
            warn "$barcodetype, $barcode FAILED:$@";
        }
    }

 
    elsif ( $barcodetype eq 'COOP2OF5' ) {
        $bar_length = '9.43333333333333';
        $tot_bar_length =
          ( $bar_length * $num_of_bars ) + ( $guard_length * 2 );
        $xsize_ratio = ( $bar_width / $tot_bar_length ) * .9;
        eval {
            PDF::Reuse::Barcode::COOP2of5(
                x => ( $x_pos + ( $width / 10 ) ),
                y => ( $y_pos + ( $height / 10 ) ),
                value => $barcode,
                ySize => ( .02 * $height ),
                xSize => $xsize_ratio,
            );
        };
        if ($@) {
            warn "$barcodetype, $barcode FAILED:$@";
        }
    }

    elsif ( $barcodetype eq 'INDUSTRIAL2OF5' ) {
        $bar_length = '13.1333333333333';
        $tot_bar_length =
          ( $bar_length * $num_of_bars ) + ( $guard_length * 2 );
        $xsize_ratio = ( $bar_width / $tot_bar_length ) * .9;
        eval {
            PDF::Reuse::Barcode::Industrial2of5(
                x => ( $x_pos + ( $width / 10 ) ),
                y => ( $y_pos + ( $height / 10 ) ),
                value => $barcode,
                ySize => ( .02 * $height ),
                xSize => $xsize_ratio,
            );
        };
        if ($@) {
            warn "$barcodetype, $barcode FAILED:$@";
        }
    }

    my $moo2 = $tot_bar_length * $xsize_ratio;

    warn " $x_pos, $y_pos, $barcode, $barcodetype\n";
    warn
"BAR_WDTH = $bar_width, TOT.BAR.LGHT=$tot_bar_length  R*TOT.BAR =$moo2 \n";
}

=item build_circ_barcode;

  build_circ_barcode( $x_pos, $y_pos, $barcode,
	        $barcodetype, \$item);

$item is the result of a previous call to get_label_items();

=cut

#'
sub build_circ_barcode {
    my ( $x_pos_circ, $y_pos, $value, $barcodetype, $item ) = @_;

    #warn Dumper \$item;

    #warn "value = $value\n";

    #$DB::single = 1;

    if ( $barcodetype eq 'EAN13' ) {

        #testing EAN13 barcodes hack
        $value = $value . '000000000';
        $value =~ s/-//;
        $value = substr( $value, 0, 12 );

        #warn $value;
        eval {
            PDF::Reuse::Barcode::EAN13(
                x     => ( $x_pos_circ + 27 ),
                y     => ( $y_pos + 15 ),
                value => $value,

                #            prolong => 2.96,
                #            xSize   => 1.5,

                # ySize   => 1.2,

# added for xpdf compat. doesnt use type3 fonts., but increases filesize from 20k to 200k
# i think its embedding extra fonts in the pdf file.
#  mode => 'graphic',
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "EAN13BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }
    elsif ( $barcodetype eq 'Code39' ) {

        eval {
            PDF::Reuse::Barcode::Code39(
                x     => ( $x_pos_circ + 9 ),
                y     => ( $y_pos + 15 ),
                value => $value,

                #           prolong => 2.96,
                xSize => .85,

                ySize => 1.3,
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "CODE39BARCODE $value FAILED:$@";
        }

        #warn $barcodetype;

    }

    elsif ( $barcodetype eq 'Matrix2of5' ) {

        #warn "MATRIX ELSE:";

        #testing MATRIX25  barcodes hack
        #    $value = $value.'000000000';
        $value =~ s/-//;

        #    $value = substr( $value, 0, 12 );
        #warn $value;

        eval {
            PDF::Reuse::Barcode::Matrix2of5(
                x     => ( $x_pos_circ + 27 ),
                y     => ( $y_pos + 15 ),
                value => $value,

                #        prolong => 2.96,
                #       xSize   => 1.5,

                # ySize   => 1.2,
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }

    elsif ( $barcodetype eq 'EAN8' ) {

        #testing ean8 barcodes hack
        $value = $value . '000000000';
        $value =~ s/-//;
        $value = substr( $value, 0, 8 );

        #warn $value;

        #warn "EAN8 ELSEIF";
        eval {
            PDF::Reuse::Barcode::EAN8(
                x       => ( $x_pos_circ + 42 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };

        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }

    elsif ( $barcodetype eq 'UPC-E' ) {
        eval {
            PDF::Reuse::Barcode::UPCE(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };

        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }
    elsif ( $barcodetype eq 'NW7' ) {
        eval {
            PDF::Reuse::Barcode::NW7(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };

        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }
    elsif ( $barcodetype eq 'ITF' ) {
        eval {
            PDF::Reuse::Barcode::ITF(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };

        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }
    elsif ( $barcodetype eq 'Industrial2of5' ) {
        eval {
            PDF::Reuse::Barcode::Industrial2of5(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }
    elsif ( $barcodetype eq 'IATA2of5' ) {
        eval {
            PDF::Reuse::Barcode::IATA2of5(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }

    elsif ( $barcodetype eq 'COOP2of5' ) {
        eval {
            PDF::Reuse::Barcode::COOP2of5(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }
    elsif ( $barcodetype eq 'UPC-A' ) {

        eval {
            PDF::Reuse::Barcode::UPCA(
                x       => ( $x_pos_circ + 27 ),
                y       => ( $y_pos + 15 ),
                value   => $value,
                prolong => 2.96,
                xSize   => 1.5,

                # ySize   => 1.2,
            );
        };
        if ($@) {
            $item->{'barcodeerror'} = 1;

            #warn "BARCODE FAILED:$@";
        }

        #warn $barcodetype;

    }

}

=item draw_boundaries

 sub draw_boundaries ($x_pos_spine, $x_pos_circ1, $x_pos_circ2,
                $y_pos, $spine_width, $label_height, $circ_width)  

This sub draws boundary lines where the label outlines are, to aid in printer testing, and debugging.

=cut

#'
sub draw_boundaries {

    my (
        $x_pos_spine, $x_pos_circ1,  $x_pos_circ2, $y_pos,
        $spine_width, $label_height, $circ_width
    ) = @_;

    my $y_pos_initial = ( ( 792 - 36 ) - 90 );
    my $y_pos         = $y_pos_initial;
    my $i             = 1;

    for ( $i = 1 ; $i <= 8 ; $i++ ) {

        &drawbox( $x_pos_spine, $y_pos, ($spine_width), ($label_height) );

   #warn "OLD BOXES  x=$x_pos_spine, y=$y_pos, w=$spine_width, h=$label_height";
        &drawbox( $x_pos_circ1, $y_pos, ($circ_width), ($label_height) );
        &drawbox( $x_pos_circ2, $y_pos, ($circ_width), ($label_height) );

        $y_pos = ( $y_pos - $label_height );

    }
}

=item drawbox

	sub drawbox { 	$lower_left_x, $lower_left_y, 
			$upper_right_x, $upper_right_y )

this is a low level sub, that draws a pdf box, it is called by draw_boxes

FYI: the  $upper_right_x and $upper_right_y values are RELATIVE to  $lower_left_x and $lower_left_y

and $lower_left_x, $lower_left_y are ABSOLUTE, this caught me out!

=cut

#'
sub drawbox {
    my ( $llx, $lly, $urx, $ury ) = @_;

    #    warn "llx,y= $llx,$lly  ,   urx,y=$urx,$ury \n";

    my $str = "q\n";    # save the graphic state
    $str .= "0.5 w\n";              # border color red
    $str .= "1.0 0.0 0.0  RG\n";    # border color red
         #   $str .= "0.5 0.75 1.0 rg\n";           # fill color blue
    $str .= "1.0 1.0 1.0  rg\n";    # fill color white

    $str .= "$llx $lly $urx $ury re\n";    # a rectangle
    $str .= "B\n";                         # fill (and a little more)
    $str .= "Q\n";                         # save the graphic state

    prAdd($str);

}

END { }    # module clean-up code here (global destructor)

1;
__END__

=back

=head1 AUTHOR

Mason James <mason@katipo.co.nz>
=cut

