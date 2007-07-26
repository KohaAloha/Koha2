package C4::AuthoritiesMarc;
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
use C4::Context;
use C4::Koha;
use MARC::Record;
use C4::Biblio;
use C4::Search;

use vars qw($VERSION @ISA @EXPORT);

# set the version for version checking
$VERSION = do { my @v = '$Revision$' =~ /\d+/g; shift(@v).".".join( "_", map { sprintf "%03d", $_ } @v ); };

@ISA = qw(Exporter);
@EXPORT = qw(
    &GetTagsLabels
    &GetAuthType
    &GetAuthTypeCode
    &GetAuthMARCFromKohaField 
    &AUTHhtml2marc

    &AddAuthority
    &ModAuthority
    &DelAuthority
    &GetAuthority
    &GetAuthorityXML
    
    &CountUsage
    &CountUsageChildren
    &SearchAuthorities
    
    &BuildSummary
    &BuildUnimarcHierarchies
    &BuildUnimarcHierarchy
    
    &merge
    &FindDuplicateAuthority
 );

=head2 GetAuthMARCFromKohaField 

=over 4

( $tag, $subfield ) = &GetAuthMARCFromKohaField ($kohafield,$authtypecode);
returns tag and subfield linked to kohafield

Comment :
Suppose Kohafield is only linked to ONE subfield
=back

=cut
sub GetAuthMARCFromKohaField {
#AUTHfind_marc_from_kohafield
  my ( $kohafield,$authtypecode ) = @_;
  my $dbh=C4::Context->dbh;
  return 0, 0 unless $kohafield;
  $authtypecode="" unless $authtypecode;
  my $marcfromkohafield;
  my $sth = $dbh->prepare("select tagfield,tagsubfield from auth_subfield_structure where kohafield= ? and authtypecode=? ");
  $sth->execute($kohafield,$authtypecode);
  my ($tagfield,$tagsubfield) = $sth->fetchrow;
    
  return  ($tagfield,$tagsubfield);
}

=head2 SearchAuthorities 

=over 4

(\@finalresult, $nbresults)= &SearchAuthorities($tags, $and_or, $excluding, $operator, $value, $offset,$length,$authtypecode,$sortby)
returns ref to array result and count of results returned

=back

