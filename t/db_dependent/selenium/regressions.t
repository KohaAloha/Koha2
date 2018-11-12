#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use C4::Context;

use Test::More tests => 3;

use C4::Context;
use Koha::AuthUtils;
use t::lib::Selenium;
use t::lib::TestBuilder;

eval { require Selenium::Remote::Driver; };
skip "Selenium::Remote::Driver is needed for selenium tests.", 1 if $@;

my $s = t::lib::Selenium->new;

my $driver = $s->driver;
my $opac_base_url = $s->opac_base_url;
my $base_url = $s->base_url;
my $builder = t::lib::TestBuilder->new;

# It seems that we do not have enough records indexed with ES
my $SearchEngine_value = C4::Context->preference('SearchEngine');
C4::Context->set_preference('SearchEngine', 'Zebra');

my $AudioAlerts_value = C4::Context->preference('AudioAlerts');
C4::Context->set_preference('AudioAlerts', '1');

our @cleanup;
subtest 'OPAC - borrowernumber and branchcode as html attributes' => sub {
    plan tests => 2;

    my $patron = $builder->build_object(
        { class => 'Koha::Patrons', value => { flags => 1 } } );
    my $password = Koha::AuthUtils::generate_password();
    $patron->update_password( $patron->userid, $password );
    $s->opac_auth( $patron->userid, $password );
    my $elt = $driver->find_element('//span[@class="loggedinusername"]');
    is( $elt->get_attribute('data-branchcode'), $patron->library->branchcode,
        "Since bug 20921 span.loggedinusername should contain data-branchcode"
    );
    is( $elt->get_attribute('data-borrowernumber'), $patron->borrowernumber,
"Since bug 20921 span.loggedinusername should contain data-borrowernumber"
    );
    push @cleanup, $patron, $patron->category, $patron->library;
};

subtest 'OPAC - Remove from cart' => sub {
    plan tests => 4;

    $driver->get( $opac_base_url . "opac-search.pl?q=d" );

    # A better way to do that would be to modify the way we display the basket count
    # We should show/hide the count instead or recreate the node
    my @basket_count_elts = $driver->find_elements('//span[@id="basketcount"]/span');
    is( scalar(@basket_count_elts), 0, 'Basket should be empty');

    # This will fail if nothing is indexed, but at this point we should have everything setup correctly
    my @checkboxes = $driver->find_elements('//input[@type="checkbox"][@name="biblionumber"]');
    my $biblionumber1 = $checkboxes[0]->get_value();
    my $biblionumber3 = $checkboxes[2]->get_value();
    my $biblionumber5 = $checkboxes[4]->get_value();

    $driver->find_element('//a[@class="addtocart cart'.$biblionumber1.'"]')->click;
    my $basket_count_elt = $driver->find_element('//span[@id="basketcount"]/span');
    is( $basket_count_elt->get_text(),
        1, 'One element should have been added to the cart' );

    $driver->find_element('//a[@class="addtocart cart'.$biblionumber3.'"]')->click;
    $driver->find_element('//a[@class="addtocart cart'.$biblionumber5.'"]')->click;
    $basket_count_elt = $driver->find_element('//span[@id="basketcount"]/span');
    is( $basket_count_elt->get_text(),
        3, '3 elements should have been added to the cart' );

    $driver->find_element('//a[@class="cartRemove cartR'.$biblionumber3.'"]')->click;
    $basket_count_elt = $driver->find_element('//span[@id="basketcount"]/span');
    is( $basket_count_elt->get_text(),
        2, '1 element should have been removed from the cart' );
};

subtest 'Play sound on the circulation page' => sub {
    plan tests => 1;

    my $builder  = t::lib::TestBuilder->new;
    my $patron = $builder->build_object({ class => 'Koha::Patrons', value => { flags => 0 }});

    my $mainpage = $s->base_url . q|mainpage.pl|;
    $driver->get($mainpage . q|?logout.x=1|);
    like( $driver->get_title(), qr(Log in to Koha), );
    $s->auth;

    $driver->get( $base_url . "/circ/circulation.pl?borrowernumber=" . $patron->borrowernumber );

    my $audio_node = $driver->find_element('//span[@id="audio-alert"]/audio[@src="/intranet-tmpl/prog/sound/beep.ogg"]');

    push @cleanup, $patron, $patron->category, $patron->library;
};

END {
    C4::Context->preference('SearchEngine', $SearchEngine_value);
    C4::Context->preference('AudioAlerts', $AudioAlerts_value);
    $_->delete for @cleanup;
};
