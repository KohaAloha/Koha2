#!/usr/bin/perl
# Script to perform searching
# For documentation try 'perldoc /path/to/search'
#
# $Header$
#
# Copyright 2006 LibLime
#
# This file is part of Koha
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

=head1 NAME

search - a search script for finding records in a Koha system (Version 2.4)

=head1 OVERVIEW

This script contains a demonstration of a new search API for Koha 2.4. It is
designed to be simple to use and configure, yet capable of performing feats
like stemming, field weighting, relevance ranking, support for multiple 
query language formats (CCL, CQL, PQF), full or nearly full support for the
bib1 attribute set, extended attribute sets defined in Zebra profiles, access
to the full range of Z39.50 query options, federated searches on Z39.50
targets, etc.

I believe the API as represented in this script is mostly sound, even if the
individual functions in Search.pm and Koha.pm need to be cleaned up. Of course,
you are free to disagree :-)

I will attempt to describe what is happening at each part of this script.
-- JF

=head2 INTRO

This script performs two functions:

=over 

=item 1. interacts with Koha to retrieve and display the results of a search

=item 2. loads the advanced search page

=back

These two functions share many of the same variables and modules, so the first
task is to load what they have in common and determine which template to use.
Once determined, proceed to only load the variables and procedures necessary
for that function.

=head2 THE ADVANCED SEARCH PAGE

If we're loading the advanced search page this script will call a number of
display* routines which populate objects that are sent to the template for 
display of things like search indexes, languages, search limits, branches,
etc. These are not stored in the template for two reasons:

=over

=item 1. Efficiency - we have more control over objects inside the script, and it's possible to not duplicate things like indexes (if the search indexes were stored in the template they would need to be repeated)

=item 2. Customization - if these elements were moved to the sql database it would allow a simple librarian to determine which fields to display on the page without editing any html (also how the fields should behave when being searched).

=back

However, they create one problem : the strings aren't translated. I have an idea
for how to do this that I will purusue soon.

=head2 PERFORMING A SEARCH

If we're performing a search, this script  performs three primary
operations:

=over 

=item 1. builds query strings (yes, plural)

=item 2. perform the search and return the results array

=item 3. build the HTML for output to the template

=back

There are several additional secondary functions performed that I will
not cover in detail.

=head3 1. Building Query Strings
    
There are several types of queries needed in the process of search and retrieve:

=over

=item 1 Koha query - the query that is passed to Zebra

This is the most complex query that needs to be built.The original design goal was to use a custom CCL2PQF query parser to translate an incoming CCL query into a multi-leaf query to pass to Zebra. It needs to be multi-leaf to allow field weighting, koha-specific relevance ranking, and stemming. When I have a chance I'll try to flesh out this section to better explain.

This query incorporates query profiles that aren't compatible with non-Zebra Z39.50 targets to acomplish the field weighting and relevance ranking.

=item 2 Federated query - the query that is passed to other Z39.50 targets

This query is just the user's query expressed in CCL CQL, or PQF for passing to a non-zebra Z39.50 target (one that doesn't support the extended profile that Zebra does).

=item 3 Search description - passed to the template / saved for future refinements of the query (by user)

This is a simple string that completely expresses the query in a way that can be parsed by Koha for future refinements of the query or as a part of a history feature. It differs from the human search description in several ways:

1. it does not contain commas or = signs
2. 

=item 4 Human search description - what the user sees in the search_desc area

This is a simple string nearly identical to the Search description, but more human readable. It will contain = signs or commas, etc.

=back

=head3 2. Perform the Search

This section takes the query strings and performs searches on the named servers, including the Koha Zebra server, stores the results in a deeply nested object, builds 'faceted results', and returns these objects.

=head3 3. Build HTML

The final major section of this script takes the objects collected thusfar and builds the HTML for output to the template and user.

=head3 Additional Notes

Not yet completed...

=cut

use strict;            # always use

## STEP 1. Load things that are used in both search page and
# results page and decide which template to load, operations 
# to perform, etc.
## load Koha modules
use C4::Context;
use C4::Output;
use C4::Auth;
use C4::Search;
use C4::Languages; # getAllLanguages
use C4::Koha;
use POSIX qw(ceil floor);
use C4::Branch; # GetBranches
# create a new CGI object
# not sure undef_params option is working, need to test
use CGI qw('-no_undef_params');
my $cgi = new CGI;

