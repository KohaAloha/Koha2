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

# test comment

use strict;
use C4::Auth;
use CGI;
use C4::Context;

use C4::Output;
use C4::Koha;
use C4::Interface::CGI::Output;
use C4::Circulation::Circ2;

=head1 NAME

plugin that shows a stats on borrowers

=head1 DESCRIPTION


=over2

=cut

my $input          = new CGI;
my $do_it          = $input->param('do_it');
my $fullreportname = "reports/acquisitions_stats.tmpl";
my $line           = $input->param("Line");
my $column         = $input->param("Column");
my @filters        = $input->param("Filter");
my $podsp          = $input->param("PlacedOnDisplay");
my $rodsp          = $input->param("ReceivedOnDisplay");
my $aodsp          = $input->param("AcquiredOnDisplay");    ##added by mason.
my $calc           = $input->param("Cellvalue");
my $output         = $input->param("output");
my $basename       = $input->param("basename");
my $mime           = $input->param("MIME");
my $del            = $input->param("sep");

#warn "calcul : ".$calc;
my ($template, $borrowernumber, $cookie)
	= get_template_and_user({template_name => $fullreportname,
				query => $input,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {reports => 1},
				debug => 1,
				});
$template->param(do_it => $do_it,
		intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
		);
if ($do_it) {

    #warn
"line=$line, col=$column, pod=$podsp, rod=$rodsp, aod=$aodsp, calc=$calc, filters=@filters\n";

    my $results =
      calculate( $line, $column, $podsp, $rodsp, $aodsp, $calc, \@filters );
    if ( $output eq "screen" ) {
        $template->param( mainloop => $results );
        output_html_with_http_headers $input, $cookie, $template->output;
        exit(1);
    }
    else {
        print $input->header(
            -type       => 'application/vnd.sun.xml.calc',
            -encoding    => 'utf-8',
            -attachment => "$basename.csv",
            -name       => "$basename.csv"
        );
        my $cols  = @$results[0]->{loopcol};
        my $lines = @$results[0]->{looprow};
        my $sep;
        $sep = C4::Context->preference("delimiter");
        print @$results[0]->{line} . "/" . @$results[0]->{column} . $sep;
        foreach my $col (@$cols) {
            print $col->{coltitle} . $sep;
        }
        print "Total\n";
        foreach my $line (@$lines) {
            my $x = $line->{loopcell};
            print $line->{rowtitle} . $sep;
            foreach my $cell (@$x) {
                print $cell->{value} . $sep;
            }
            print $line->{totalrow};
            print "\n";
        }
        print "TOTAL";
        $cols = @$results[0]->{loopfooter};
        foreach my $col (@$cols) {
            print $sep. $col->{totalcol};
        }
        print $sep. @$results[0]->{total};
        exit(1);
    }
}
else {
    my $dbh = C4::Context->dbh;
    my @values;
    my %labels;
    my %select;
    my $req;
    $req =
      $dbh->prepare(
        "SELECT distinctrow id,name FROM aqbooksellers ORDER BY name");
    $req->execute;
    my @select;
    push @select, "";

    #       $select{""}="";
    while ( my ( $value, $desc ) = $req->fetchrow ) {
        push @select, $desc;

        #               $select{$value}=$desc;
    }
    my $CGIBookSellers = CGI::scrolling_list(
        -name   => 'Filter',
        -id     => 'Filter',
        -values => \@select,

        #                               -labels   => \%select,
        -size     => 1,
        -multiple => 0
    );

    $req =
      $dbh->prepare(
"SELECT DISTINCTROW itemtype,description FROM itemtypes ORDER BY description"
      );
    $req->execute;
    undef @select;
    undef %select;
    push @select, "";
    $select{""} = "";
    while ( my ( $value, $desc ) = $req->fetchrow ) {
        push @select, $value;
        $select{$value} = $desc;
    }
    my $CGIItemTypes = CGI::scrolling_list(
        -name     => 'Filter',
        -id       => 'Filter',
        -values   => \@select,
        -labels   => \%select,
        -size     => 1,
        -multiple => 0
    );

    $req =
      $dbh->prepare(
"SELECT DISTINCTROW bookfundid,bookfundname FROM aqbookfund ORDER BY bookfundname"
      );
    $req->execute;
    undef @select;
    undef %select;
    push @select, "";
    $select{""} = "";

    while ( my ( $value, $desc ) = $req->fetchrow ) {
        push @select, $value;
        $select{$value} = $desc;
    }
    my $CGIBudget = CGI::scrolling_list(
        -name     => 'Filter',
        -id       => 'Filter',
        -values   => \@select,
        -labels   => \%select,
        -size     => 1,
        -multiple => 0
    );

    $req =
      $dbh->prepare(
"SELECT DISTINCTROW sort1 FROM aqorders WHERE sort1 IS NOT NULL ORDER BY sort1"
      );
    $req->execute;
    undef @select;
    push @select, "";
    my $hassort1;
    while ( my ($value) = $req->fetchrow ) {
        $hassort1 = 1 if ($value);
        push @select, $value;
    }
    my $CGISort1 = CGI::scrolling_list(
        -name     => 'Filter',
        -id       => 'Filter',
        -values   => \@select,
        -size     => 1,
        -multiple => 0
    );

    $req =
      $dbh->prepare(
"SELECT DISTINCTROW sort2 FROM aqorders WHERE sort2 IS NOT NULL ORDER BY sort2"
      );
    $req->execute;
    undef @select;
    push @select, "";
    my $hassort2;
    my $hglghtsort2;

    while ( my ($value) = $req->fetchrow ) {
        $hassort2 = 1 if ($value);
        $hglghtsort2 = !($hassort1);
        push @select, $value;
    }
    my $CGISort2 = CGI::scrolling_list(
        -name     => 'Filter',
        -id       => 'Filter',
        -values   => \@select,
        -size     => 1,
        -multiple => 0
    );

    my @mime = ( C4::Context->preference("MIME") );
    foreach my $mime (@mime) {

        #               warn "".$mime;
    }

    my $CGIextChoice = CGI::scrolling_list(
        -name     => 'MIME',
        -id       => 'MIME',
        -values   => \@mime,
        -size     => 1,
        -multiple => 0
    );

    my @dels         = ( C4::Context->preference("delimiter") );
    my $CGIsepChoice = CGI::scrolling_list(
        -name     => 'sep',
        -id       => 'sep',
        -values   => \@dels,
        -size     => 1,
        -multiple => 0
    );

    $template->param(
        CGIBookSeller => $CGIBookSellers,
        CGIItemType   => $CGIItemTypes,
        CGIBudget     => $CGIBudget,
        hassort1      => $hassort1,
        hassort2      => $hassort2,
        HlghtSort2    => $hglghtsort2,
        CGISort1      => $CGISort1,
        CGISort2      => $CGISort2,
        CGIextChoice  => $CGIextChoice,
        CGIsepChoice  => $CGIsepChoice
    );

}
output_html_with_http_headers $input, $cookie, $template->output;

