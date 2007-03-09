package C4::Branch;

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
use C4::Context;
use C4::Koha;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

# set the version for version checking
$VERSION = do { my @v = '$Revision$' =~ /\d+/g; shift(@v).".".join( "_", map { sprintf "%03d", $_ } @v ); };

=head1 NAME

C4::Branch - Koha branch module

=head1 SYNOPSIS

use C4::Branch;

=head1 DESCRIPTION

The functions in this module deal with branches.

=head1 FUNCTIONS

=cut

@ISA    = qw(Exporter);
@EXPORT = qw(
   &GetBranchCategory
   &GetBranchName
   &GetBranch
   &GetBranches
   &GetBranchDetail
   &get_branchinfos_of
   &ModBranch
   &CheckBranchCategorycode
   &GetBranchInfo
   &ModBranchCategoryInfo
   &DelBranch
);

=head2 GetBranches

  $branches = &GetBranches();
  returns informations about ALL branches.
  Create a branch selector with the following code
  IndependantBranches Insensitive...
  
=head3 in PERL SCRIPT

my $branches = GetBranches;
my @branchloop;
foreach my $thisbranch (keys %$branches) {
    my $selected = 1 if $thisbranch eq $branch;
    my %row =(value => $thisbranch,
                selected => $selected,
                branchname => $branches->{$thisbranch}->{'branchname'},
            );
    push @branchloop, \%row;
}


=head3 in TEMPLATE
            <select name="branch">
                <option value="">Default</option>
            <!-- TMPL_LOOP name="branchloop" -->
                <option value="<!-- TMPL_VAR name="value" -->" <!-- TMPL_IF name="selected" -->selected<!-- /TMPL_IF -->><!-- TMPL_VAR name="branchname" --></option>
            <!-- /TMPL_LOOP -->
            </select>

=cut

sub GetBranches {

    my $onlymine=@_;
    # returns a reference to a hash of references to ALL branches...
    my %branches;
    my $dbh = C4::Context->dbh;
    my $sth;
    my $query="SELECT * from branches";
    if ($onlymine && C4::Context->userenv && C4::Context->userenv->{branch}){
      $query .= " WHERE branchcode =".$dbh->quote(C4::Context->userenv->{branch});
    }
    $query.=" order by branchname";
    $sth = $dbh->prepare($query);
    $sth->execute;
    while ( my $branch = $sth->fetchrow_hashref ) {
        my $nsth =
          $dbh->prepare(
            "select categorycode from branchrelations where branchcode = ?");
        $nsth->execute( $branch->{'branchcode'} );
        while ( my ($cat) = $nsth->fetchrow_array ) {

            # FIXME - This seems wrong. It ought to be
            # $branch->{categorycodes}{$cat} = 1;
            # otherwise, there's a namespace collision if there's a
            # category with the same name as a field in the 'branches'
            # table (i.e., don't create a category called "issuing").
            # In addition, the current structure doesn't really allow
            # you to list the categories that a branch belongs to:
            # you'd have to list keys %$branch, and remove those keys
            # that aren't fields in the "branches" table.
            $branch->{$cat} = 1;
        }
        $branches{ $branch->{'branchcode'} } = $branch;
    }
    return ( \%branches );
}

=head2 GetBranchName

=cut

sub GetBranchName {
    my ($branchcode) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;
    $sth = $dbh->prepare("Select branchname from branches where branchcode=?");
    $sth->execute($branchcode);
    my $branchname = $sth->fetchrow_array;
    $sth->finish;
    return ($branchname);
}

=head2 ModBranch

&ModBranch($newvalue);

This function modify an existing branches.

C<$newvalue> is a ref to an array wich is containt all the column from branches table.

=cut

sub ModBranch {
    my ($data) = @_;
    
    my $dbh    = C4::Context->dbh;
    if ($data->{add}) {
        my $query  = "
            INSERT INTO branches
            (branchcode,branchname,branchaddress1,
            branchaddress2,branchaddress3,branchphone,
            branchfax,branchemail,branchip,branchprinter)
            VALUES (?,?,?,?,?,?,?,?,?,?)
        ";
        my $sth    = $dbh->prepare($query);
        $sth->execute(
            $data->{'branchcode'},       $data->{'branchname'},
            $data->{'branchaddress1'},   $data->{'branchaddress2'},
            $data->{'branchaddress3'},   $data->{'branchphone'},
            $data->{'branchfax'},        $data->{'branchemail'},
            $data->{'branchip'},         $data->{'branchprinter'},
        );
    } else {
        my $query  = "
            UPDATE branches
            SET branchname=?,branchaddress1=?,
                branchaddress2=?,branchaddress3=?,branchphone=?,
                branchfax=?,branchemail=?,branchip=?,branchprinter=?
            WHERE branchcode=?
        ";
        my $sth    = $dbh->prepare($query);
        $sth->execute(
            $data->{'branchname'},
            $data->{'branchaddress1'},   $data->{'branchaddress2'},
            $data->{'branchaddress3'},   $data->{'branchphone'},
            $data->{'branchfax'},        $data->{'branchemail'},
            $data->{'branchip'},         $data->{'branchprinter'},
            $data->{'branchcode'},
        );
    }
    # sort out the categories....
    my @checkedcats;
    my $cats = GetBranchCategory();
    foreach my $cat (@$cats) {
        my $code = $cat->{'categorycode'};
        if ( $data->{$code} ) {
            push( @checkedcats, $code );
        }
    }
    my $branchcode = uc( $data->{'branchcode'} );
    my $branch     = GetBranchInfo($branchcode);
    $branch = $branch->[0];
    my $branchcats = $branch->{'categories'};
    my @addcats;
    my @removecats;
    foreach my $bcat (@$branchcats) {

        unless ( grep { /^$bcat$/ } @checkedcats ) {
            push( @removecats, $bcat );
        }
    }
    foreach my $ccat (@checkedcats) {
        unless ( grep { /^$ccat$/ } @$branchcats ) {
            push( @addcats, $ccat );
        }
    }
    foreach my $cat (@addcats) {
        my $sth =
          $dbh->prepare(
"insert into branchrelations (branchcode, categorycode) values(?, ?)"
          );
        $sth->execute( $branchcode, $cat );
        $sth->finish;
    }
    foreach my $cat (@removecats) {
        my $sth =
          $dbh->prepare(
            "delete from branchrelations where branchcode=? and categorycode=?"
          );
        $sth->execute( $branchcode, $cat );
        $sth->finish;
    }
}

