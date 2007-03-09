package C4::Review;

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

use vars qw($VERSION @ISA @EXPORT);

# set the version for version checking
$VERSION = do { my @v = '$Revision$' =~ /\d+/g; shift(@v).".".join( "_", map { sprintf "%03d", $_ } @v ); };

=head1 NAME

C4::Review - Perl Module containing routines for dealing with reviews of items

=head1 SYNOPSIS

  use C4::Review;


  my $review=getreview($biblionumber,$borrowernumber);
  savereview($biblionumber,$borrowernumber,$review);
  updatereview($biblionumber,$borrowernumber,$review);
  my $count=numberofreviews($biblionumber);
  my $reviews=getreviews($biblionumber);
  my $reviews=getallreviews($status);

=head1 DESCRIPTION

Review.pm provides many routines for manipulating reviews.

=head1 FUNCTIONS

=cut

@ISA    = qw(Exporter);
@EXPORT = qw(getreview savereview updatereview numberofreviews
  getreviews getallreviews approvereview deletereview);

use vars qw();

my $DEBUG = 0;

=head2 getreview

  $review = getreview($biblionumber,$borrowernumber);

Takes a borrowernumber and a biblionumber and returns the review of that biblio


=cut

sub getreview {
    my ( $biblionumber, $borrowernumber ) = @_;
    my $dbh   = C4::Context->dbh;
    my $query =
      "SELECT * FROM reviews WHERE biblionumber=? and borrowernumber=?";
    my $sth = $dbh->prepare($query);
    $sth->execute( $biblionumber, $borrowernumber );
    my $review = $sth->fetchrow_hashref();
    $sth->finish();
    return $review;
}

sub savereview {
    my ( $biblionumber, $borrowernumber, $review ) = @_;
    my $dbh   = C4::Context->dbh;
    my $query = "INSERT INTO reviews (borrowernumber,biblionumber,
	review,approved,datereviewed) VALUES 
  (?,?,?,?,now())";
    my $sth = $dbh->prepare($query);
    $sth->execute( $borrowernumber, $biblionumber, $review, 0 );
    $sth->finish();
}

sub updatereview {
    my ( $biblionumber, $borrowernumber, $review ) = @_;
    my $dbh   = C4::Context->dbh;
    my $query = "UPDATE reviews SET review=?,datereviewed=now(),approved=?
  WHERE borrowernumber=? and biblionumber=?";
    my $sth = $dbh->prepare($query);
    $sth->execute( $review, 0, $borrowernumber, $biblionumber );
    $sth->finish();
}

sub numberofreviews {
    my ($biblionumber) = @_;
    my $dbh            = C4::Context->dbh;
    my $query          =
      "SELECT count(*) FROM reviews WHERE biblionumber=? and approved=?";
    my $sth = $dbh->prepare($query);
    $sth->execute( $biblionumber, 1 );
    my $count = $sth->fetchrow_hashref;

    $sth->finish();
    return ( $count->{'count(*)'} );
}

sub getreviews {
    my ( $biblionumber, $approved ) = @_;
    my $dbh   = C4::Context->dbh;
    my $query =
"SELECT * FROM reviews WHERE biblionumber=? and approved=? order by datereviewed desc";
    my $sth = $dbh->prepare($query) || warn $dbh->err_str;
    $sth->execute( $biblionumber, $approved );
    my @results;
    while ( my $data = $sth->fetchrow_hashref() ) {
        push @results, $data;
    }
    $sth->finish();
    return ( \@results );
}

sub getallreviews {
    my ($status) = @_;
    my $dbh      = C4::Context->dbh;
    my $query    =
      "SELECT * FROM reviews WHERE approved=? order by datereviewed desc";
    my $sth = $dbh->prepare($query);
    $sth->execute($status);
    my @results;
    while ( my $data = $sth->fetchrow_hashref() ) {
        push @results, $data;
    }
    $sth->finish();
    return ( \@results );
}

=head2 approvereview

  approvereview($reviewid);

Takes a reviewid and marks that review approved

=cut

sub approvereview {
    my ($reviewid) = @_;
    my $dbh        = C4::Context->dbh();
    my $query      = "UPDATE reviews
               SET approved=?
               WHERE reviewid=?";
    my $sth = $dbh->prepare($query);
    $sth->execute( 1, $reviewid );
    $sth->finish();
}

=head2 deletereview

  deletereview($reviewid);

Takes a reviewid and deletes it

=cut

sub deletereview {
    my ($reviewid) = @_;
    my $dbh        = C4::Context->dbh();
    my $query      = "DELETE FROM reviews
               WHERE reviewid=?";
    my $sth = $dbh->prepare($query);
    $sth->execute($reviewid);
    $sth->finish();
}

1;
__END__

=head1 AUTHOR

Koha Team

=cut