my ($template,$borrowernumber,$cookie);

# decide which template to use
my $template_name;
my @params = $cgi->param("limit");
if ((@params>1) || ($cgi->param("q")) ) {
    $template_name = 'catalogue/results.tmpl';
}
else {
    $template_name = 'catalogue/advsearch.tmpl';
}

# load the template
($template, $borrowernumber, $cookie) = get_template_and_user({
    template_name => $template_name,
    query => $cgi,
    type => "intranet",
    authnotrequired => 0,
    flagsrequired   => { catalogue => 1 },
    }
);

=head1 BUGS and FIXMEs

There are many, most are documented in the code. The one that
isn't fully documented, but referred to is the need for a full
query parser.

=cut

## URI Re-Writing
# FIXME: URI re-writing should be tested more carefully and may better
# handled by mod_rewrite or something else. The code below almost works,
# but doesn't quite handle limits correctly when they are the only
# param passed -- I'll work on this soon -- JF
#my $rewrite_flag;
#my $uri = $cgi->url(-base => 1);
#my $relative_url = $cgi->url(-relative=>1);
#$uri.="/".$relative_url."?";
#warn "URI:$uri";
#my @cgi_params_list = $cgi->param();
#my $url_params = $cgi->Vars;

#for my $each_param_set (@cgi_params_list) {
#    $uri.= join "",  map "\&$each_param_set=".$_, split("\0",$url_params->{$each_param_set}) if $url_params->{$each_param_set};
#}
#warn "New URI:$uri";
# Only re-write a URI if there are params or if it already hasn't been re-written
#unless (($cgi->param('r')) || (!$cgi->param()) ) {
#    print $cgi->redirect(     -uri=>$uri."&r=1",
#                            -cookie => $cookie);
#    exit;
#}

# load the branches
my $branches = GetBranches();
my @branch_loop;
push @branch_loop, {value => "", branchname => "All Branches", };
for my $branch_hash (keys %$branches) {
    push @branch_loop, {value => "branch: $branch_hash", branchname => $branches->{$branch_hash}->{'branchname'}, };
}
$template->param(branchloop => \@branch_loop,);

# load the itemtypes (Called Collection Codes in the template -- used for circ rules )
my $itemtypes = GetItemTypes;
my @itemtypesloop;
my $selected=1;
my $cnt;
my $imgdir = getitemtypeimagesrc();
foreach my $thisitemtype ( sort {$itemtypes->{$a}->{'description'} cmp $itemtypes->{$b}->{'description'} } keys %$itemtypes ) {
    my %row =(  number=>$cnt++,
                imageurl=> $itemtypes->{$thisitemtype}->{'imageurl'}?($imgdir."/".$itemtypes->{$thisitemtype}->{'imageurl'}):"",
                code => $thisitemtype,
                selected => $selected,
                description => $itemtypes->{$thisitemtype}->{'description'},
                count5 => $cnt % 4,
            );
    $selected = 0 if ($selected) ;
    push @itemtypesloop, \%row;
}
$template->param(itemtypeloop => \@itemtypesloop);

# # load the itypes (Called item types in the template -- just authorized values for searching)
# my ($itypecount,@itype_loop) = GetCcodes();
# $template->param(itypeloop=>\@itype_loop,);

# load the languages ( for switching from one template to another )
# my @languages_options = displayLanguages($cgi);
# my $languages_count = @languages_options;
# if($languages_count > 1){
#         $template->param(languages => \@languages_options);
# }

