#!/usr/bin/perl

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
use CGI;
use C4::Context;
use C4::Output;

use C4::Auth;
use C4::Output;
use C4::Koha;
use C4::Interface::CGI::Output;
use C4::Branch; # GetBranches

my $input = new CGI;
my $dbh = C4::Context->dbh;

my $type=$input->param('type');
my $branch = $input->param('branch');
$branch="" unless $branch;
my $op = $input->param('op');

# my $flagsrequired;
# $flagsrequired->{circulation}=1;
my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "admin/finesrules.tmpl",
                             query => $input,
                             type => "intranet",
                             authnotrequired => 0,
 			     flagsrequired => {parameters => 1},
			      debug => 1,
                             });
# save the values entered
if ($op eq 'save') {
  my @names=$input->param();
  my $sth_search = $dbh->prepare("select count(*) as total from issuingrules where branchcode=? and categorycode=? and itemtype=?");

  my $sth_Finsert = $dbh->prepare("insert into issuingrules (branchcode,categorycode,itemtype,fine,firstremind,chargeperiod) values (?,?,?,?,?,?)");
  my $sth_Fupdate=$dbh->prepare("Update issuingrules set fine=?,firstremind=?,chargeperiod=? where branchcode=? and categorycode=? and itemtype=?");
  my $sth_Fdelete=$dbh->prepare("delete from issuingrules where branchcode=? and categorycode=? and itemtype=? and issuelength=0");

  foreach my $key (@names){
    # FINES
    if ($key =~ /F-(.*)-(.*)\.(.*)/) {
      my $br = $1; # branch
      my $bor = $2; # borrower category
      my $cat = $3; # item type
      my $data=$input->param($key);
      my ($fine,$firstremind,$chargeperiod)=split(',',$data);
      warn "$br $bor $cat $fine $firstremind $chargeperiod";
# 			if ($fine >0) {
#       $br="*" unless ($br);
      $bor="*" unless ($bor);
      $cat="*" unless ($cat);
      $sth_search->execute($br,$bor,$cat);
      my $res = $sth_search->fetchrow_hashref();
      if ($res->{total}) {
              $sth_Fupdate->execute($fine,$firstremind,$chargeperiod,$br,$bor,$cat);
      } else {
              $sth_Finsert->execute($br,$bor,$cat,$fine,$firstremind,$chargeperiod);
      }
    }
  }

}
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

my $sth=$dbh->prepare("Select description,categorycode from categories order by description");
$sth->execute;
my @trow3;
my @title_loop;
# my $i=0;
while (my $data=$sth->fetchrow_hashref){
	my %row = (in_title => $data->{'description'});
	push @title_loop,\%row;
 	push @trow3,$data->{'categorycode'};
# 	$i++;
}

my %row = (in_title => "*");
push @title_loop, \%row;
push @trow3,'*';

$sth->finish;
$sth=$dbh->prepare("Select description,itemtype from itemtypes order by description");
$sth->execute;
# $i=0;
my $toggle= 1;
my @row_loop;
my @itemtypes;
while (my $row=$sth->fetchrow_hashref){
	push @itemtypes,\$row;
}
my $line;
$line->{itemtype} = "*";
$line->{description} = "*";
push @itemtypes,\$line;

foreach my $data (@itemtypes) {
	my @trow2;
	my @cell_loop;
	if ( $toggle eq 1 ) {
		$toggle = 0;
	} else {
		$toggle = 1;
	}
	for (my $i=0;$i<=$#trow3;$i++){
		my $sth2=$dbh->prepare("select * from issuingrules where branchcode=? and categorycode=? and itemtype=?");
		$sth2->execute($branch,$trow3[$i],$$data->{'itemtype'});
		my $dat=$sth2->fetchrow_hashref;
		$sth2->finish;
		my $fine=$dat->{'fine'}+0;
		my $finesvalue;
		$finesvalue= "$fine,$dat->{'firstremind'},$dat->{'chargeperiod'}" if $fine+$dat->{'firstremind'}+$dat->{'chargeperiod'}>0;
		my %row = (finesname=> "F-$branch-$trow3[$i].$$data->{'itemtype'}",
					finesvalue => $finesvalue,
					toggle => $toggle,
					);
		push @cell_loop,\%row;
	}
	my %row = (categorycode => $$data->{description},
  					cell =>\@cell_loop);
	push @row_loop, \%row;
}

$sth->finish;
$template->param(title => \@title_loop,
                row => \@row_loop,
                branchloop => \@branchloop,
                branch => $branch,
                intranetcolorstylesheet => C4::Context->preference("intranetcolorstylesheet"),
		intranetstylesheet => C4::Context->preference("intranetstylesheet"),
		IntranetNav => C4::Context->preference("IntranetNav"),
						);
output_html_with_http_headers $input, $cookie, $template->output;
