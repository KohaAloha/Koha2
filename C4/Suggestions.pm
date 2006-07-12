package C4::Suggestions;

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

# $Id$

use strict;
require Exporter;
use DBI;
use C4::Context;
use C4::Output;
use Mail::Sendmail;
use vars qw($VERSION @ISA @EXPORT);

# set the version for version checking
$VERSION = do { my @v = '$Revision$' =~ /\d+/g;
  shift(@v) . "." . join("_", map {sprintf "%03d", $_ } @v); };

=head1 NAME

C4::Suggestions - Some useful functions for dealings with suggestions.

=head1 SYNOPSIS

use C4::Suggestions;

=head1 DESCRIPTION

=over 4

The functions in this module deal with the suggestions in OPAC and in librarian interface

A suggestion is done in the OPAC. It has the status "ASKED"

When a librarian manages the suggestion, he can set the status to "REJECTED" or "ACCEPTED".

When the book is ordered, the suggestion status becomes "ORDERED"

When a book is ordered and arrived in the library, the status becomes "AVAILABLE"

All suggestions of a borrower can be seen by the borrower itself.
Suggestions done by other borrowers can be seen when not "AVAILABLE"

=back

=head1 FUNCTIONS

=cut

@ISA = qw(Exporter);
@EXPORT = qw(
    &NewSuggestion
    &SearchSuggestion
    &GetSuggestion
    &DelSuggestion
    &CountSuggestion
    &ModStatus
    &ConnectSuggestionAndBiblio
    &GetSuggestionFromBiblionumber
 );

=head2 SearchSuggestion

=over 4

(\@array) = &SearchSuggestion($user,$author,$title,$publishercode,$status,$suggestedbyme)

searches for a suggestion

return :
C<\@array> : the suggestions found. Array of hash.
Note the status is stored twice :
* in the status field
* as parameter ( for example ASKED => 1, or REJECTED => 1) . This is for template & translation purposes.

=back

=cut

sub SearchSuggestion  {
    my ($user,$author,$title,$publishercode,$status,$suggestedbyme)=@_;
    my $dbh = C4::Context->dbh;
    my $query = qq|
    SELECT suggestions.*,
        U1.surname   AS surnamesuggestedby,
        U1.firstname AS firstnamesuggestedby,
        U2.surname   AS surnamemanagedby,
        U2.firstname AS firstnamemanagedby
    FROM suggestions
    LEFT JOIN borrowers AS U1 ON suggestedby=U1.borrowernumber
    LEFT JOIN borrowers AS U2 ON managedby=U2.borrowernumber
    WHERE 1=1 |;

    my @sql_params;
    if ($author) {
       push @sql_params,"%".$author."%";
       $query .= " and author like ?";
    }
    if ($title) {
        push @sql_params,"%".$title."%";
        $query .= " and suggestions.title like ?";
    }
    if ($publishercode) {
        push @sql_params,"%".$publishercode."%";
        $query .= " and publishercode like ?";
    }
    if ($status) {
        push @sql_params,$status;
        $query .= " and status=?";
    }

    if (C4::Context->preference("IndependantBranches")) {
        my $userenv = C4::Context->userenv;
        if ($userenv) {
            unless ($userenv->{flags} == 1){
                push @sql_params,$userenv->{branch};
                $query .= " and (U1.branchcode = ? or U1.branchcode ='')";
            }
        }
    }
    if ($suggestedbyme) {
        unless ($suggestedbyme eq -1) {
            push @sql_params,$user;
            $query .= " and suggestedby=?";
        }
    } else {
        $query .= " and managedby is NULL";
    }
    my $sth=$dbh->prepare($query);
    $sth->execute(@sql_params);
    my @results;
    my $even=1; # the even variable is used to set even / odd lines, for highlighting
    while (my $data=$sth->fetchrow_hashref){
        $data->{$data->{STATUS}} = 1;
        if ($even) {
            $even=0;
            $data->{even}=1;
        } else {
            $even=1;
        }
        push(@results,$data);
    }
    return (\@results);
}

=head2 GetSuggestion

=over 4

\%sth = &GetSuggestion($suggestionid)

