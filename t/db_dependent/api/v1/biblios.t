#!/usr/bin/env perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Test::More tests => 2;
use Test::Mojo;
use Test::Warn;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Auth;
use Koha::Biblios;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'get() tests' => sub {

    plan tests => 18;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    $patron->discard_changes;
    my $userid = $patron->userid;

    my $biblio = $builder->build_sample_biblio({
        title  => 'The unbearable lightness of being',
        author => 'Milan Kundera'
    });
    $t->get_ok("//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber)
      ->status_is(403);

    $patron->flags(4)->store;

    $t->get_ok( "//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber
                => { Accept => 'application/weird+format' } )
      ->status_is(406)
      ->json_is( [ "application/json",
                   "application/marcxml+xml",
                   "application/marc-in-json",
                   "application/marc" ] );

    $t->get_ok( "//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber
                 => { Accept => 'application/json' } )
      ->status_is(200)
      ->json_is( '/title', 'The unbearable lightness of being' )
      ->json_is( '/author', 'Milan Kundera' );

    $t->get_ok( "//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber
                 => { Accept => 'application/marcxml+xml' } )
      ->status_is(200);

    $t->get_ok( "//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber
                 => { Accept => 'application/marc-in-json' } )
      ->status_is(200);

    $t->get_ok( "//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber
                 => { Accept => 'application/marc' } )
      ->status_is(200);

    $biblio->delete;
    $t->get_ok( "//$userid:$password@/api/v1/biblios/" . $biblio->biblionumber
                 => { Accept => 'application/marc' } )
      ->status_is(404)
      ->json_is( '/error', 'Object not found.' );

    $schema->storage->txn_rollback;
};

subtest 'delete() tests' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 } # no permissions
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    my $item      = $builder->build_sample_item();
    my $biblio_id = $item->biblionumber;

    $t->delete_ok("//$userid:$password@/api/v1/biblios/$biblio_id")
      ->status_is(403, 'Not enough permissions makes it return the right code');

    # Add permissions
    $builder->build(
        {
            source => 'UserPermission',
            value  => {
                borrowernumber => $patron->borrowernumber,
                module_bit     => 9,
                code           => 'edit_catalogue'
            }
        }
    );


    # Bibs with items cannot be deleted
    $t->delete_ok("//$userid:$password@/api/v1/biblios/$biblio_id")
      ->status_is(409);

    $item->delete();

    # Bibs with no items can be deleted
    $t->delete_ok("//$userid:$password@/api/v1/biblios/$biblio_id")
      ->status_is(204, 'SWAGGER3.2.4')
      ->content_is('', 'SWAGGER3.3.4');

    $t->delete_ok("//$userid:$password@/api/v1/biblios/$biblio_id")
      ->status_is(404);

    $schema->storage->txn_rollback;
};
