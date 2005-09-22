#!/usr/bin/perl -w

# $Id$

# Copyright 2005 Katipo Communications
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
use lib '/usr/local/koha/intranet/modules';
use Curses::UI;
use C4::Circulation::Circ2;
use C4::Members;
use C4::Print;
use C4::Context;

my $cui = new Curses::UI( -color_support => 1 );

my @menu = (
    {
        -label   => 'File',
        -submenu => [
            { -label => 'Issues   ^I', -value => \&issues },
            { -label => 'Returns  ^R', -value => \&returns },
            { -label => 'Exit     ^Q', -value => \&exit_dialog }
        ]
    },
    {
        -label   => 'Parameters',
        -submenu => [
            { -label => 'Branch',  -value => \&changebranch },
            { -label => 'Printer', -value => \&changeprinter }
        ]
    },
);

my $menu = $cui->add(
    'menu', 'Menubar',
    -menu => \@menu,
    -fg   => "blue",
);

my $win1 = $cui->add(
    'win1', 'Window',
    -border => 1,
    -y      => 1,
    -bfg    => 'red',
    -width  => 40,
);

my $win2 = $cui->add(
    'win2', 'Window',
    -border => 1,
    -y      => 1,
    -x      => 40,
    -height => 10,
    -bfg    => 'red',
);

my $win3 = $cui->add(
    'win3', 'Window',
    -border => 1,
    -y      => 11,
    -x      => 40,
    -height => 10,
    -bfg    => 'red',
);

my $texteditor = $win1->add( "text", "TextEditor",
    -text =>
      "This is the first cut of a \ncirculations system using Curses::UI\n"
      . "Use the menus (or the keyboard\nshortcuts) to choose issues or \nreturns"
);

$cui->set_binding( sub { $menu->focus() }, "\cX" );
$cui->set_binding( \&exit_dialog, "\cQ" );
$cui->set_binding( \&issues,      "\cI" );
$cui->set_binding( \&returns,     "\cR" );

$texteditor->focus();
$cui->mainloop();

my %env;

sub exit_dialog() {
    my $return = $cui->dialog(
        -message => "Do you really want to quit?",
        -title   => "Are you sure???",
        -buttons => [ 'yes', 'no' ],

    );

    exit(0) if $return;
}

sub returns {
    my $barcode = $cui->question(
        -title    => 'Returns',
        -question => 'Barcode'
    );
    my $branch = 'MAIN';

    if ($barcode) {
        my ( $returned, $messages, $iteminformation, $borrower ) =
          returnbook( $barcode, $branch );
        if ( $borrower && $borrower->{'borrowernumber'} ) {
            $borrower =
              getpatroninformation( \%env, $borrower->{'borrowernumber'}, 0 );
            $win1->delete('borrowerdata');
            my $borrowerdata = $win1->add(
                'borrowerdata', 'TextViewer',
                -text => "Cardnumber: $borrower->{'cardnumber'}\n"
                  . "Name: $borrower->{'title'} $borrower->{'firstname'} $borrower->{'surname'}\n"

            );

            $borrowerdata->focus();
        }
        else {
            $cui->error( -message => 'That item isnt on loan' );
        }
    }
}

sub issues {

    # this routine does the actual issuing

    my $borrowernumber;
    my $borrowerlist;

   # the librarian can overide system issue date, need to fetch values from them
    my $year;
    my $month;
    my $day;

    $win1->delete('text');

    # get a cardnumber or a name
    my $cardnumber = $cui->question(
        -title    => 'Issues',
        -question => 'Cardnumber'
    );

    # search for that borrower
    my ( $count, $borrowers ) =
      BornameSearch( \%env, $cardnumber, 'cardnumber', 'web' );
    my @borrowers = @$borrowers;
    if ( $#borrowers == -1 ) {
        $cui->error( -message =>
              'No borrowers match that name or cardnumber please try again.' );
    }
    elsif ( $#borrowers == 0 ) {
        $borrowernumber = $borrowers[0]->{'borrowernumber'};
    }
    else {
        $borrowerlist = \@borrowers;
    }

    if ($borrowernumber) {

        # if we have one single borrower, we can start issuing
        doissues( $borrowernumber, \%env, $year, $month, $day );
    }
    elsif ($borrowerlist) {

        # choose from a list then start issuing
        my @borrowernumbers;
        my %borrowernames;
        foreach my $bor (@$borrowerlist) {
            push @borrowernumbers, $bor->{'borrowernumber'};
            $borrowernames{ $bor->{'borrowernumber'} } =
              "$bor->{'cardnumber'} $bor->{'firstname'} $bor->{surname}";
        }
        $win1->delete('mypopupbox');
        my $popupbox = $win1->add(
            'mypopupbox', 'Popupmenu',
            -values   => [@borrowernumbers],
            -labels   => \%borrowernames,
            -onchange => \&dolistissues,
        );

        $popupbox->focus();
    }
    else {
    }
}