sub calculate {
    my ( $line, $column, $podsp, $rodsp, $aodsp, $process, $filters ) = @_;
    my @mainloop;
    my @loopfooter;
    my @loopcol;
    my @loopline;
    my @looprow;
    my %globalline;
    my $grantotal = 0;

    # extract parameters
    my $dbh = C4::Context->dbh;

    # Filters
    # Checking filters
    #
    my @loopfilter;
    for ( my $i = 0 ; $i <= 8 ; $i++ ) {
        my %cell;
        if ( @$filters[$i] ) {
            if ( ( ( $i == 1 ) or ( $i == 3 ) ) and ( @$filters[ $i - 1 ] ) ) {
                $cell{err} = 1 if ( @$filters[$i] < @$filters[ $i - 1 ] );
            }
            $cell{filter} .= @$filters[$i];
            $cell{crit}   .= "Placed On From" if ( $i == 0 );
            $cell{crit}   .= "Placed On To" if ( $i == 1 );
            $cell{crit}   .= "Received On From" if ( $i == 2 );
            $cell{crit}   .= "Received On To" if ( $i == 3 );

            $cell{crit} .= "Acquired On From" if ( $i == 4 );
            $cell{crit} .= "Acquired On To"   if ( $i == 5 );

            $cell{crit} .= "BookSeller" if ( $i == 6 );
            $cell{crit} .= "Doc Type"   if ( $i == 7 );
            $cell{crit} .= "Budget"     if ( $i == 8 );
            $cell{crit} .= "Sort1"      if ( $i == 9 );
            $cell{crit} .= "Sort2"      if ( $i == 10 );
            push @loopfilter, \%cell;
        }
    }

    my @linefilter;

    #       warn "filtres ".@filters[0];
    #       warn "filtres ".@filters[1];
    #       warn "filtres ".@filters[2];
    #       warn "filtres ".@filters[3];

    $linefilter[0] = @$filters[0] if ( $line =~ /closedate/ );
    $linefilter[1] = @$filters[1] if ( $line =~ /closedate/ );
    $linefilter[0] = @$filters[2] if ( $line =~ /received/ );
    $linefilter[1] = @$filters[3] if ( $line =~ /received/ );

    $linefilter[0] = @$filters[4] if ( $line =~ /acquired/ );
    $linefilter[1] = @$filters[5] if ( $line =~ /acquired/ );

    $linefilter[0] = @$filters[6]  if ( $line =~ /bookseller/ );
    $linefilter[0] = @$filters[7]  if ( $line =~ /itemtype/ );
    $linefilter[0] = @$filters[8]  if ( $line =~ /bookfund/ );
    $linefilter[0] = @$filters[9]  if ( $line =~ /sort1/ );
    $linefilter[0] = @$filters[10] if ( $line =~ /sort2/ );

    #warn "filtre lignes".$linefilter[0]." ".$linefilter[1];
    #
    my @colfilter;
    $colfilter[0] = @$filters[0] if ( $column =~ /closedate/ );
    $colfilter[1] = @$filters[1] if ( $column =~ /closedate/ );
    $colfilter[0] = @$filters[2] if ( $column =~ /received/ );
    $colfilter[1] = @$filters[3] if ( $column =~ /received/ );

    $colfilter[0] = @$filters[4] if ( $column =~ /acquired/ );
    $colfilter[1] = @$filters[5] if ( $column =~ /acquired/ );

    $colfilter[0] = @$filters[6]  if ( $column =~ /bookseller/ );
    $colfilter[0] = @$filters[7]  if ( $column =~ /itemtype/ );
    $colfilter[0] = @$filters[8]  if ( $column =~ /bookfund/ );
    $colfilter[0] = @$filters[9]  if ( $column =~ /sort1/ );
    $colfilter[0] = @$filters[10] if ( $column =~ /sort2/ );

    #warn "filtre col ".$colfilter[0]." ".$colfilter[1];

    #warn "line=$line, podsp=$podsp, rodsp=$rodsp, aodsp=$aodsp\n";

    # 1st, loop rows.
    my $linefield;
    if ( ( $line =~ /closedate/ ) and ( $podsp == 1 ) ) {

        #Display by day
        $linefield .= "dayname($line)";
    }
    elsif ( ( $line =~ /closedate/ ) and ( $podsp == 2 ) ) {

        #Display by Month
        $linefield .= "monthname($line)";
    }
    elsif ( ( $line =~ /closedate/ ) and ( $podsp == 3 ) ) {

        #Display by Year
        $linefield .= "Year($line)";

    }
    elsif ( ( $line =~ /received/ ) and ( $rodsp == 1 ) ) {

        #Display by day
        $linefield .= "dayname($line)";
    }
    elsif ( ( $line =~ /received/ ) and ( $rodsp == 2 ) ) {

        #Display by Month
        $linefield .= "monthname($line)";
    }
    elsif ( ( $line =~ /received/ ) and ( $rodsp == 3 ) ) {

        #Display by Year
        $linefield .= "Year($line)";

    }
    elsif ( ( $line =~ /acquired/ ) and ( $aodsp == 1 ) ) {

        #Display by day
        $linefield .= "dayname($line)";
    }
    elsif ( ( $line =~ /acquired/ ) and ( $aodsp == 2 ) ) {

        #Display by Month
        $linefield .= "monthname($line)";
    }
    elsif ( ( $line =~ /acquired/ ) and ( $aodsp == 3 ) ) {

        #Display by Year
        $linefield .= "Year($line)";

    }
    else {
        $linefield .= $line;
    }

    my $strsth;
    $strsth .=
      "SELECT DISTINCTROW $linefield FROM (aqorders, aqbasket,aqorderbreakdown)
                LEFT JOIN items ON (aqorders.biblioitemnumber= items.biblioitemnumber)
                LEFT JOIN biblioitems ON (aqorders.biblioitemnumber= biblioitems.biblioitemnumber)
                LEFT JOIN aqorderdelivery ON (aqorders.ordernumber =aqorderdelivery.ordernumber )
                LEFT JOIN aqbooksellers ON (aqbasket.booksellerid=aqbooksellers.id) WHERE (aqorders.basketno=aqbasket.basketno)
                AND (aqorderbreakdown.ordernumber=aqorders.ordernumber) AND $line IS NOT NULL ";

    if (@linefilter) {
        if ( $linefilter[1] ) {
            if ( $linefilter[0] ) {
                $strsth .= " AND $line BETWEEN ? AND ? ";
            }
            else {
                $strsth .= " AND $line < ? ";
            }
        }
        elsif (
            ( $linefilter[0] )
            and (  ( $line =~ /closedate/ )
                or ( $line =~ /received/ )
                or ( $line =~ /acquired/ ) )
          )
        {
            $strsth .= " AND $line > ? ";
        }
        elsif ( $linefilter[0] ) {
            $linefilter[0] =~ s/\*/%/g;
            $strsth .= " AND $line LIKE ? ";
        }
    }
    $strsth .= " GROUP BY $linefield";
    $strsth .= " ORDER BY $linefield";

    #warn "377:strsth= $strsth";

    my $sth = $dbh->prepare($strsth);
    if ( (@linefilter) and ( $linefilter[1] ) ) {
        $sth->execute( "'" . $linefilter[0] . "'", "'" . $linefilter[1] . "'" );
    }
    elsif ( $linefilter[0] ) {
        $sth->execute( $linefilter[0] );
    }
    else {
        $sth->execute;
    }

    while ( my ($celvalue) = $sth->fetchrow ) {
        my %cell;
        if ($celvalue) {
            $cell{rowtitle} = $celvalue;

            #               } else {
            #                       $cell{rowtitle} = "";
        }
        $cell{totalrow} = 0;
        push @loopline, \%cell;
    }

    #warn "column=$column, podsp=$podsp, rodsp=$rodsp, aodsp=$aodsp\n";

    # 2nd, loop cols.
    my $colfield;
    if ( ( $column =~ /closedate/ ) and ( $podsp == 1 ) ) {

        #Display by day
        $colfield .= "dayname($column)";
    }
    elsif ( ( $column =~ /closedate/ ) and ( $podsp == 2 ) ) {

        #Display by Month
        $colfield .= "monthname($column)";
    }
    elsif ( ( $column =~ /closedate/ ) and ( $podsp == 3 ) ) {

        #Display by Year
        $colfield .= "Year($column)";

    }
    elsif ( ( $column =~ /deliverydate/ ) and ( $rodsp == 1 ) ) {

        #Display by day
        $colfield .= "dayname($column)";
    }
    elsif ( ( $column =~ /deliverydate/ ) and ( $rodsp == 2 ) ) {

        #Display by Month
        $colfield .= "monthname($column)";
    }
    elsif ( ( $column =~ /deliverydate/ ) and ( $rodsp == 3 ) ) {

        #Display by Year
        $colfield .= "Year($column)";

    }
    elsif ( ( $column =~ /dateaccessioned/ ) and ( $aodsp == 1 ) ) {

        #Display by day
        $colfield .= "dayname($column)";
    }
    elsif ( ( $column =~ /dateaccessioned/ ) and ( $aodsp == 2 ) ) {

        #Display by Month
        $colfield .= "monthname($column)";
    }
    elsif ( ( $column =~ /dateaccessioned/ ) and ( $aodsp == 3 ) ) {

        #Display by Year
        $colfield .= "Year($column)";

    }
    else {
        $colfield .= $column;
    }

    my $strsth2;
    $strsth2 .=
      "SELECT distinctrow $colfield FROM (aqorders, aqbasket,aqorderbreakdown)
                 LEFT JOIN items ON (aqorders.biblioitemnumber= items.biblioitemnumber)
                 LEFT JOIN biblioitems ON (aqorders.biblioitemnumber= biblioitems.biblioitemnumber)
                 LEFT JOIN aqorderdelivery ON (aqorders.ordernumber =aqorderdelivery.ordernumber )
                 LEFT JOIN aqbooksellers ON (aqbasket.booksellerid=aqbooksellers.id)
                 WHERE (aqorders.basketno=aqbasket.basketno) AND (aqorderbreakdown.ordernumber=aqorders.ordernumber)
                 AND $column IS NOT NULL";

    if (@colfilter) {
        if ( $colfilter[1] ) {
            if ( $colfilter[0] ) {
                $strsth2 .= " AND $column BETWEEN  ? AND ? ";
            }
            else {
                $strsth2 .= " AND $column < ? ";
            }
        }
        elsif (
            ( $colfilter[0] )
            and (  ( $column =~ /closedate/ )
                or ( $line =~ /received/ )
                or ( $line =~ /acquired/ ) )
          )
        {
            $strsth2 .= " AND $column > ? ";
        }
        elsif ( $colfilter[0] ) {
            $colfilter[0] =~ s/\*/%/g;
            $strsth2 .= " AND $column LIKE ? ";
        }
    }
    $strsth2 .= " GROUP BY $colfield";
    $strsth2 .= " ORDER BY $colfield";

    #        warn "MASON:. $strsth2";

    my $sth2 = $dbh->prepare($strsth2);
    if ( (@colfilter) and ( $colfilter[1] ) ) {

        #                warn "from : ".$colfilter[0]." To  :".$colfilter[1];
        $sth2->execute( "'" . $colfilter[0] . "'", "'" . $colfilter[1] . "'" );
    }
    elsif ( $colfilter[0] ) {
        $sth2->execute( $colfilter[0] );
    }
    else {
        $sth2->execute;
    }

    while ( my ($celvalue) = $sth2->fetchrow ) {
        my %cell;
        if ($celvalue) {

            #               warn "coltitle :".$celvalue;
            $cell{coltitle} = $celvalue;
        }
        push @loopcol, \%cell;
    }

    #       warn "fin des titres colonnes";

    my $i = 0;
    my @totalcol;
    my $hilighted = -1;

    #Initialization of cell values.....
    my %table;

    #       warn "init table";
    foreach my $row (@loopline) {
        foreach my $col (@loopcol) {

#                       warn " init table : $row->{rowtitle} / $col->{coltitle} ";
            $table{ $row->{rowtitle} }->{ $col->{coltitle} } = 0;
        }
        $table{ $row->{rowtitle} }->{totalrow} = 0;
    }

    # preparing calculation
    my $strcalc;
    $strcalc .= "SELECT $linefield, $colfield, ";
    $strcalc .= "SUM( aqorders.quantity ) " if ( $process == 1 );
    $strcalc .= "SUM( aqorders.quantity * aqorders.listprice ) "
      if ( $process == 2 );
    $strcalc .= "FROM (aqorders, aqbasket,aqorderbreakdown)
                 LEFT JOIN items ON (aqorders.biblioitemnumber= items.biblioitemnumber)
                 LEFT JOIN biblioitems ON (aqorders.biblioitemnumber= biblioitems.biblioitemnumber)
                 LEFT JOIN aqorderdelivery ON (aqorders.ordernumber =aqorderdelivery.ordernumber )
                 LEFT JOIN aqbooksellers ON (aqbasket.booksellerid=aqbooksellers.id) WHERE (aqorders.basketno=aqbasket.basketno)
                      AND (aqorderbreakdown.ordernumber=aqorders.ordernumber) ";

    @$filters[0] =~ s/\*/%/g if ( @$filters[0] );
    $strcalc .= " AND aqbasket.closedate > '" . @$filters[0] . "'"
      if ( @$filters[0] );
    @$filters[1] =~ s/\*/%/g if ( @$filters[1] );
    $strcalc .= " AND aqbasket.closedate < '" . @$filters[1] . "'"
      if ( @$filters[1] );
    @$filters[2] =~ s/\*/%/g if ( @$filters[2] );
    $strcalc .= " AND aqorderdelivery.deliverydate > '" . @$filters[2] . "'"
      if ( @$filters[2] );
    @$filters[3] =~ s/\*/%/g if ( @$filters[3] );
    $strcalc .= " AND aqorderdelivery.deliverydate < '" . @$filters[3] . "'"
      if ( @$filters[3] );
    @$filters[4] =~ s/\*/%/g if ( @$filters[4] );
    $strcalc .= " AND aqbasket.closedate > '" . @$filters[4] . "'"
      if ( @$filters[4] );
    @$filters[5] =~ s/\*/%/g if ( @$filters[5] );
    $strcalc .= " AND aqbasket.closedate < '" . @$filters[5] . "'"
      if ( @$filters[5] );
    @$filters[6] =~ s/\*/%/g if ( @$filters[6] );
    $strcalc .= " AND aqbooksellers.name LIKE '" . @$filters[6] . "'"
      if ( @$filters[6] );
    @$filters[7] =~ s/\*/%/g if ( @$filters[7] );
    $strcalc .= " AND biblioitems.itemtype LIKE '" . @$filters[7] . "'"
      if ( @$filters[7] );
    @$filters[8] =~ s/\*/%/g if ( @$filters[8] );
    $strcalc .= " AND aqbookfund.bookfundid LIKE '" . @$filters[8] . "'"
      if ( @$filters[8] );
    @$filters[9] =~ s/\*/%/g if ( @$filters[9] );
    $strcalc .= " AND aqorders.sort1 LIKE '" . @$filters[9] . "'"
      if ( @$filters[9] );
    @$filters[10] =~ s/\*/%/g if ( @$filters[10] );
    $strcalc .= " AND aqorders.sort2 LIKE '" . @$filters[10] . "'"
      if ( @$filters[10] );
    $strcalc .= " GROUP BY $linefield, $colfield ORDER BY $linefield,$colfield";

    #        warn "/n/n". $strcalc;
    my $dbcalc = $dbh->prepare($strcalc);
    $dbcalc->execute;

    #       warn "filling table";
    my $emptycol;
    while ( my ( $row, $col, $value ) = $dbcalc->fetchrow ) {

        #              warn "filling table $row / $col / $value ";
        $emptycol = 1         if ( $col eq undef );
        $col      = "zzEMPTY" if ( $col eq undef );
        $row      = "zzEMPTY" if ( $row eq undef );

        $table{$row}->{$col}     += $value;
        $table{$row}->{totalrow} += $value;
        $grantotal               += $value;
    }

    push @loopcol, { coltitle => "NULL" } if ($emptycol);

    foreach my $row ( sort keys %table ) {
        my @loopcell;

        #@loopcol ensures the order for columns is common with column titles
        # and the number matches the number of columns
        foreach my $col (@loopcol) {
            my $value = $table{$row}->{
                ( $col->{coltitle} eq "NULL" )
                ? "zzEMPTY"
                : $col->{coltitle}
              };
            push @loopcell, { value => $value };
        }
        push @looprow,
          {
            'rowtitle' => ( $row eq "zzEMPTY" ) ? "NULL" : $row,
            'loopcell'  => \@loopcell,
            'hilighted' => ( $hilighted > 0 ),
            'totalrow'  => $table{$row}->{totalrow}
          };
        $hilighted = -$hilighted;
    }

    #       warn "footer processing";
    foreach my $col (@loopcol) {
        my $total = 0;
        foreach my $row (@looprow) {
            $total += $table{
                ( $row->{rowtitle} eq "NULL" ) ? "zzEMPTY"
                : $row->{rowtitle}
              }->{
                ( $col->{coltitle} eq "NULL" ) ? "zzEMPTY"
                : $col->{coltitle}
              };

#                       warn "value added ".$table{$row->{rowtitle}}->{$col->{coltitle}}. "for line ".$row->{rowtitle};
        }

        #               warn "summ for column ".$col->{coltitle}."  = ".$total;
        push @loopfooter, { 'totalcol' => $total };
    }

    # the header of the table
    #        $globalline{loopfilter}=\@loopfilter;
    # the core of the table
    $globalline{looprow} = \@looprow;
    $globalline{loopcol} = \@loopcol;

    #       # the foot (totals by borrower type)
    $globalline{loopfooter} = \@loopfooter;
    $globalline{total}      = $grantotal;
    $globalline{line}       = $line;
    $globalline{column}     = $column;
    push @mainloop, \%globalline;
    return \@mainloop;
}

1;