# The following should only be loaded if we're bringing up the advanced search template
if ( $template_name eq "catalogue/advsearch.tmpl" ) {
    # load the servers (used for searching -- to do federated searching, etc.)
    my $primary_servers_loop;# = displayPrimaryServers();
    $template->param(outer_servers_loop =>  $primary_servers_loop,);
    
    my $secondary_servers_loop;# = displaySecondaryServers();
    $template->param(outer_sup_servers_loop => $secondary_servers_loop,);
    
    # load the limit types (icon-based limits in advanced search page)
    my $outer_limit_types_loop = displayLimitTypes();
    $template->param(outer_limit_types_loop =>  $outer_limit_types_loop,);
    
    # load the search indexes (what a user can choose to search by)
    my $indexes = displayIndexes();
    
    # determine what to display next to the search boxes (ie, boolean option
    # shouldn't appear on the first one, scan indexes should, adding a new
    # box should only appear on the last, etc.
    # FIXME: this stuff should be cleaned up a bit and the html should be turned
    # into flags for the template -- I'll work on that soon -- JF
    my @search_boxes_array;
    my $search_boxes_count = 1; # should be a syspref
    for (my $i=0;$i<=$search_boxes_count;$i++) {
        my $this_index =[@$indexes]; # clone the data, not just the reference
        #@$this_index[$i]->{selected} = "selected";
        if ($i==0) {
            push @search_boxes_array,
                {indexes => $this_index,
                search_boxes_label => 1,
                scan_index => 1,
                };
        
        }
        elsif ($i==$search_boxes_count) {
            push @search_boxes_array,
                {indexes => $indexes,
                add_field => "1",};
        }
        else {
            push @search_boxes_array,
                {indexes => $indexes,};
        }
    }
    $template->param(uc(C4::Context->preference("marcflavour")) => 1,
                      search_boxes_loop => \@search_boxes_array);

    # load the language limits (for search)
    my $languages_limit_loop = getAllLanguages();
    $template->param(search_languages_loop => $languages_limit_loop,);
    
    # load the subtype limits
    my $outer_subtype_limits_loop = displaySubtypesLimit();
    $template->param(outer_subtype_limits_loop => $outer_subtype_limits_loop,);
    
    my $expanded_options;
    if (not defined $cgi->param('expanded_options')){
        $expanded_options = C4::Context->preference("expandedSearchOption");
    }
    else {
        $expanded_options = $cgi->param('expanded_options');
    }
    $template->param(expanded_options => $expanded_options);

    # load the sort_by options for the template
    my $sort_by = $cgi->param('sort_by');
    my $sort_by_loop = displaySortby($sort_by);
    $template->param(sort_by_loop => $sort_by_loop);

    output_html_with_http_headers $cgi, $cookie, $template->output;
    exit;
}

### OK, if we're this far, we're performing an actual search

# Fetch the paramater list as a hash in scalar context:
#  * returns paramater list as tied hash ref
#  * we can edit the values by changing the key
#  * multivalued CGI paramaters are returned as a packaged string separated by "\0" (null)
my $params = $cgi->Vars;

# Params that can have more than one value
# sort by is used to sort the query
my @sort_by;
@sort_by = split("\0",$params->{'sort_by'}) if $params->{'sort_by'};
# load the sort_by options for the template
my $sort_by = $params->{'sort_by'};
my $sort_by_loop = displaySortby($sort_by);
$template->param(sort_by_loop => $sort_by_loop);
#
# Use the servers defined, or just search our local catalog(default)
my @servers;
@servers = split("\0",$params->{'server'}) if $params->{'server'};
unless (@servers) {
    #FIXME: this should be handled using Context.pm
    @servers = ("biblioserver");
    # @servers = C4::Context->config("biblioserver");
}

# operators include boolean and proximity operators and are used
# to evaluate multiple operands
my @operators;
@operators = split("\0",$params->{'op'}) if $params->{'op'};

# indexes are query qualifiers, like 'title', 'author', etc. They
# can be simple or complex
my @indexes;
@indexes = split("\0",$params->{'idx'}) if $params->{'idx'};

# an operand can be a single term, a phrase, or a complete ccl query
my @operands;
@operands = split("\0",$params->{'q'}) if $params->{'q'};

# limits are use to limit to results to a pre-defined category such as branch or language
my @limits;
@limits = split("\0",$params->{'limit'}) if $params->{'limit'};

my $available;
foreach my $limit(@limits) {
    if ($limit =~/available/) {
        $available = 1;
    }
}
$template->param(available => $available);
push @limits, map "yr:".$_, split("\0",$params->{'limit-yr'}) if $params->{'limit-yr'};

# Params that can only have one value
my $query = $params->{'q'};
my $scan = $params->{'scan'};
my $results_per_page = $params->{'count'} || 20;
my $offset = $params->{'offset'} || 0;
my $hits;
my $expanded_facet = $params->{'expand'};

