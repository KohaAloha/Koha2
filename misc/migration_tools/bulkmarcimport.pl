#!/usr/bin/perl
# small script that import an iso2709 file into koha 2.0

use strict;
# use warnings;

# Koha modules used
use MARC::File::USMARC;
# Uncomment the line below and use MARC::File::XML again when it works better.
# -- thd
# use MARC::File::XML;
use MARC::Record;
use MARC::Batch;
use MARC::Charset;

# According to kados, an undocumented feature of setting MARC::Charset to 
# ignore_errors(1) is that errors are not ignored.  Instead of deleting the 
# whole subfield when a character does not translate properly from MARC8 into 
# UTF-8, just the problem characters are deleted.  This should solve at least 
# some of the fixme problems for fMARC8ToUTF8().
# 
# Problems remain if there are MARC 21 records where 000/09 is set incorrectly. 
# -- thd.
# MARC::Charset->ignore_errors(1);

use C4::Context;
use C4::Biblio;
use Time::HiRes qw(gettimeofday);
use Getopt::Long;
binmode(STDOUT, ":utf8");

use Getopt::Long;

my ( $input_marc_file, $number) = ('',0);
my ($version, $delete, $test_parameter,$char_encoding, $verbose, $commit,$fk_off);

$|=1;

GetOptions(
    'commit:f'    => \$commit,
    'file:s'    => \$input_marc_file,
    'n:f' => \$number,
    'h' => \$version,
    'd' => \$delete,
    't' => \$test_parameter,
    'c:s' => \$char_encoding,
    'v:s' => \$verbose,
    'fk' => \$fk_off,
);

# FIXME:  Management of error conditions needed for record parsing problems
# and MARC8 character sets with mappings to Unicode not yet included in 
# MARC::Charset.  The real world rarity of these problems is not fully tested.
# Unmapped character sets will throw a warning currently and processing will 
# continue with the error condition.  A fairly trivial correction should 
# address some record parsing and unmapped character set problems but I need 
# time to implement a test and correction for undef subfields and revert to 
# MARC8 if mappings are missing. -- thd
sub fMARC8ToUTF8($$) {
    my ($record) = shift;
    my ($verbose) = shift;
    if ($verbose) {
        if ($verbose >= 2) {
            my $leader = $record->leader();
            $leader =~ s/ /#/g;
            print "\n000 " . $leader;
        }
    }
    foreach my $field ($record->fields()) {
        if ($field->is_control_field()) {
            if ($verbose) {
                if ($verbose >= 2) {
                    my $fieldName = $field->tag();
                    my $fieldValue = $field->data();
                    $fieldValue =~ s/ /#/g;
                    print "\n" . $fieldName;
                    print ' ' . $fieldValue;
                }
            }
        } else {
            my @subfieldsArray;
            my $fieldName = $field->tag();
            my $indicator1Value = $field->indicator(1);
            my $indicator2Value = $field->indicator(2);
            if ($verbose) {
                if ($verbose >= 2) {
                    $indicator1Value =~ s/ /#/;
                    $indicator2Value =~ s/ /#/;
                    print "\n" . $fieldName . ' ' .
                            $indicator1Value .
                    $indicator2Value;
                }
            }
            foreach my $subfield ($field->subfields()) {
                my $subfieldName = $subfield->[0];
                my $subfieldValue = $subfield->[1];
                $subfieldValue = MARC::Charset::marc8_to_utf8($subfieldValue);
    
                # Alas, MARC::Field::update() does not work correctly.
                ## push (@subfieldsArray, $subfieldName, $subfieldValue);
    
                push @subfieldsArray, [$subfieldName, $subfieldValue];
                if ($verbose) {
                    if ($verbose >= 2) {
                        print " \$" . $subfieldName . ' ' . $subfieldValue;
                    }
                }
            }
    
            # Alas, MARC::Field::update() does not work correctly.
            #
            # The first instance in the field of a of a repeated subfield
            # overwrites the content from later instances with the content
            # from the first instance.
            ## $field->update(@subfieldsArray);
    
            foreach my $subfieldRow(@subfieldsArray) {
                my $subfieldName = $subfieldRow->[0];
                $field->delete_subfields($subfieldName);
            }
            foreach my $subfieldRow(@subfieldsArray) {
                $field->add_subfields(@$subfieldRow);
            }
    
            if ($verbose) {
                if ($verbose >= 2) {
                    # Reading the indicator values again is not necessary.
                    # They were not converted.
                    # $indicator1Value = $field->indicator(1);
                    # $indicator2Value = $field->indicator(2);
                    # $indicator1Value =~ s/ /#/;
                    # $indicator2Value =~ s/ /#/;
                    print "\nCONVERTED TO UTF-8:\n" . $fieldName . ' ' .
                            $indicator1Value .
                    $indicator2Value;
                    foreach my $subfield ($field->subfields()) {
                        my $subfieldName = $subfield->[0];
                        my $subfieldValue = $subfield->[1];
                        print " \$" . $subfieldName . ' ' . $subfieldValue;
                    }
                }
            }
            if ($verbose) {
                if ($verbose >= 2) {
                    print "\n" if $verbose;
                }
            }
        }
    }
    $record->encoding('UTF-8');
    return $record;
}


