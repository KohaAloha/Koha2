#!/usr/bin/perl

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
use CGI;
use C4::Auth;    # get_template_and_user
use C4::Output;
use C4::BookShelves;
use C4::Languages;       # getTranslatedLanguages
use C4::Branch;          # GetBranches
use C4::Members;         # GetMember
use C4::NewsChannels;    # get_opac_news
use C4::Acquisition;     # GetRecentAcqui

my $input = new CGI;
my $dbh   = C4::Context->dbh;

my $limit = $input->param('recentacqui');

my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-main.tmpl",
        type            => "opac",
        query           => $input,
        authnotrequired => 1,
        flagsrequired   => { borrow => 1 },
    }
);

if ($limit) {
    my $recentacquiloop = GetRecentAcqui($limit);

    #     warn Data::Dumper::Dumper($recentacquiloop);
    $template->param( recentacquiloop => $recentacquiloop, );
}

# SearchMyLibraryFirst
if ( C4::Context->preference("SearchMyLibraryFirst") ) {
    if ( C4::Context->userenv ) {
        my $branches = GetBranches();
        my @branchloop;

        foreach my $thisbranch ( keys %$branches ) {
            my $selected = 1
              if ( C4::Context->userenv
                && ( $thisbranch eq C4::Context->userenv->{branch} ) );

#         warn $thisbranch;
#         warn C4::Context->userenv;
#         warn C4::Context->userenv->{branch};
#         warn " => ".C4::Context->userenv && ($thisbranch eq C4::Context->userenv->{branch});
            my %row = (
                value      => $thisbranch,
                selected   => $selected,
                branchname => $branches->{$thisbranch}->{'branchname'},
            );
            push @branchloop, \%row;
        }
        $template->param( "mylibraryfirst" => 1, branchloop => \@branchloop );
    }
    else {
        $template->param( "mylibraryfirst" => 0 );
    }
}

my $borrower = GetMember( $borrowernumber, 'borrowernumber' );
my @languages;
my $counter   = 0;
my $langavail = getTranslatedLanguages('opac');
foreach my $language (@$langavail) {

#   next if $currently_selected_languages->{$language};
#   FIXME: could incorporate language_name and language_locale_name for better display
    push @languages,
      { language => $language->{'language_code'}, counter => $counter };
    $counter++;
}

# Template params
if ( $counter > 1 ) {
    $template->param( languages => \@languages )
      if C4::Context->preference('opaclanguagesdisplay');
}

$template->param(
    textmessaging        => $borrower->{textmessaging},
    opaclanguagesdisplay => 0,
);

# display news
# use cookie setting for language, bug default to syspref if it's not set
my $news_lang = $input->cookie('KohaOpacLanguage')
  || C4::Context->preference('opaclanguages');
my $all_koha_news   = &GetNewsToDisplay($news_lang);
my $koha_news_count = scalar @$all_koha_news;

$template->param(
    koha_news       => $all_koha_news,
    koha_news_count => $koha_news_count
);

output_html_with_http_headers $input, $cookie, $template->output;