=head2 GetBranchCategory

$results = GetBranchCategory($categorycode);

C<$results> is an ref to an array.

=cut

sub GetBranchCategory {

    # returns a reference to an array of hashes containing branches,
    my ($catcode) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;

    #    print DEBUG "GetBranchCategory: entry: catcode=".cvs($catcode)."\n";
    if ($catcode) {
        $sth =
          $dbh->prepare(
            "select * from branchcategories where categorycode = ?");
        $sth->execute($catcode);
    }
    else {
        $sth = $dbh->prepare("Select * from branchcategories");
        $sth->execute();
    }
    my @results;
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @results, $data );
    }
    $sth->finish;

    #    print DEBUG "GetBranchCategory: exit: returning ".cvs(\@results)."\n";
    return \@results;
}

=head2 GetBranch

$branch = GetBranch( $query, $branches );

=cut

sub GetBranch ($$) {
    my ( $query, $branches ) = @_;    # get branch for this query from branches
    my $branch = $query->param('branch');
    my %cookie = $query->cookie('userenv');
    ($branch)                || ($branch = $cookie{'branchname'});
    ( $branches->{$branch} ) || ( $branch = ( keys %$branches )[0] );
    return $branch;
}

=head2 GetBranchDetail

  $branchname = &GetBranchDetail($branchcode);

Given the branch code, the function returns the corresponding
branch name for a comprehensive information display

=cut

sub GetBranchDetail {
    my ($branchcode) = @_;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT * FROM branches WHERE branchcode = ?");
    $sth->execute($branchcode);
    my $branchname = $sth->fetchrow_hashref();
    $sth->finish();
    return $branchname;
}


=head2 get_branchinfos_of

  my $branchinfos_of = get_branchinfos_of(@branchcodes);

Associates a list of branchcodes to the information of the branch, taken in
branches table.

Returns a href where keys are branchcodes and values are href where keys are
branch information key.

  print 'branchname is ', $branchinfos_of->{$code}->{branchname};

=cut

sub get_branchinfos_of {
    my @branchcodes = @_;

    my $query = '
    SELECT branchcode,
       branchname
    FROM branches
    WHERE branchcode IN ('
      . join( ',', map( { "'" . $_ . "'" } @branchcodes ) ) . ')
';
    return C4::Koha::get_infos_of( $query, 'branchcode' );
}

=head2 GetBranchInfo

$results = GetBranchInfo($branchcode);

returns C<$results>, a reference to an array of hashes containing branches.

=cut

sub GetBranchInfo {
    my ($branchcode) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;
    if ($branchcode) {
        $sth =
          $dbh->prepare(
            "Select * from branches where branchcode = ? order by branchcode");
        $sth->execute($branchcode);
    }
    else {
        $sth = $dbh->prepare("Select * from branches order by branchcode");
        $sth->execute();
    }
    my @results;
    while ( my $data = $sth->fetchrow_hashref ) {
        my $nsth =
          $dbh->prepare(
            "select categorycode from branchrelations where branchcode = ?");
        $nsth->execute( $data->{'branchcode'} );
        my @cats = ();
        while ( my ($cat) = $nsth->fetchrow_array ) {
            push( @cats, $cat );
        }
        $nsth->finish;
        $data->{'categories'} = \@cats;
        push( @results, $data );
    }
    $sth->finish;
    return \@results;
}

=head2 DelBranch

&DelBranch($branchcode);

=cut

sub DelBranch {
    my ($branchcode) = @_;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("delete from branches where branchcode = ?");
    $sth->execute($branchcode);
    $sth->finish;
}

=head2 ModBranchCategoryInfo

&ModBranchCategoryInfo($data);
sets the data from the editbranch form, and writes to the database...

=cut

sub ModBranchCategoryInfo {

    my ($data) = @_;
    my $dbh    = C4::Context->dbh;
    my $sth    = $dbh->prepare("replace branchcategories (categorycode,categoryname,codedescription) values (?,?,?)");
    $sth->execute(uc( $data->{'categorycode'} ),$data->{'categoryname'}, $data->{'codedescription'} );
    $sth->finish;
}

=head2 DeleteBranchCategory

DeleteBranchCategory($categorycode);

=cut

sub DeleteBranchCategory {
    my ($categorycode) = @_;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("delete from branchcategories where categorycode = ?");
    $sth->execute($categorycode);
    $sth->finish;
}

=head2 CheckBranchCategorycode

$number_rows_affected = CheckBranchCategorycode($categorycode);

=cut

sub CheckBranchCategorycode {

    # check to see if the branchcode is being used in the database somewhere....
    my ($categorycode) = @_;
    my $dbh            = C4::Context->dbh;
    my $sth            =
      $dbh->prepare(
        "select count(*) from branchrelations where categorycode=?");
    $sth->execute($categorycode);
    my ($total) = $sth->fetchrow_array;
    return $total;
}



=head1 AUTHOR

Koha Developement team <info@koha.org>

=cut