this function get the detail of the suggestion $suggestionid (input arg)

return :
    the result of the SQL query as a hash : $sth->fetchrow_hashref.

=back

=cut
sub GetSuggestion {
    my ($suggestionid) = @_;
    my $dbh = C4::Context->dbh;
    my $query = qq|
        SELECT *
        FROM   suggestions
        WHERE  suggestionid=?
    |;
    my $sth = $dbh->prepare($query);
    $sth->execute($suggestionid);
    return($sth->fetchrow_hashref);
}

=head2 GetSuggestionFromBiblionumber

=over 4

$suggestionid = &GetSuggestionFromBiblionumber($dbh,$biblionumber)

Get a suggestion from it's biblionumber.

return :
the id of the suggestion which is related to the biblionumber given on input args.

=back

=cut
sub GetSuggestionFromBiblionumber {
    my ($dbh,$biblionumber) = @_;
    my $query = qq|
        SELECT suggestionid
        FROM   suggestions
        WHERE  biblionumber=?
    |;
    my $sth = $dbh->prepare($query);
    $sth->execute($biblionumber);
    my ($suggestionid) = $sth->fetchrow;
    return $suggestionid;
}


=head2 CountSuggestion

=over 4

&CountSuggestion($status)

Count the number of suggestions with the status given on input argument.
the arg status can be :

=over

=over

=item * ASKED : asked by the user, not dealed by the librarian

=item * ACCEPTED : accepted by the librarian, but not yet ordered

=item * REJECTED : rejected by the librarian (definitive status)

=item * ORDERED : ordered by the librarian (acquisition module)

=back

=back

return :
the number of suggestion with this status.

=back

=cut
sub CountSuggestion {
    my ($status) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;
    if (C4::Context->preference("IndependantBranches")){
        my $userenv = C4::Context->userenv;
        if ($userenv->{flags} == 1){
            my $query = qq |
                SELECT count(*)
                FROM   suggestions
                WHERE  status=?
            |;
            $sth = $dbh->prepare($query);
            $sth->execute($status);
        }
        else {
            my $query = qq |
                SELECT count(*)
                FROM suggestions,borrowers
                WHERE status=?
                AND borrowers.borrowernumber=suggestions.suggestedby
                AND (borrowers.branchcode='' OR borrowers.branchcode =?)
            |;
            $sth = $dbh->prepare($query);
            $sth->execute($status,$userenv->{branch});
        }
    }
    else {
        my $query = qq |
            SELECT count(*)
            FROM suggestions
            WHERE status=?
        |;
         $sth = $dbh->prepare($query);
        $sth->execute($status);
    }
    my ($result) = $sth->fetchrow;
    return $result;
}

=head2 NewSuggestion


=over 4

&NewSuggestion($borrowernumber,$title,$author,$publishercode,$note,$copyrightdate,$volumedesc,$publicationyear,$place,$isbn,$biblionumber)

Insert a new suggestion on database with value given on input arg.

=back

=cut
sub NewSuggestion {
    my ($borrowernumber,$title,$author,$publishercode,$note,$copyrightdate,$volumedesc,$publicationyear,$place,$isbn,$biblionumber) = @_;
    my $dbh = C4::Context->dbh;
    my $query = qq |
        INSERT INTO suggestions
            (status,suggestedby,title,author,publishercode,note,copyrightdate,
            volumedesc,publicationyear,place,isbn,biblionumber)
        VALUES ('ASKED',?,?,?,?,?,?,?,?,?,?,?)
    |;
    my $sth = $dbh->prepare($query);
    $sth->execute($borrowernumber,$title,$author,$publishercode,$note,$copyrightdate,$volumedesc,$publicationyear,$place,$isbn,$biblionumber);
}

=head2 ModStatus

=over 4

&ModStatus($suggestionid,$status,$managedby,$biblionumber)

Modify the status (status can be 'ASKED', 'ACCEPTED', 'REJECTED', 'ORDERED')
and send a mail to notify the user that did the suggestion.

Note that there is no function to modify a suggestion : only the status can be modified, thus the name of the function.

=back

