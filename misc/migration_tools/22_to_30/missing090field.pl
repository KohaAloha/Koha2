#!/usr/bin/perl
# This script finds and fixes missing 090 fields in Koha for MARC21
#  Written by TG on 01/10/2005
#  Revised by Joshua Ferraro on 03/31/2006
use strict;

# Koha modules used

use C4::Context;
use C4::Biblio;
use MARC::Record;
use MARC::File::USMARC;

$|=1;
my $dbh = C4::Context->dbh;

my $sth=$dbh->prepare("select m.biblionumber,b.biblioitemnumber from marc_biblio m left join biblioitems b on b.biblionumber=m.biblionumber");
	$sth->execute();

my $i=1;
while (my ($biblionumber,$biblioitemnumber)=$sth->fetchrow ){
 my $record = GetMarcBiblio($biblionumber);
    print ".";	
    print "\r$i" unless $i %100;
    MARCmodbiblionumber($biblionumber,$biblioitemnumber,$record);
}

sub MARCmodbiblionumber{
    my ($biblionumber,$biblioitemnumber,$record)=@_;
    
    my ($tagfield,$biblionumtagsubfield) = &MARCfind_marc_from_kohafield($dbh,"biblio.biblionumber","");
    my ($tagfield2,$biblioitemtagsubfield) = &MARCfind_marc_from_kohafield($dbh,"biblio.biblioitemnumber","");
        
    my $update=0;
        my @tags = $record->field($tagfield);
    
    if (!@tags){
        my $newrec = MARC::Field->new( $tagfield,'','', $biblionumtagsubfield => $biblionumber,$biblioitemtagsubfield=>$biblioitemnumber);
            $record->append_fields($newrec);
        $update=1;
    }
    
    
    if ($update){	
        &MARCmodbiblio($dbh,$biblionumber,$record,'',0);
        print "\n modified : $biblionumber \n";	
    }
    
}
END;