# Define some global variables
my $error; # used for error handling
my $search_desc; # the query expressed in terms that humans understand
my $koha_query; # the query expressed in terms that zoom understands with field weighting and stemming
my $federated_query;
my $query_type; # usually not needed, but can be used to trigger ccl, cql, or pqf queries if set
my @results;
## I. BUILD THE QUERY
($error,$search_desc,$koha_query,$federated_query,$query_type) = buildQuery($query,\@operators,\@operands,\@indexes,\@limits);

## II. DO THE SEARCH AND GET THE RESULTS
my $total; # the total results for the whole set
my $facets; # this object stores the faceted results that display on the left-hand of the results page
my @results_array;
my $results_hashref;

if (C4::Context->preference('NoZebra')) {
    eval {
        ($error, $results_hashref, $facets) = NZgetRecords($koha_query,$federated_query,\@sort_by,\@servers,$results_per_page,$offset,$expanded_facet,$branches,$query_type,$scan);
    };
} else {
    eval {
        ($error, $results_hashref, $facets) = getRecords($koha_query,$federated_query,\@sort_by,\@servers,$results_per_page,$offset,$expanded_facet,$branches,$query_type,$scan);
    };
}
if ($@ || $error) {
    $template->param(query_error => $error.$@);

    output_html_with_http_headers $cgi, $cookie, $template->output;
    exit;
}
my $op=$cgi->param("operation");
if ($op eq "bulkedit"){
        my ($countchanged,$listunchanged)=
          EditBiblios($results_hashref->{'biblioserver'}->{"RECORDS"},
                      $params->{"tagsubfield"},
                      $params->{"inputvalue"},
                      $params->{"targetvalue"},
                      $params->{"test"}
                      );
        $template->param(bulkeditresults=>1,
                      tagsubfield=>$params->{"tagsubfield"},
                      inputvalue=>$params->{"inputvalue"},
                      targetvalue=>$params->{"targetvalue"},
                      countchanged=>$countchanged,
                      countunchanged=>scalar(@$listunchanged),
                      listunchanged=>$listunchanged);
}

if (C4::Context->userenv->{'flags'}==1 ||(C4::Context->userenv->{'flags'} & ( 2**9 ) )){
#Edit Catalogue Permissions
  $template->param(bulkedit => 1);
  $template->param(tagsubfields=>GetManagedTagSubfields());
}
# At this point, each server has given us a result set
# now we build that set for template display
my @sup_results_array;
for (my $i=0;$i<=@servers;$i++) {
    my $server = $servers[$i];
    if ($server =~/biblioserver/) { # this is the local bibliographic server
        $hits = $results_hashref->{$server}->{"hits"};
        my @newresults = searchResults( $search_desc,$hits,$results_per_page,$offset,@{$results_hashref->{$server}->{"RECORDS"}});
        $total = $total + $results_hashref->{$server}->{"hits"};
        if ($hits) {
            $template->param(total => $hits);
            $template->param(searchdesc => ($query_type?"$query_type=":"")."$search_desc" );
            $template->param(results_per_page =>  $results_per_page);
            $template->param(SEARCH_RESULTS => \@newresults);

            my @page_numbers;
            my $pages = ceil($hits / $results_per_page);
            my $current_page_number = 1;
            $current_page_number = ($offset / $results_per_page + 1) if $offset;
            my $previous_page_offset = $offset - $results_per_page unless ($offset - $results_per_page <0);
            my $next_page_offset = $offset + $results_per_page;
            for (my $j=1; $j<=$pages;$j++) {
                my $this_offset = (($j*$results_per_page)-$results_per_page);
                my $this_page_number = $j;
                my $highlight = 1 if ($this_page_number == $current_page_number);
                if ($this_page_number <= $pages) {
                push @page_numbers, { offset => $this_offset, pg => $this_page_number, highlight => $highlight, sort_by => join " ",@sort_by };
                }
            }
            $template->param(PAGE_NUMBERS => \@page_numbers,
                            previous_page_offset => $previous_page_offset,
                            next_page_offset => $next_page_offset) unless $pages < 2;
        }
    } # end of the if local
    else {
        # check if it's a z3950 or opensearch source
        my $zed3950 = 0;  # FIXME :: Hardcoded value.
        if ($zed3950) {
            my @inner_sup_results_array;
            for my $sup_record ( @{$results_hashref->{$server}->{"RECORDS"}} ) {
                my $marc_record_object = MARC::Record->new_from_usmarc($sup_record);
                my $control_number = $marc_record_object->field('010')->subfield('a') if $marc_record_object->field('010');
                $control_number =~ s/^ //g;
                my $link = "http://catalog.loc.gov/cgi-bin/Pwebrecon.cgi?SAB1=".$control_number."&BOOL1=all+of+these&FLD1=LC+Control+Number+LCCN+%28K010%29+%28K010%29&GRP1=AND+with+next+set&SAB2=&BOOL2=all+of+these&FLD2=Keyword+Anywhere+%28GKEY%29+%28GKEY%29&PID=6211&SEQ=20060816121838&CNT=25&HIST=1";
                my $title = $marc_record_object->title();
                push @inner_sup_results_array, {
                    'title' => $title,
                    'link' => $link,
                };
            }
            my $servername = $server;
            push @sup_results_array, { servername => $servername, inner_sup_results_loop => \@inner_sup_results_array};
            $template->param(outer_sup_results_loop => \@sup_results_array);
        }
    }

} #/end of the for loop
#$template->param(FEDERATED_RESULTS => \@results_array);


