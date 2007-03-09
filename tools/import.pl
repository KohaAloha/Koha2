#!/usr/bin/perl

# $Id$

# Script for handling import of MARC data into Koha db
#   and Z39.50 lookups

# Koha library project  www.koha.org

# Licensed under the GPL


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

# standard or CPAN modules used
use CGI;
use DBI;

# Koha modules used
use C4::Context;
use C4::Output;
use C4::Interface::CGI::Output;
use C4::Input;
use C4::Biblio;
use MARC::File::USMARC;

use C4::Output;
use C4::Auth;
use C4::Breeding;

#------------------
# Constants

my $includes = C4::Context->config('includes') ||
	"/usr/local/www/hdl/htdocs/includes";

# HTML colors for alternating lines
my $lc1='#dddddd';
my $lc2='#ddaaaa';

#-------------
#-------------
# Initialize

my $userid=$ENV{'REMOTE_USER'};

my $input = new CGI;
my $dbh = C4::Context->dbh;

my $uploadmarc=$input->param('uploadmarc');
my $overwrite_biblio = $input->param('overwrite_biblio');
my $filename = $input->param('filename');
my $syntax = $input->param('syntax');
my ($template, $loggedinuser, $cookie)
	= get_template_and_user({template_name => "tools/import.tmpl",
					query => $input,
					type => "intranet",
					authnotrequired => 0,
					flagsrequired => {tools => 1},
					debug => 1,
					});

$template->param(SCRIPT_NAME => $ENV{'SCRIPT_NAME'},
						uploadmarc => $uploadmarc);
if ($uploadmarc && length($uploadmarc)>0) {
	my $marcrecord='';
	while (<$uploadmarc>) {
		$marcrecord.=$_;
	}
	my ($notmarcrecord,$alreadyindb,$alreadyinfarm,$imported) = ImportBreeding($marcrecord,$overwrite_biblio,$filename,$syntax,int(rand(99999)));

	$template->param(imported => $imported,
							alreadyindb => $alreadyindb,
							alreadyinfarm => $alreadyinfarm,
							notmarcrecord => $notmarcrecord,
							total => $imported+$alreadyindb+$alreadyinfarm+$notmarcrecord,
							);

}

output_html_with_http_headers $input, $cookie, $template->output;


#---------------
# log cleared, as marcimport is (almost) rewritten from scratch.
# $Log$
# Revision 1.4  2007/03/09 15:14:47  tipaul
# rel_3_0 moved to HEAD
#
# Revision 1.1.2.4  2006/12/22 17:13:49  tipaul
# removing "management" permission, that is useless (replaced by tools & admin)
#
# Revision 1.1.2.3  2006/12/18 16:35:20  toins
# removing use HTML::Template from *.pl.
#
# Revision 1.1.2.2  2006/10/03 12:27:32  toins
# the script was written twice into the file !
#
# Revision 1.1.2.1  2006/09/26 13:42:54  toins
# fix wrong link to breeding.tmpl
#
# Revision 1.1  2006/02/24 11:52:38  hdl
# Adding tools directory template and scripts
# Changing barcodes, export and import and letters directory.
# Changing export script name (marc.pl) to export.pl
# Changing import script name (breeding.pl) to import.pl
#
# Revision 1.4  2005/05/04 08:52:13  tipaul
# synch'ing 2.2 and head
#
# Revision 1.3  2005/03/23 09:57:47  doxulting
# Adding a parameter to allow acces to people with management/tools flags
