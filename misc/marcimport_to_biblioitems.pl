#!/usr/bin/perl
# script that correct the marcxml  from in biblioitems 
#  Written by TG on 10/04/2006
use strict;

# Koha modules used

use C4::Context;
use C4::Biblio;
use MARC::Record;
use MARC::File::USMARC;
use MARC::File::XML;
use MARC::Batch;
use Time::HiRes qw(gettimeofday);
use Getopt::Long;
my  $input_marc_file = '';
my ($version);
GetOptions(
    'file:s'    => \$input_marc_file,
    'h' => \$version,
);

if ($version || ($input_marc_file eq '')) {
	print <<EOF
small script to import an iso2709 file into Koha with existing biblionumbers in marc record.
parameters :
\th : this version/help screen
\tfile /path/to/file/to/dump : the file to dump
SAMPLE : 
\t\$ export KOHA_CONF=/etc/koha.conf
\t\$ perl misc/marcimport_to_biblioitems.pl  -file /home/jmf/koha.mrc 
EOF
;#'
die;
}
my $starttime = gettimeofday;
my $timeneeded;
my $dbh = C4::Context->dbh;

my $sth2=$dbh->prepare("update biblioitems  set marc=? where biblionumber=?");
my $i=0;

my $batch = MARC::Batch->new( 'USMARC', $input_marc_file );
$batch->warnings_off();
$batch->strict_off();
my $i=0;
my ($tagfield,$biblionumtagsubfield) = &MARCfind_marc_from_kohafield($dbh,"biblio.biblionumber","");

while ( my $record = $batch->next() ) {
my $biblionumber=$record->field($tagfield)->subfield($biblionumtagsubfield);
$i++;
$sth2->execute($record->as_usmarc,$biblionumber) if $biblionumber;
print "$biblionumber \n";
}

$timeneeded = gettimeofday - $starttime ;
	print "$i records in $timeneeded s\n" ;

END;
sub search{
my ($query)=@_;
my $nquery="\ \@attr 1=1007  ".$query;
my $oAuth=C4::Context->Zconn("biblioserver");
if ($oAuth eq "error"){
warn "Error/CONNECTING \n";
 return("error",undef);
}
my $oAResult;
my $Anewq= new ZOOM::Query::PQF($nquery);
eval {
$oAResult= $oAuth->search_pqf($nquery) ; 
};
if($@){
warn " /Cannot search:", $@->code()," /MSG:",$@->message(),"\n";
  return("error",undef);
}
my $authrecord;
my $nbresults="0";
 $nbresults=$oAResult->size();
if ($nbresults eq "1" ){
my $rec=$oAResult->record(0);
my $marcdata=$rec->raw();
 $authrecord = MARC::File::USMARC::decode($marcdata);
}
return ($authrecord,$nbresults);
}