$template->param(
            #classlist => $classlist,
            total => $total,
            searchdesc => ($query_type?"$query_type=":"")."$search_desc",
            opacfacets => 1,
            facets_loop => $facets,
            suggestion => C4::Context->preference("suggestion"),
            virtualshelves => C4::Context->preference("virtualshelves"),
            LibraryName => C4::Context->preference("LibraryName"),
            OpacNav => C4::Context->preference("OpacNav"),
            opaccredits => C4::Context->preference("opaccredits"),
            AmazonContent => C4::Context->preference("AmazonContent"),
            opacsmallimage => C4::Context->preference("opacsmallimage"),
            opaclayoutstylesheet => C4::Context->preference("opaclayoutstylesheet"),
            opaccolorstylesheet => C4::Context->preference("opaccolorstylesheet"),
            "BiblioDefaultView".C4::Context->preference("BiblioDefaultView") => 1,
            scan_use => $scan,
            search_error => $error,
);
## Now let's find out if we have any supplemental data to show the user
#  and in the meantime, save the current query for statistical purposes, etc.
my $koha_spsuggest; # a flag to tell if we've got suggestions coming from Koha
my @koha_spsuggest; # place we store the suggestions to be returned to the template as LOOP
my $phrases = $search_desc;
my $ipaddress;

if ( C4::Context->preference("kohaspsuggest") ) {
        eval {
            my $koha_spsuggest_dbh;
            # FIXME: this needs to be moved to Context.pm
            eval {
                $koha_spsuggest_dbh=DBI->connect("DBI:mysql:suggest:66.213.78.76","auth","Free2cirC");
            };
            if ($@) { 
                warn "can't connect to spsuggest db";
            }
            else {
                my $koha_spsuggest_insert = "INSERT INTO phrase_log(phr_phrase,phr_resultcount,phr_ip) VALUES(?,?,?)";
                my $koha_spsuggest_query = "SELECT display FROM distincts WHERE strcmp(soundex(suggestion), soundex(?)) = 0 order by soundex(suggestion) limit 0,5";
                my $koha_spsuggest_sth = $koha_spsuggest_dbh->prepare($koha_spsuggest_query);
                $koha_spsuggest_sth->execute($phrases);
                while (my $spsuggestion = $koha_spsuggest_sth->fetchrow_array) {
                    $spsuggestion =~ s/(:|\/)//g;
                    my %line;
                    $line{spsuggestion} = $spsuggestion;
                    push @koha_spsuggest,\%line;
                    $koha_spsuggest = 1;
                }

                # Now save the current query
                $koha_spsuggest_sth=$koha_spsuggest_dbh->prepare($koha_spsuggest_insert);
                #$koha_spsuggest_sth->execute($phrases,$results_per_page,$ipaddress);
                $koha_spsuggest_sth->finish;

                $template->param( koha_spsuggest => $koha_spsuggest ) unless $hits;
                $template->param( SPELL_SUGGEST => \@koha_spsuggest,
                );
            }
    };
    if ($@) {
            warn "Kohaspsuggest failure:".$@;
    }
}

# VI. BUILD THE TEMPLATE
output_html_with_http_headers $cgi, $cookie, $template->output;