if ($version || ($input_marc_file eq '')) {
    print <<EOF
small script to import an iso2709 file into Koha.
parameters :
\th : this version/help screen
\tfile /path/to/file/to/dump : the file to dump
\tv : verbose mode. 1 means "some infos", 2 means "MARC dumping"
\tfk : Turn off foreign key checks during import.                
\tn : the number of records to import. If missing, all the file is imported
\tcommit : the number of records to wait before performing a 'commit' operation
\tt : test mode : parses the file, saying what he would do, but doing nothing.
\tc : the characteristic MARC flavour. At the moment, only MARC21 and UNIMARC 
\tsupported. MARC21 by default.
\td : delete EVERYTHING related to biblio in koha-DB before import  :tables :
\t\tbiblio, \t\tbiblioitems, \t\tsubjects,\titems
\tmarc_biblio,
\t\tmarc_subfield_table, \tmarc_word, \t\tmarc_blob_subfield
IMPORTANT : don't use this script before you've entered and checked your MARC parameters tables twice (or more!).
Otherwise, the import won't work correctly and you will get invalid data.

SAMPLE : 
\t\$ export KOHA_CONF=/etc/koha.conf
\t\$ perl misc/migration_tools/bulkmarcimport.pl -d -commit 1000 -file /home/jmf/koha.mrc -n 3000
EOF
;#'
die;
}

my $dbh = C4::Context->dbh;

if ($delete) {
    print "deleting biblios\n";
    $dbh->do("truncate biblio");
    $dbh->do("truncate biblioitems");
    $dbh->do("truncate items");
}
if ($fk_off) {
	$dbh->do("SET FOREIGN_KEY_CHECKS = 0");
}
if ($test_parameter) {
    print "TESTING MODE ONLY\n    DOING NOTHING\n===============\n";
}

my $marcFlavour = C4::Context->preference('marcflavour') || 'MARC21';

print "Characteristic MARC flavour: $marcFlavour\n" if $verbose;
# die;
my $starttime = gettimeofday;
my $batch = MARC::Batch->new( 'USMARC', $input_marc_file );
$batch->warnings_off();
$batch->strict_off();
my $i=0;
my $commitnum = 50;

if ($commit) {

$commitnum = $commit;

}

#1st of all, find item MARC tag.
my ($tagfield,$tagsubfield) = &GetMarcFromKohaField("items.itemnumber",'');
# $dbh->do("lock tables biblio write, biblioitems write, items write, marc_biblio write, marc_subfield_table write, marc_blob_subfield write, marc_word write, marc_subfield_structure write, stopwords write");
while ( my $record = $batch->next() ) {
# warn "=>".$record->as_formatted;
# warn "I:".$i;
# warn "NUM:".$number;
    $i++;
    print ".";
    print "\r$i" unless $i % 100;
#     if ($i==$number) {
#         z3950_extended_services('commit',set_service_options('commit'));
#         print "COMMIT OPERATION SUCCESSFUL\n";
# 
#         my $timeneeded = gettimeofday - $starttime;
#         die "$i MARC records imported in $timeneeded seconds\n";
#     }
#     # perform the commit operation ever so often
#     if ($i==$commit) {
#         z3950_extended_services('commit',set_service_options('commit'));
#         $commit+=$commitnum;
#         print "COMMIT OPERATION SUCCESSFUL\n";
#     }
    #now, parse the record, extract the item fields, and store them in somewhere else.

    ## create an empty record object to populate
    my $newRecord = MARC::Record->new();
    $newRecord->leader($record->leader());

    # go through each field in the existing record
    foreach my $oldField ( $record->fields() ) {

    # just reproduce tags < 010 in our new record
    #
    # Fields are not necessarily only numeric in the actual world of records
    # nor in what I would recommend for additonal safe non-interfering local
    # use fields.  The following regular expression match is much safer than
    # a numeric evaluation. -- thd
    if ( $oldField->tag() =~ m/^00/ ) {
        $newRecord->append_fields( $oldField );
        next();
    }

    # store our new subfield data in this list
    my @newSubfields = ();

    # go through each subfield code/data pair
    foreach my $pair ( $oldField->subfields() ) {
        #$pair->[1] =~ s/\<//g;
        #$pair->[1] =~ s/\>//g;
        push( @newSubfields, $pair->[0], $pair->[1] ); #char_decode($pair->[1],$char_encoding) );
    }

    # add the new field to our new record
    my $newField = MARC::Field->new(
        $oldField->tag(),
        $oldField->indicator(1),
        $oldField->indicator(2),
        @newSubfields
    );

    $newRecord->append_fields( $newField );

    }

    warn "$i ==>".$newRecord->as_formatted() if $verbose eq 2;
    my @fields = $newRecord->field($tagfield);
    my @items;
    my $nbitems=0;

    foreach my $field (@fields) {
        my $item = MARC::Record->new();
        $item->append_fields($field);
        push @items,$item;
        $newRecord->delete_field($field);
        $nbitems++;
    }
    print "$i : $nbitems items found\n" if $verbose;
    # now, create biblio and items with Addbiblio call.
    unless ($test_parameter) {
    warn "NEWREC : ".$newRecord->as_formatted;
        my ($bibid,$oldbibitemnum) = AddBiblio($newRecord,'');
        warn "ADDED biblio NB $bibid in DB\n" if $verbose;
        for (my $i=0;$i<=$#items;$i++) {
#             warn "here is the biblioitemnumber $oldbibitemnum";
            AddItem($items[$i],$bibid,$oldbibitemnum);
        }
    }
}
if ($fk_off) {
	$dbh->do("SET FOREIGN_KEY_CHECKS = 1");
}
# final commit of the changes
#z3950_extended_services('commit',set_service_options('commit'));
#print "COMMIT OPERATION SUCCESSFUL\n";

my $timeneeded = gettimeofday - $starttime;
print "$i MARC records done in $timeneeded seconds\n";