=cut
sub ModStatus {
    my ($suggestionid,$status,$managedby,$biblionumber) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;
    if ($managedby>0) {
        if ($biblionumber) {
        my $query = qq|
            UPDATE suggestions
            SET    status=?,managedby=?,biblionumber=?
            WHERE  suggestionid=?
        |;
        $sth = $dbh->prepare($query);
        $sth->execute($status,$managedby,$biblionumber,$suggestionid);
        } else {
            my $query = qq|
                UPDATE suggestions
                SET    status=?,managedby=?
                WHERE  suggestionid=?
            |;
            $sth = $dbh->prepare($query);
            $sth->execute($status,$managedby,$suggestionid);
        }
   } else {
        if ($biblionumber) {
            my $query = qq|
                UPDATE suggestions
                SET    status=?,biblionumber=?
                WHERE  suggestionid=?
            |;
            $sth = $dbh->prepare($query);
            $sth->execute($status,$biblionumber,$suggestionid);
        }
        else {
            my $query = qq|
                UPDATE suggestions
                SET    status=?
                WHERE  suggestionid=?
            |;
            $sth = $dbh->prepare($query);
            $sth->execute($status,$suggestionid);
        }
    }
    # check mail sending.
    my $queryMail = qq|
        SELECT suggestions.*,
            boby.surname AS bysurname,
            boby.firstname AS byfirstname,
            boby.emailaddress AS byemail,
            lib.surname AS libsurname,
            lib.firstname AS libfirstname,
            lib.emailaddress AS libemail
        FROM suggestions
            LEFT JOIN borrowers AS boby ON boby.borrowernumber=suggestedby
            LEFT JOIN borrowers AS lib ON lib.borrowernumber=managedby
        WHERE suggestionid=?
    |;
    $sth = $dbh->prepare($queryMail);
    $sth->execute($suggestionid);
    my $emailinfo = $sth->fetchrow_hashref;
    my $template = gettemplate("suggestion/mail_suggestion_$status.tmpl","intranet");

    $template->param(
        byemail => $emailinfo->{byemail},
        libemail => $emailinfo->{libemail},
        status => $emailinfo->{status},
        title => $emailinfo->{title},
        author =>$emailinfo->{author},
        libsurname => $emailinfo->{libsurname},
        libfirstname => $emailinfo->{libfirstname},
        byfirstname => $emailinfo->{byfirstname},
        bysurname => $emailinfo->{bysurname},
    );
    my %mail = (
        To => $emailinfo->{byemail},
        From => $emailinfo->{libemail},
        Subject => 'Koha suggestion',
        Message => "".$template->output
    );
    sendmail(%mail);
}

=head2 ConnectSuggestionAndBiblio

=over 4
&ConnectSuggestionAndBiblio($suggestionid,$biblionumber)

connect a suggestion to an existing biblio

=back

=cut
sub ConnectSuggestionAndBiblio {
    my ($suggestionid,$biblionumber) = @_;
    my $dbh=C4::Context->dbh;
    my $query = qq |
        UPDATE suggestions
        SET    biblionumber=?
        WHERE  suggestionid=?
    |;
    my $sth = $dbh->prepare($query);
    $sth->execute($biblionumber,$suggestionid);
}

=head2 DelSuggestion

=over 4

&DelSuggestion($borrowernumber,$suggestionid)

Delete a suggestion. A borrower can delete a suggestion only if he is its owner.

=back

=cut

sub DelSuggestion {
    my ($borrowernumber,$suggestionid) = @_;
    my $dbh = C4::Context->dbh;
    # check that the suggestion comes from the suggestor
    my $query = qq |
        SELECT suggestedby
        FROM   suggestions
        WHERE  suggestionid=?
    |;
    my $sth = $dbh->prepare($query);
    $sth->execute($suggestionid);
    my ($suggestedby) = $sth->fetchrow;
    if ($suggestedby eq $borrowernumber) {
        my $queryDelete = qq|
            DELETE FROM suggestions
            WHERE suggestionid=?
        |;
        $sth = $dbh->prepare($queryDelete);
        $sth->execute($suggestionid);
    }
}