=cut
sub SearchAuthorities {
    my ($tags, $and_or, $excluding, $operator, $value, $offset,$length,$authtypecode,$sortby) = @_;
#     warn "CALL : $tags, $and_or, $excluding, $operator, $value, $offset,$length,$authtypecode,$sortby";
    my $dbh=C4::Context->dbh;
    if (C4::Context->preference('NoZebra')) {
    
        #
        # build the query
        #
        my $query;
        my @auths=split / /,$authtypecode ;
        foreach my  $auth (@auths){
            $query .="AND auth_type= $auth ";
        }
        $query =~ s/^AND //;
        my $dosearch;
        for(my $i = 0 ; $i <= $#{$value} ; $i++)
        {
            if (@$value[$i]){
                if (@$tags[$i] eq "mainmainentry") {
                    $query .=" AND mainmainentry";
                }elsif (@$tags[$i] eq "mainentry") {
                    $query .=" AND mainentry";
                } else {
                    $query .=" AND ";
                }
                if (@$operator[$i] eq 'is') {
                    $query.=(@$tags[$i]?"=":""). '"'.@$value[$i].'"';
                }elsif (@$operator[$i] eq "="){
                    $query.=(@$tags[$i]?"=":""). '"'.@$value[$i].'"';
                }elsif (@$operator[$i] eq "start"){
                    $query.=(@$tags[$i]?"=":"").'"'.@$value[$i].'%"';
                } else {
                    $query.=(@$tags[$i]?"=":"").'"'.@$value[$i].'%"';
                }
                $dosearch=1;
            }#if value
        }
        #
        # do the query (if we had some search term
        #
        if ($dosearch) {
#             warn "QUERY : $query";
            my $result = C4::Search::NZanalyse($query,'authorityserver');
#             warn "result : $result";
            my %result;
            foreach (split /;/,$result) {
                my ($authid,$title) = split /,/,$_;
                # hint : the result is sorted by title.biblionumber because we can have X biblios with the same title
                # and we don't want to get only 1 result for each of them !!!
                # hint & speed improvement : we can order without reading the record
                # so order, and read records only for the requested page !
                $result{$title.$authid}=$authid;
            }
            # sort the hash and return the same structure as GetRecords (Zebra querying)
            my @finalresult = ();
            my $numbers=0;
            if ($sortby eq 'HeadingDsc') { # sort by mainmainentry desc
                foreach my $key (sort {$b cmp $a} (keys %result)) {
                    push @finalresult, $result{$key};
#                     warn "push..."$#finalresult;
                    $numbers++;
                }
            } else { # sort by mainmainentry ASC
                foreach my $key (sort (keys %result)) {
                    push @finalresult, $result{$key};
#                     warn "push..."$#finalresult;
                    $numbers++;
                }
            }
            # limit the $results_per_page to result size if it's more
            $length = $numbers-1 if $numbers < $length;
            # for the requested page, replace authid by the complete record
            # speed improvement : avoid reading too much things
            for (my $counter=$offset;$counter<=$offset+$length;$counter++) {
#                 $finalresult[$counter] = GetAuthority($finalresult[$counter])->as_usmarc;
                my $separator=C4::Context->preference('authoritysep');
                my $authrecord = MARC::File::USMARC::decode(GetAuthority($finalresult[$counter])->as_usmarc);
                my $authid=$authrecord->field('001')->data(); 
                my $summary=BuildSummary($authrecord,$authid,$authtypecode);
                my $query_auth_tag = "SELECT auth_tag_to_report FROM auth_types WHERE authtypecode=?";
                my $sth = $dbh->prepare($query_auth_tag);
                $sth->execute($authtypecode);
                my $auth_tag_to_report = $sth->fetchrow;
                my %newline;
                $newline{used}=CountUsage($authid);
                $newline{summary} = $summary;
                $newline{authid} = $authid;
                $newline{even} = $counter % 2;
                $finalresult[$counter]= \%newline;
            }
            return (\@finalresult, $numbers);
        } else {
            return;
        }
    } else {
        my $query;
        my $attr;
            # the marclist may contain "mainentry". In this case, search the tag_to_report, that depends on
            # the authtypecode. Then, search on $a of this tag_to_report
            # also store main entry MARC tag, to extract it at end of search
        my $mainentrytag;
        ##first set the authtype search and may be multiple authorities
        my $n=0;
        my @authtypecode;
        my @auths=split / /,$authtypecode ;
        foreach my  $auth (@auths){
            $query .=" \@attr 1=Authority/format-id \@attr 5=100 ".$auth; ##No truncation on authtype
            push @authtypecode ,$auth;
            $n++;
        }
        if ($n>1){
            $query= "\@or ".$query;
        }
        
        my $dosearch;
        my $and;
        my $q2;
        for(my $i = 0 ; $i <= $#{$value} ; $i++)
        {
            if (@$value[$i]){
            ##If mainentry search $a tag
                if (@$tags[$i] eq "mainmainentry") {
                $attr =" \@attr 1=Heading ";
                }elsif (@$tags[$i] eq "mainentry") {
                $attr =" \@attr 1=Heading-Entity ";
                }else{
                $attr =" \@attr 1=Any ";
                }
                if (@$operator[$i] eq 'is') {
                    $attr.=" \@attr 4=1  \@attr 5=100 ";##Phrase, No truncation,all of subfield field must match
                }elsif (@$operator[$i] eq "="){
                    $attr.=" \@attr 4=107 ";           #Number Exact match
                }elsif (@$operator[$i] eq "start"){
                    $attr.=" \@attr 4=1 \@attr 5=1 ";#Phrase, Right truncated
                } else {
                    $attr .=" \@attr 5=1 \@attr 4=6 ";## Word list, right truncated, anywhere
                }
                $and .=" \@and " ;
                $attr =$attr."\"".@$value[$i]."\"";
                $q2 .=$attr;
            $dosearch=1;
            }#if value
        }
        ##Add how many queries generated
        $query= $and.$query.$q2;
        ## Adding order
        $query=' @or  @attr 7=1 @attr 1=Heading 0 @or  @attr 7=1 @attr 1=Heading-Entity 1'.$query if ($sortby eq "HeadingAsc");
        $query=' @or  @attr 7=2 @attr 1=Heading 0 @or  @attr 7=1 @attr 1=Heading-Entity 1'.$query if ($sortby eq "HeadingDsc");
        
        $offset=0 unless $offset;
        my $counter = $offset;
        $length=10 unless $length;
        my @oAuth;
        my $i;
        $oAuth[0]=C4::Context->Zconn("authorityserver" , 1);
        my $Anewq= new ZOOM::Query::PQF($query,$oAuth[0]);
        my $oAResult;
        $oAResult= $oAuth[0]->search($Anewq) ; 
        while (($i = ZOOM::event(\@oAuth)) != 0) {
            my $ev = $oAuth[$i-1]->last_event();
            last if $ev == ZOOM::Event::ZEND;
        }
        my($error, $errmsg, $addinfo, $diagset) = $oAuth[0]->error_x();
        if ($error) {
            warn  "oAuth error: $errmsg ($error) $addinfo $diagset\n";
            goto NOLUCK;
        }
        
        my $nbresults;
        $nbresults=$oAResult->size();
        my $nremains=$nbresults;    
        my @result = ();
        my @finalresult = ();
        
        if ($nbresults>0){
        
        ##Find authid and linkid fields
        ##we may be searching multiple authoritytypes.
        ## FIXME this assumes that all authid and linkid fields are the same for all authority types
        # my ($authidfield,$authidsubfield)=GetAuthMARCFromKohaField($dbh,"auth_header.authid",$authtypecode[0]);
        # my ($linkidfield,$linkidsubfield)=GetAuthMARCFromKohaField($dbh,"auth_header.linkid",$authtypecode[0]);
            while (($counter < $nbresults) && ($counter < ($offset + $length))) {
            
            ##Here we have to extract MARC record and $authid from ZEBRA AUTHORITIES
            my $rec=$oAResult->record($counter);
            my $marcdata=$rec->raw();
            my $authrecord;
            my $separator=C4::Context->preference('authoritysep');
            $authrecord = MARC::File::USMARC::decode($marcdata);
            my $authid=$authrecord->field('001')->data(); 
            my $summary=BuildSummary($authrecord,$authid,$authtypecode);
            my $query_auth_tag = "SELECT auth_tag_to_report FROM auth_types WHERE authtypecode=?";
            my $sth = $dbh->prepare($query_auth_tag);
            $sth->execute($authtypecode);
            my $auth_tag_to_report = $sth->fetchrow;
            my %newline;
            $newline{summary} = $summary;
            $newline{authid} = $authid;
            $newline{even} = $counter % 2;
            $counter++;
            push @finalresult, \%newline;
            }## while counter
        ###
        for (my $z=0; $z<@finalresult; $z++){
                my  $count=CountUsage($finalresult[$z]{authid});
                $finalresult[$z]{used}=$count;
        }# all $z's
        
        }## if nbresult
        NOLUCK:
        # $oAResult->destroy();
        # $oAuth[0]->destroy();
        
        return (\@finalresult, $nbresults);
    }
}

=head2 CountUsage 

=over 4

$count= &CountUsage($authid)
counts Usage of Authid in bibliorecords. 

=back

=cut

sub CountUsage {
    my ($authid) = @_;
    if (C4::Context->preference('NoZebra')) {
        # Read the index Koha-Auth-Number for this authid and count the lines
        my $result = C4::Search::NZanalyse("an=$authid");
        my @tab = split /;/,$result;
        return scalar @tab;
    } else {
        ### ZOOM search here
        my $oConnection=C4::Context->Zconn("biblioserver",1);
        my $query;
        $query= "an=".$authid;
        my $oResult = $oConnection->search(new ZOOM::Query::CCL2RPN( $query, $oConnection ));
        my $result;
        while ((my $i = ZOOM::event([ $oConnection ])) != 0) {
            my $ev = $oConnection->last_event();
            if ($ev == ZOOM::Event::ZEND) {
                $result = $oResult->size();
            }
        }
        return ($result);
    }
}

=head2 CountUsageChildren 

=over 4

$count= &CountUsageChildren($authid)
counts Usage of narrower terms of Authid in bibliorecords.

=back

=cut
sub CountUsageChildren {
  my ($authid) = @_;
}

=head2 GetAuthTypeCode

=over 4

$authtypecode= &GetAuthTypeCode($authid)
returns authtypecode of an authid

=back

=cut
sub GetAuthTypeCode {
#AUTHfind_authtypecode
  my ($authid) = @_;
  my $dbh=C4::Context->dbh;
  my $sth = $dbh->prepare("select authtypecode from auth_header where authid=?");
  $sth->execute($authid);
  my ($authtypecode) = $sth->fetchrow;
  return $authtypecode;
}
 
=head2 GetTagsLabels

=over 4

$tagslabel= &GetTagsLabels($forlibrarian,$authtypecode)
returns a ref to hashref of authorities tag and subfield structure.

tagslabel usage : 
$tagslabel->{$tag}->{$subfield}->{'attribute'}
where attribute takes values in :
  lib
  tab
  mandatory
  repeatable
  authorised_value
  authtypecode
  value_builder
  kohafield
  seealso
  hidden
  isurl
  link

=back

=cut
sub GetTagsLabels {
  my ($forlibrarian,$authtypecode)= @_;
  my $dbh=C4::Context->dbh;
  $authtypecode="" unless $authtypecode;
  my $sth;
  my $libfield = ($forlibrarian eq 1)? 'liblibrarian' : 'libopac';


  # check that authority exists
  $sth=$dbh->prepare("select count(*) from auth_tag_structure where authtypecode=?");
  $sth->execute($authtypecode);
  my ($total) = $sth->fetchrow;
  $authtypecode="" unless ($total >0);
  $sth= $dbh->prepare(
"SELECT tagfield,liblibrarian,libopac,mandatory,repeatable 
 FROM auth_tag_structure 
 WHERE authtypecode=? 
 ORDER BY tagfield"
    );

  $sth->execute($authtypecode);
  my ( $liblibrarian, $libopac, $tag, $res, $tab, $mandatory, $repeatable );

  while ( ( $tag, $liblibrarian, $libopac, $mandatory, $repeatable ) = $sth->fetchrow ) {
        $res->{$tag}->{lib}        = ($forlibrarian or !$libopac)?$liblibrarian:$libopac;
        $res->{$tag}->{tab}        = " ";            # XXX
        $res->{$tag}->{mandatory}  = $mandatory;
        $res->{$tag}->{repeatable} = $repeatable;
  }
  $sth=      $dbh->prepare(
"SELECT tagfield,tagsubfield,liblibrarian,libopac,tab, mandatory, repeatable,authorised_value,authtypecode,value_builder,kohafield,seealso,hidden,isurl 
FROM auth_subfield_structure 
WHERE authtypecode=? 
ORDER BY tagfield,tagsubfield"
    );
    $sth->execute($authtypecode);

    my $subfield;
    my $authorised_value;
    my $value_builder;
    my $kohafield;
    my $seealso;
    my $hidden;
    my $isurl;
    my $link;

    while (
        ( $tag,         $subfield,   $liblibrarian,   , $libopac,      $tab,
        $mandatory,     $repeatable, $authorised_value, $authtypecode,
        $value_builder, $kohafield,  $seealso,          $hidden,
        $isurl,            $link )
        = $sth->fetchrow
      )
    {
        $res->{$tag}->{$subfield}->{lib}              = ($forlibrarian or !$libopac)?$liblibrarian:$libopac;
        $res->{$tag}->{$subfield}->{tab}              = $tab;
        $res->{$tag}->{$subfield}->{mandatory}        = $mandatory;
        $res->{$tag}->{$subfield}->{repeatable}       = $repeatable;
        $res->{$tag}->{$subfield}->{authorised_value} = $authorised_value;
        $res->{$tag}->{$subfield}->{authtypecode}     = $authtypecode;
        $res->{$tag}->{$subfield}->{value_builder}    = $value_builder;
        $res->{$tag}->{$subfield}->{kohafield}        = $kohafield;
        $res->{$tag}->{$subfield}->{seealso}          = $seealso;
        $res->{$tag}->{$subfield}->{hidden}           = $hidden;
        $res->{$tag}->{$subfield}->{isurl}            = $isurl;
        $res->{$tag}->{$subfield}->{link}            = $link;
    }
    return $res;
}

=head2 AddAuthority

=over 4

$authid= &AddAuthority($record, $authid,$authtypecode)
returns authid of the newly created authority

Either Create Or Modify existing authority.

=back

=cut
sub AddAuthority {
# pass the MARC::Record to this function, and it will create the records in the authority table
  my ($record,$authid,$authtypecode) = @_;
  my $dbh=C4::Context->dbh;
  my $leader='         a              ';##Fixme correct leader as this one just adds utf8 to MARC21

# if authid empty => true add, find a new authid number
  if (!$authid) {
    my $sth=$dbh->prepare("select max(authid) from auth_header");
    $sth->execute;
    ($authid)=$sth->fetchrow;
    $authid=$authid+1;
  ##Insert the recordID in MARC record 
  ##Both authid and authtypecode is expected to be in the same field. Modify if other requirements arise
    $record->add_fields('001',$authid) unless $record->field('001');
    $record->add_fields('152','','','b'=>$authtypecode) unless $record->field('152');
#     warn $record->as_formatted;
    $dbh->do("lock tables auth_header WRITE");
    $sth=$dbh->prepare("insert into auth_header (authid,datecreated,authtypecode,marc,marcxml) values (?,now(),?,?,?)");
    $sth->execute($authid,$authtypecode,$record->as_usmarc,$record->as_xml_record);
    $sth->finish;
  }else{
      $record->add_fields('001',$authid) unless ($record->field('001'));
      $record->add_fields('100',$authid) unless ($record->field('100'));
      $record->add_fields('152','','','b'=>$authtypecode) unless ($record->field('152'));
      $dbh->do("lock tables auth_header WRITE");
      my $sth=$dbh->prepare("update auth_header set marc=?,marcxml=? where authid=?");
      $sth->execute($record->as_usmarc,$record->as_xml_record,$authid);
      $sth->finish;
  }
  $dbh->do("unlock tables");
  ModZebra($authid,'specialUpdate',"authorityserver",$record);
  return ($authid);
}


=head2 DelAuthority

=over 4

$authid= &DelAuthority($authid)
Deletes $authid

=back

=cut


sub DelAuthority {
    my ($authid) = @_;
    my $dbh=C4::Context->dbh;

    ModZebra($authid,"recordDelete","authorityserver",GetAuthority($authid));
    $dbh->do("delete from auth_header where authid=$authid") ;

}

sub ModAuthority {
  my ($authid,$record,$authtypecode,$merge)=@_;
  my $dbh=C4::Context->dbh;
#   my ($oldrecord)=&GetAuthority($authid);
#   if ($oldrecord eq $record) {
#       return;
#   }
#   my $sth=$dbh->prepare("update auth_header set marc=?,marcxml=? where authid=?");
  #Now rewrite the $record to table with an add
  $authid=AddAuthority($record,$authid,$authtypecode);

### If a library thinks that updating all biblios is a long process and wishes to leave that to a cron job to use merge_authotities.p
### they should have a system preference "dontmerge=1" otherwise by default biblios will be updated
### the $merge flag is now depreceated and will be removed at code cleaning
  if (C4::Context->preference('dontmerge') ){
  # save the file in localfile/modified_authorities
      my $cgidir = C4::Context->intranetdir ."/cgi-bin";
      unless (opendir(DIR,"$cgidir")) {
              $cgidir = C4::Context->intranetdir."/";
      }
  
      my $filename = $cgidir."/localfile/modified_authorities/$authid.authid";
      open AUTH, "> $filename";
      print AUTH $authid;
      close AUTH;
  } else {
#        &merge($authid,$record,$authid,$record);
  }
  return $authid;
}

=head2 GetAuthorityXML 

=over 4

$marcxml= &GetAuthorityXML( $authid)
returns xml form of record $authid

=back

=cut
sub GetAuthorityXML {
  # Returns MARC::XML of the authority passed in parameter.
  my ( $authid ) = @_;
  my $dbh=C4::Context->dbh;
  my $sth =
      $dbh->prepare("select marcxml from auth_header where authid=? "  );
  $sth->execute($authid);
  my ($marcxml)=$sth->fetchrow;
  return $marcxml;

}

=head2 GetAuthority 

=over 4

$record= &GetAuthority( $authid)
Returns MARC::Record of the authority passed in parameter.

=back

=cut
sub GetAuthority {
    my ($authid)=@_;
    my $dbh=C4::Context->dbh;
    my $sth=$dbh->prepare("select marcxml from auth_header where authid=?");
    $sth->execute($authid);
    my ($marcxml) = $sth->fetchrow;
    my $record=MARC::Record->new_from_xml($marcxml,'UTF-8',(C4::Context->preference("marcflavour") eq "UNIMARC"?"UNIMARCAUTH":C4::Context->preference("marcflavour")));
    $record->encoding('UTF-8');
    return ($record);
}

=head2 GetAuthType 

=over 4

$result= &GetAuthType( $authtypecode)
If $authtypecode is not "" then 
  Returns hashref to authtypecode information
else 
  returns ref to array of hashref information of all Authtypes

=back

=cut
sub GetAuthType {
    my ($authtypecode) = @_;
    my $dbh=C4::Context->dbh;
    my $sth;
    if ($authtypecode){
      $sth=$dbh->prepare("select * from auth_types where authtypecode=?");
      $sth->execute($authtypecode);
    } else {
      $sth=$dbh->prepare("select * from auth_types");
      $sth->execute;
    }
    my $res=$sth->fetchall_arrayref({});
    if (scalar(@$res)==1){
      return $res->[0];
    } else {
      return $res;
    }
}


sub AUTHhtml2marc {
    my ($rtags,$rsubfields,$rvalues,%indicators) = @_;
    my $dbh=C4::Context->dbh;
    my $prevtag = -1;
    my $record = MARC::Record->new();
#---- TODO : the leader is missing

#     my %subfieldlist=();
    my $prevvalue; # if tag <10
    my $field; # if tag >=10
    for (my $i=0; $i< @$rtags; $i++) {
        # rebuild MARC::Record
        if (@$rtags[$i] ne $prevtag) {
            if ($prevtag < 10) {
                if ($prevvalue) {
                    $record->add_fields((sprintf "%03s",$prevtag),$prevvalue);
                }
            } else {
                if ($field) {
                    $record->add_fields($field);
                }
            }
            $indicators{@$rtags[$i]}.='  ';
            if (@$rtags[$i] <10) {
                $prevvalue= @$rvalues[$i];
                undef $field;
            } else {
                undef $prevvalue;
                $field = MARC::Field->new( (sprintf "%03s",@$rtags[$i]), substr($indicators{@$rtags[$i]},0,1),substr($indicators{@$rtags[$i]},1,1), @$rsubfields[$i] => @$rvalues[$i]);
            }
            $prevtag = @$rtags[$i];
        } else {
            if (@$rtags[$i] <10) {
                $prevvalue=@$rvalues[$i];
            } else {
                if (length(@$rvalues[$i])>0) {
                    $field->add_subfields(@$rsubfields[$i] => @$rvalues[$i]);
                }
            }
            $prevtag= @$rtags[$i];
        }
    }
    # the last has not been included inside the loop... do it now !
    $record->add_fields($field) if $field;
    return $record;
}

=head2 FindDuplicateAuthority

=over 4

$record= &FindDuplicateAuthority( $record, $authtypecode)
return $authid,Summary if duplicate is found.

Comments : an improvement would be to return All the records that match.

=back

=cut

sub FindDuplicateAuthority {

    my ($record,$authtypecode)=@_;
#    warn "IN for ".$record->as_formatted;
    my $dbh = C4::Context->dbh;
#    warn "".$record->as_formatted;
    my $sth = $dbh->prepare("select auth_tag_to_report from auth_types where authtypecode=?");
    $sth->execute($authtypecode);
    my ($auth_tag_to_report) = $sth->fetchrow;
    $sth->finish;
#     warn "record :".$record->as_formatted."  auth_tag_to_report :$auth_tag_to_report";
    # build a request for SearchAuthorities
    my $query='at='.$authtypecode.' ';
    map {$query.= " and he=\"".$_->[1]."\"" if ($_->[0]=~/[A-z]/)}  $record->field($auth_tag_to_report)->subfields() if $record->field($auth_tag_to_report);
    my ($error,$results)=SimpleSearch($query,"authorityserver");
    # there is at least 1 result => return the 1st one
    if (@$results>0) {
      my $marcrecord = MARC::File::USMARC::decode($results->[0]);
      return $marcrecord->field('001')->data,BuildSummary($marcrecord,$marcrecord->field('001')->data,$authtypecode);
    }
    # no result, returns nothing
    return;
}

=head2 BuildSummary

=over 4

$text= &BuildSummary( $record, $authid, $authtypecode)
return HTML encoded Summary

Comment : authtypecode can be infered from both record and authid.
Moreover, authid can also be inferred from $record.
Would it be interesting to delete those things.

=back

=cut

sub BuildSummary{
## give this a Marc record to return summary
  my ($record,$authid,$authtypecode)=@_;
  my $dbh=C4::Context->dbh;
  my $authref = GetAuthType($authtypecode);
  my $summary = $authref->{summary};
  my %language;
  $language{'fre'}="Français";
  $language{'eng'}="Anglais";
  $language{'ger'}="Allemand";
  $language{'ita'}="Italien";
  $language{'spa'}="Espagnol";
  my %thesaurus;
  $thesaurus{'1'}="Peuples";
  $thesaurus{'2'}="Anthroponymes";
  $thesaurus{'3'}="Oeuvres";
  $thesaurus{'4'}="Chronologie";
  $thesaurus{'5'}="Lieux";
  $thesaurus{'6'}="Sujets";
  #thesaurus a remplir
  my @fields = $record->fields();
  my $reported_tag;
  # if the library has a summary defined, use it. Otherwise, build a standard one
  if ($summary) {
    my @fields = $record->fields();
    #             $reported_tag = '$9'.$result[$counter];
    foreach my $field (@fields) {
      my $tag = $field->tag();
      my $tagvalue = $field->as_string();
      $summary =~ s/\[(.?.?.?.?)$tag\*(.*?)]/$1$tagvalue$2\[$1$tag$2]/g;
      if ($tag<10) {
        if ($tag eq '001') {
          $reported_tag.='$3'.$field->data();
        }
      } else {
        my @subf = $field->subfields;
        for my $i (0..$#subf) {
          my $subfieldcode = $subf[$i][0];
          my $subfieldvalue = $subf[$i][1];
          my $tagsubf = $tag.$subfieldcode;
          $summary =~ s/\[(.?.?.?.?)$tagsubf(.*?)]/$1$subfieldvalue$2\[$1$tagsubf$2]/g;
        }
      }
    }
    $summary =~ s/\[(.*?)]//g;
    $summary =~ s/\n/<br>/g;
  } else {
    my $heading; 
    my $authid; 
    my $altheading;
    my $seealso;
    my $broaderterms;
    my $narrowerterms;
    my $see;
    my $seeheading;
        my $notes;
    my @fields = $record->fields();
    if (C4::Context->preference('marcflavour') eq 'UNIMARC') {
    # construct UNIMARC summary, that is quite different from MARC21 one
      # accepted form
      foreach my $field ($record->field('2..')) {
        $heading.= $field->subfield('a');
                $authid=$field->subfield('3');
      }
      # rejected form(s)
      foreach my $field ($record->field('3..')) {
        $notes.= '<span class="note">'.$field->subfield('a')."</span>\n";
      }
      foreach my $field ($record->field('4..')) {
        my $thesaurus = "thes. : ".$thesaurus{"$field->subfield('2')"}." : " if ($field->subfield('2'));
        $see.= '<span class="UF">'.$thesaurus.$field->subfield('a')."</span> -- \n";
      }
      # see :
      foreach my $field ($record->field('5..')) {
            
        if (($field->subfield('5')) && ($field->subfield('a')) && ($field->subfield('5') eq 'g')) {
          $broaderterms.= '<span class="BT"> <a href="detail.pl?authid='.$field->subfield('3').'">'.$field->subfield('a')."</a></span> -- \n";
        } elsif (($field->subfield('5')) && ($field->subfield('a')) && ($field->subfield('5') eq 'h')){
          $narrowerterms.= '<span class="NT"><a href="detail.pl?authid='.$field->subfield('3').'">'.$field->subfield('a')."</a></span> -- \n";
        } elsif ($field->subfield('a')) {
          $seealso.= '<span class="RT"><a href="detail.pl?authid='.$field->subfield('3').'">'.$field->subfield('a')."</a></span> -- \n";
        }
      }
      # // form
      foreach my $field ($record->field('7..')) {
        my $lang = substr($field->subfield('8'),3,3);
        $seeheading.= '<span class="langue"> En '.$language{$lang}.' : </span><span class="OT"> '.$field->subfield('a')."</span><br />\n";  
      }
            $broaderterms =~s/-- \n$//;
            $narrowerterms =~s/-- \n$//;
            $seealso =~s/-- \n$//;
            $see =~s/-- \n$//;
      $summary = "<b><a href=\"detail.pl?authid=$authid\">".$heading."</a></b><br />".($notes?"$notes <br />":"");
      $summary.= '<p><div class="label">TG : '.$broaderterms.'</div></p>' if ($broaderterms);
      $summary.= '<p><div class="label">TS : '.$narrowerterms.'</div></p>' if ($narrowerterms);
      $summary.= '<p><div class="label">TA : '.$seealso.'</div></p>' if ($seealso);
      $summary.= '<p><div class="label">EP : '.$see.'</div></p>' if ($see);
      $summary.= '<p><div class="label">'.$seeheading.'</div></p>' if ($seeheading);
      } else {
      # construct MARC21 summary
          foreach my $field ($record->field('1..')) {
              if ($record->field('100')) {
                  $heading.= $field->as_string('abcdefghjklmnopqrstvxyz68');
              } elsif ($record->field('110')) {
                                      $heading.= $field->as_string('abcdefghklmnoprstvxyz68');
              } elsif ($record->field('111')) {
                                      $heading.= $field->as_string('acdefghklnpqstvxyz68');
              } elsif ($record->field('130')) {
                                      $heading.= $field->as_string('adfghklmnoprstvxyz68');
              } elsif ($record->field('148')) {
                                      $heading.= $field->as_string('abvxyz68');
              } elsif ($record->field('150')) {
          #    $heading.= $field->as_string('abvxyz68');
          $heading.= $field->as_formatted();
              my $tag=$field->tag();
              $heading=~s /^$tag//g;
              $heading =~s /\_/\$/g;
              } elsif ($record->field('151')) {
                                      $heading.= $field->as_string('avxyz68');
              } elsif ($record->field('155')) {
                                      $heading.= $field->as_string('abvxyz68');
              } elsif ($record->field('180')) {
                                      $heading.= $field->as_string('vxyz68');
              } elsif ($record->field('181')) {
                                      $heading.= $field->as_string('vxyz68');
              } elsif ($record->field('182')) {
                                      $heading.= $field->as_string('vxyz68');
              } elsif ($record->field('185')) {
                                      $heading.= $field->as_string('vxyz68');
              } else {
                  $heading.= $field->as_string();
              }
          } #See From
          foreach my $field ($record->field('4..')) {
              $seeheading.= "&nbsp;&nbsp;&nbsp;".$field->as_string()."<br />";
              $seeheading.= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<i>see:</i> ".$seeheading."<br />";
          } #See Also
          foreach my $field ($record->field('5..')) {
              $altheading.= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<i>see also:</i> ".$field->as_string()."<br />";
              $altheading.= "&nbsp;&nbsp;&nbsp;".$field->as_string()."<br />";
              $altheading.= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<i>see also:</i> ".$altheading."<br />";
          }
          $summary.=$heading.$seeheading.$altheading;
      }
  }
  return $summary;
}

=head2 BuildUnimarcHierarchies

=over 4

$text= &BuildUnimarcHierarchies( $authid, $force)
return text containing trees for hierarchies
for them to be stored in auth_header

Example of text:
122,1314,2452;1324,2342,3,2452

=back

=cut
sub BuildUnimarcHierarchies{
  my $authid = shift @_;
#   warn "authid : $authid";
  my $force = shift @_;
  my @globalresult;
  my $dbh=C4::Context->dbh;
  my $hierarchies;
  my $data = GetHeaderAuthority($authid);
  if ($data->{'authtrees'} and not $force){
    return $data->{'authtrees'};
  } elsif ($data->{'authtrees'}){
    $hierarchies=$data->{'authtrees'};
  } else {
    my $record = GetAuthority($authid);
    my $found;
    foreach my $field ($record->field('550')){
      if ($field->subfield('5') && $field->subfield('5') eq 'g'){
        my $parentrecord = GetAuthority($field->subfield('3'));
        my $localresult=$hierarchies;
        my $trees;
        $trees = BuildUnimarcHierarchies($field->subfield('3'));
        my @trees;
        if ($trees=~/;/){
           @trees = split(/;/,$trees);
        } else {
           push @trees, $trees;
        }
        foreach (@trees){
          $_.= ",$authid";
        }
        @globalresult = (@globalresult,@trees);
        $found=1;
      }
      $hierarchies=join(";",@globalresult);
    }
    #Unless there is no ancestor, I am alone.
    $hierarchies="$authid" unless ($hierarchies);
  }
  AddAuthorityTrees($authid,$hierarchies);
  return $hierarchies;
}

=head2 BuildUnimarcHierarchy

=over 4

$ref= &BuildUnimarcHierarchy( $record, $class,$authid)
return a hashref in order to display hierarchy for record and final Authid $authid

"loopparents"
"loopchildren"
"class"
"loopauthid"
"current_value"
"value"

"ifparents"  
"ifchildren" 
Those two latest ones should disappear soon.

=back

=cut
sub BuildUnimarcHierarchy{
  my $record = shift @_;
  my $class = shift @_;
  my $authid_constructed = shift @_;
  my $authid=$record->subfield('250','3');
  my %cell;
  my $parents=""; my $children="";
  my (@loopparents,@loopchildren);
  foreach my $field ($record->field('550')){
    if ($field->subfield('5') && $field->subfield('a')){
      if ($field->subfield('5') eq 'h'){
        push @loopchildren, { "childauthid"=>$field->subfield('3'),"childvalue"=>$field->subfield('a')};
      }elsif ($field->subfield('5') eq 'g'){
        push @loopparents, { "parentauthid"=>$field->subfield('3'),"parentvalue"=>$field->subfield('a')};
      }
          # brothers could get in there with an else
    }
  }
  $cell{"ifparents"}=1 if (scalar(@loopparents)>0);
  $cell{"ifchildren"}=1 if (scalar(@loopchildren)>0);
  $cell{"loopparents"}=\@loopparents if (scalar(@loopparents)>0);
  $cell{"loopchildren"}=\@loopchildren if (scalar(@loopchildren)>0);
  $cell{"class"}=$class;
  $cell{"loopauthid"}=$authid;
  $cell{"current_value"} =1 if $authid eq $authid_constructed;
  $cell{"value"}=$record->subfield('250',"a");
  return \%cell;
}

=head2 GetHeaderAuthority

=over 4

$ref= &GetHeaderAuthority( $authid)
return a hashref in order auth_header table data

=back

=cut
sub GetHeaderAuthority{
  my $authid = shift @_;
  my $sql= "SELECT * from auth_header WHERE authid = ?";
  my $dbh=C4::Context->dbh;
  my $rq= $dbh->prepare($sql);
  $rq->execute($authid);
  my $data= $rq->fetchrow_hashref;
  return $data;
}

=head2 AddAuthorityTrees

=over 4

$ref= &AddAuthorityTrees( $authid, $trees)
return success or failure

=back

=cut

sub AddAuthorityTrees{
  my $authid = shift @_;
  my $trees = shift @_;
  my $sql= "UPDATE IGNORE auth_header set authtrees=? WHERE authid = ?";
  my $dbh=C4::Context->dbh;
  my $rq= $dbh->prepare($sql);
  return $rq->execute($trees,$authid);
}

=head2 merge

=over 4

$ref= &merge(mergefrom,$MARCfrom,$mergeto,$MARCto)


Could add some feature : Migrating from a typecode to an other for instance.
Then we should add some new parameter : bibliotargettag, authtargettag

=back

=cut
sub merge {
    my ($mergefrom,$MARCfrom,$mergeto,$MARCto) = @_;
    my $dbh=C4::Context->dbh;
    my $authtypecodefrom = GetAuthTypeCode($mergefrom);
    my $authtypecodeto = GetAuthTypeCode($mergeto);
    # return if authority does not exist
    my @X = $MARCfrom->fields();
    return if $#X == -1;
    @X = $MARCto->fields();
    return if $#X == -1;
    # search the tag to report
    my $sth = $dbh->prepare("select auth_tag_to_report from auth_types where authtypecode=?");
    $sth->execute($authtypecodefrom);
    my ($auth_tag_to_report) = $sth->fetchrow;
    
    my @record_to;
    @record_to = $MARCto->field($auth_tag_to_report)->subfields() if $MARCto->field($auth_tag_to_report);
    my @record_from;
    @record_from = $MARCfrom->field($auth_tag_to_report)->subfields() if $MARCfrom->field($auth_tag_to_report);
    
    # search all biblio tags using this authority.
    $sth = $dbh->prepare("select distinct tagfield from marc_subfield_structure where authtypecode=?");
    $sth->execute($authtypecodefrom);
    my @tags_using_authtype;
    while (my ($tagfield) = $sth->fetchrow) {
        push @tags_using_authtype,$tagfield."9" ;
    }

    if (C4::Context->preference('NoZebra')) {
        warn "MERGE TO DO";
    } else {
        # now, find every biblio using this authority
        my $oConnection=C4::Context->Zconn("biblioserver");
        my $query;
        $query= "an= ".$mergefrom;
        my $oResult = $oConnection->search(new ZOOM::Query::CCL2RPN( $query, $oConnection ));
        my $count=$oResult->size() if  ($oResult);
        my @reccache;
        my $z=0;
        while ( $z<$count ) {
        my $rec;
                $rec=$oResult->record($z);
            my $marcdata = $rec->raw();
        push @reccache, $marcdata;
        $z++;
        }
        $oResult->destroy();
        foreach my $marc(@reccache){
            my $update;
            my $marcrecord;
            $marcrecord = MARC::File::USMARC::decode($marc);
            foreach my $tagfield (@tags_using_authtype){
            $tagfield=substr($tagfield,0,3);
            my @tags = $marcrecord->field($tagfield);
            foreach my $tag (@tags){
                my $tagsubs=$tag->subfield("9");
            #warn "$tagfield:$tagsubs:$mergefrom";
                if ($tagsubs== $mergefrom) {
                $tag->update("9" =>$mergeto);
                foreach my $subfield (@record_to) {
            #        warn "$subfield,$subfield->[0],$subfield->[1]";
                    $tag->update($subfield->[0] =>$subfield->[1]);
                }#for $subfield
                }
                $marcrecord->delete_field($tag);
                $marcrecord->add_fields($tag);
                $update=1;
            }#for each tag
            }#foreach tagfield
            my $oldbiblio = TransformMarcToKoha($dbh,$marcrecord,"") ;
            if ($update==1){
            &ModBiblio($marcrecord,$oldbiblio->{'biblionumber'},GetFrameworkCode($oldbiblio->{'biblionumber'})) ;
            }
            
        }#foreach $marc
    }
  # now, find every other authority linked with this authority
#   my $oConnection=C4::Context->Zconn("authorityserver");
#   my $query;
# # att 9210               Auth-Internal-authtype
# # att 9220               Auth-Internal-LN
# # ccl.properties to add for authorities
#   $query= "= ".$mergefrom;
#   my $oResult = $oConnection->search(new ZOOM::Query::CCL2RPN( $query, $oConnection ));
#   my $count=$oResult->size() if  ($oResult);
#   my @reccache;
#   my $z=0;
#   while ( $z<$count ) {
#   my $rec;
#           $rec=$oResult->record($z);
#       my $marcdata = $rec->raw();
#   push @reccache, $marcdata;
#   $z++;
#   }
#   $oResult->destroy();
#   foreach my $marc(@reccache){
#     my $update;
#     my $marcrecord;
#     $marcrecord = MARC::File::USMARC::decode($marc);
#     foreach my $tagfield (@tags_using_authtype){
#       $tagfield=substr($tagfield,0,3);
#       my @tags = $marcrecord->field($tagfield);
#       foreach my $tag (@tags){
#         my $tagsubs=$tag->subfield("9");
#     #warn "$tagfield:$tagsubs:$mergefrom";
#         if ($tagsubs== $mergefrom) {
#           $tag->update("9" =>$mergeto);
#           foreach my $subfield (@record_to) {
#     #        warn "$subfield,$subfield->[0],$subfield->[1]";
#             $tag->update($subfield->[0] =>$subfield->[1]);
#           }#for $subfield
#         }
#         $marcrecord->delete_field($tag);
#         $marcrecord->add_fields($tag);
#         $update=1;
#       }#for each tag
#     }#foreach tagfield
#     my $authoritynumber = TransformMarcToKoha($dbh,$marcrecord,"") ;
#     if ($update==1){
#       &ModAuthority($marcrecord,$authoritynumber,GetAuthTypeCode($authoritynumber)) ;
#     }
# 
#   }#foreach $marc
}#sub
END { }       # module clean-up code here (global destructor)

=back

=head1 AUTHOR

Koha Developement team <info@koha.org>

Paul POULAIN paul.poulain@free.fr

=cut

# $Id$
# $Log$
# Revision 1.50  2007/07/26 15:14:05  toins
# removing warn compilation.
#
# Revision 1.49  2007/07/16 15:45:28  hdl
# Adding Summary for UNIMARC authorities
#
# Revision 1.48  2007/06/25 15:01:45  tipaul
# bugfixes on unimarc 100 handling (the field used for encoding)
#
# Revision 1.47  2007/06/06 13:08:35  tipaul
# bugfixes (various), handling utf-8 without guessencoding (as suggested by joshua, fixing some zebra config files -for french but should be interesting for other languages-
#
# Revision 1.46  2007/05/10 14:45:15  tipaul
# Koha NoZebra :
# - support for authorities
# - some bugfixes in ordering and "CCL" parsing
# - support for authorities <=> biblios walking
#
# Seems I can do what I want now, so I consider its done, except for bugfixes that will be needed i m sure !
#
# Revision 1.45  2007/04/06 14:48:45  hdl
# Code Cleaning : AuthoritiesMARC.
#
# Revision 1.44  2007/04/05 12:17:55  btoumi
# add "sort by" with heading-entity in authorities search
#
# Revision 1.43  2007/03/30 11:59:16  tipaul
# some cleaning (minor, the main one will come later) : removing some unused subs
#
# Revision 1.42  2007/03/29 16:45:53  tipaul
# Code cleaning of Biblio.pm (continued)
#
# All subs have be cleaned :
# - removed useless
# - merged some
# - reordering Biblio.pm completly
# - using only naming conventions
#
# Seems to have broken nothing, but it still has to be heavily tested.
# Note that Biblio.pm is now much more efficient than previously & probably more reliable as well.
#
# Revision 1.41  2007/03/29 13:30:31  tipaul
# Code cleaning :
# == Biblio.pm cleaning (useless) ==
# * some sub declaration dropped
# * removed modbiblio sub
# * removed moditem sub
# * removed newitems. It was used only in finishrecieve. Replaced by a TransformKohaToMarc+AddItem, that is better.
# * removed MARCkoha2marcItem
# * removed MARCdelsubfield declaration
# * removed MARCkoha2marcBiblio
#
# == Biblio.pm cleaning (naming conventions) ==
# * MARCgettagslib renamed to GetMarcStructure
# * MARCgetitems renamed to GetMarcItem
# * MARCfind_frameworkcode renamed to GetFrameworkCode
# * MARCmarc2koha renamed to TransformMarcToKoha
# * MARChtml2marc renamed to TransformHtmlToMarc
# * MARChtml2xml renamed to TranformeHtmlToXml
# * zebraop renamed to ModZebra
#
# == MARC=OFF ==
# * removing MARC=OFF related scripts (in cataloguing directory)
# * removed checkitems (function related to MARC=off feature, that is completly broken in head. If someone want to reintroduce it, hard work coming...)
# * removed getitemsbybiblioitem (used only by MARC=OFF scripts, that is removed as well)
#
# Revision 1.40  2007/03/28 10:39:16  hdl
# removing $dbh as a parameter in AuthoritiesMarc functions
# And reporting all differences into the scripts taht relies on those functions.
#
# Revision 1.39  2007/03/16 01:25:08  kados
# Using my precrash CVS copy I did the following:
#
# cvs -z3 -d:ext:kados@cvs.savannah.nongnu.org:/sources/koha co -P koha
# find koha.precrash -type d -name "CVS" -exec rm -v {} \;
# cp -r koha.precrash/* koha/
# cd koha/
# cvs commit
#
# This should in theory put us right back where we were before the crash
#
# Revision 1.39  2007/03/12 22:16:31  kados
# chcking for field before calling subfields
#
# Revision 1.38  2007/03/09 14:31:47  tipaul
# rel_3_0 moved to HEAD
#
# Revision 1.28.2.17  2007/02/05 13:16:08  hdl
# Removing Link from AuthoritiesMARC summary (caused a problem owed to the API differences between opac and intranet)
# + removing $dbh in SearchAuthorities
# + adding links in templates on summaries to go to full view.
# (no more links in popup authorities. or should we add it ?)
#
# Revision 1.28.2.16  2007/02/02 18:07:42  hdl
# Sorting and searching for exact term now works.
#
# Revision 1.28.2.15  2007/01/24 10:17:47  hdl
# FindDuplicate Now works.
# Be AWARE that it needs a change ccl.properties.
#
# Revision 1.28.2.14  2007/01/10 14:40:11  hdl
# Adding Authorities tree.
#
# Revision 1.28.2.13  2007/01/09 15:18:09  hdl
# Adding an to ccl.properties to allow ccl search for authority-numbers.
# Fixing Some problems with the previous modification to allow pqf search to work for more than one page.
# Using search for an= for an authority-Number.
#
# Revision 1.28.2.12  2007/01/09 13:51:31  hdl
# Bug Fixing : CountUsage used *synchronous* connection where biblio used ****asynchronous**** one.
# First try to get it work.
#
# Revision 1.28.2.11  2007/01/05 14:37:26  btoumi
# bug fix : remove wrong field in sql syntaxe from auth_subfield_structure table
#
# Revision 1.28.2.10  2007/01/04 13:11:08  tipaul
# commenting 2 zconn destroy
#
# Revision 1.28.2.9  2006/12/22 15:09:53  toins
# removing C4::Database;
#
# Revision 1.28.2.8  2006/12/20 17:13:19  hdl
# modifying use of GILS into use of @attr 1=Koha-Auth-Number
#
# Revision 1.28.2.7  2006/12/18 16:45:38  tipaul
# FIXME upcased
#
# Revision 1.28.2.6  2006/12/07 16:45:43  toins
# removing warn compilation. (perl -wc)
#
# Revision 1.28.2.5  2006/12/06 14:19:59  hdl
# ABugFixing : Authority count  Management.
#
# Revision 1.28.2.4  2006/11/17 13:18:58  tipaul
# code cleaning : removing use of "bib", and replacing with "biblionumber"
#
# WARNING : I tried to do carefully, but there are probably some mistakes.
# So if you encounter a problem you didn't have before, look for this change !!!
# anyway, I urge everybody to use only "biblionumber", instead of "bib", "bi", "biblio" or anything else. will be easier to maintain !!!
#
# Revision 1.28.2.3  2006/11/17 11:17:30  tipaul
# code cleaning : removing use of "bib", and replacing with "biblionumber"
#
# WARNING : I tried to do carefully, but there are probably some mistakes.
# So if you encounter a problem you didn't have before, look for this change !!!
# anyway, I urge everybody to use only "biblionumber", instead of "bib", "bi", "biblio" or anything else. will be easier to maintain !!!
#
# Revision 1.28.2.2  2006/10/12 22:04:47  hdl
# Authorities working with zebra.
# zebra Configuration files are comitted next.