sub dolistissues {
    my $list           = shift;
    my $borrowernumber = $list->get();
    doissues($borrowernumber);
}

sub doissues {
    my ( $borrowernumber, $env, $year, $month, $day ) = @_;
    my $datedue;

    my $borrower = getpatroninformation( $env, $borrowernumber, 0 );
    $win1->delete('borrowerdata');
    my $borrowerdata = $win1->add( 'borrowerdata', 'TextViewer',
        -text => "Cardnumber: $borrower->{'cardnumber'}\n"
          . "Name: $borrower->{'title'} $borrower->{'firstname'} $borrower->{'surname'}"
    );

    $borrowerdata->focus();

    $win3->delete('pastissues');
    my $issueslist = getissues($borrower);
    my $oldissues;
    foreach my $it ( keys %$issueslist ) {
        $oldissues .=
          $issueslist->{$it}->{'barcode'}
          . " $issueslist->{$it}->{'title'} $issueslist->{$it}->{'date_due'}\n";

    }

    my $pastissues =
      $win3->add( 'pastissues', 'TextViewer', -text => $oldissues, );
    $pastissues->focus();

    $win2->delete('currentissues');
    my $currentissues =
      $win2->add( 'currentissues', 'TextViewer',
        -text => "Todays issues go here", );
    $currentissues->focus();

    # go into a loop issuing until a blank barcode is given
    while ( my $barcode = $cui->question( -question => 'Barcode' ) ) {
        my $issues;
        my $issueconfirmed;
        my ( $error, $question ) =
          canbookbeissued( $env, $borrower, $barcode, $year, $month, $day );
        my $noerror    = 1;
        my $noquestion = 1;
        foreach my $impossible ( keys %$error ) {
            $cui->error( -message => $impossible );
            $noerror = 0;
        }
        if ($noerror) {

            # no point asking confirmation questions if we cant issue
            foreach my $needsconfirmation ( keys %$question ) {
                $noquestion     = 0;
                $issueconfirmed = $cui->dialog(
                    -message =>
"$needsconfirmation $question->{$needsconfirmation} Issue anyway?",
                    -title   => "Confirmation",
                    -buttons => [ 'yes', 'no' ],

                );

            }
        }
        if ( $noerror && ( $noquestion || $issueconfirmed ) ) {
            issuebook( $env, $borrower, $barcode, $datedue );
            $issues .= "$barcode";
            $win2->delete('currentissues');
            $currentissues =
              $win2->add( 'currentissues', 'TextViewer', -text => $issues, );

        }

    }

    # finished issuing
    my $printconfirm = $cui->dialog(
        -message => "Print a slip for this borrower?",
        -title   => "Print Slip",
        -buttons => [ 'yes', 'no' ],

    );
    if ($printconfirm) {
        printslip( $env, $borrowernumber );
    }
}

sub changebranch {
    my $dbh = C4::Context->dbh();
    my $sth = $dbh->prepare('SELECT * FROM branches');
    $sth->execute();
    my @branches;
    while ( my $data = $sth->fetchrow_hashref() ) {
        push @branches, $data->{'branchcode'};
    }
    $sth->finish;
    $win1->delete('text');
    $win1->delete('mypopupbox');
    my $popupbox = $win1->add(
        'mypopupbox', 'Popupmenu',
        -values   => [@branches],
        -onchange => \&setbranch,
    );
    $popupbox->focus();
}

sub changeprinter {
    my $dbh = C4::Context->dbh();
    my $sth = $dbh->prepare('SELECT * FROM printers');
    $sth->execute();
    my @printers;
    while ( my $data = $sth->fetchrow_hashref() ) {
        push @printers, $data->{'printqueue'};
    }
    $sth->finish;
    $win1->delete('text');
    $win1->delete('mypopupbox');
    my $popupbox = $win1->add(
        'mypopupbox', 'Popupmenu',
        -values   => [@printers],
        -onchange => \&setprinter,
    );
    $popupbox->focus();

}

sub setbranch {
    my $list   = shift;
    my $branch = $list->get();
    $env{'branch'} = $branch;
}

sub setprinter {
    my $list    = shift;
    my $printer = $list->get();
    $env{'printer'} = $printer;
}
