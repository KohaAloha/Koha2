#!/usr/bin/perl
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use Test::More tests => 5;

use C4::Context;
use C4::Log;
use C4::Auth qw/checkpw/;
use Koha::Database;
use Koha::DateUtils;

use t::lib::Mocks qw/mock_preference/; # to mock CronjobLog
use t::lib::TestBuilder;

# Make sure we can rollback.
our $schema  = Koha::Database->new->schema;
$schema->storage->txn_begin;
our $dbh = C4::Context->dbh;

subtest 'Existing tests' => sub {
    plan tests => 6;

    my $success;
    eval {
        # FIXME: are we sure there is an member number 1?
        logaction("MEMBERS","MODIFY",1,"test operation");
        $success = 1;
    } or do {
        diag($@);
        $success = 0;
    };
    ok($success, "logaction seemed to work");

    eval {
        # FIXME: US formatted date hardcoded into test for now
        $success = scalar(@{GetLogs("","","",undef,undef,"","")});
    } or do {
        diag($@);
        $success = 0;
    };
    ok($success, "GetLogs returns results for an open search");

    eval {
        # FIXME: US formatted date hardcoded into test for now
        my $date = output_pref( { dt => dt_from_string, dateonly => 1, dateformat => 'iso' } );
        $success = scalar(@{GetLogs( $date, $date, "", undef, undef, "", "") } );
    } or do {
        diag($@);
        $success = 0;
    };
    ok($success, "GetLogs accepts dates in an All-matching search");

    eval {
        $success = scalar(@{GetLogs("","","",["MEMBERS"],["MODIFY"],1,"")});
    } or do {
        diag($@);
        $success = 0;
    };
    ok($success, "GetLogs seemed to find ".$success." like our test record in a tighter search");

    # We want numbers to be the same between runs.
    $dbh->do("DELETE FROM action_logs;");

    t::lib::Mocks::mock_preference('CronjobLog',0);
    cronlogaction();
    my $cronJobCount = $dbh->selectrow_array("SELECT COUNT(*) FROM action_logs WHERE module='CRONJOBS';",{});
    is($cronJobCount,0,"Cronjob not logged as expected.");

    t::lib::Mocks::mock_preference('CronjobLog',1);
    cronlogaction();
    $cronJobCount = $dbh->selectrow_array("SELECT COUNT(*) FROM action_logs WHERE module='CRONJOBS';",{});
    is($cronJobCount,1,"Cronjob logged as expected.");
};

subtest "GetLogs should return all logs if dates are not set" => sub {
    plan tests => 2;
    my $today = dt_from_string->add(minutes => -1);
    my $yesterday = dt_from_string->add( days => -1 );
    $dbh->do(q|
        INSERT INTO action_logs (timestamp, user, module, action, object, info)
        VALUES
        (?, 42, 'CATALOGUING', 'MODIFY', 4242, 'Record 42 has been modified by patron 4242 yesterday'),
        (?, 43, 'CATALOGUING', 'MODIFY', 4242, 'Record 43 has been modified by patron 4242 today')
    |, undef, output_pref({dt =>$yesterday, dateformat => 'iso'}), output_pref({dt => $today, dateformat => 'iso'}));
    my $logs = GetLogs( undef, undef, undef, ['CATALOGUING'], ['MODIFY'], 4242 );
    is( scalar(@$logs), 2, 'GetLogs should return all logs regardless the dates' );
    $logs = GetLogs( output_pref($today), undef, undef, ['CATALOGUING'], ['MODIFY'], 4242 );
    is( scalar(@$logs), 1, 'GetLogs should return the logs for today' );
};

subtest 'logaction(): interface is correctly logged' => sub {

    plan tests => 4;

    # No interface passed, using C4::Context->interface
    $dbh->do("DELETE FROM action_logs;");
    C4::Context->interface( 'commandline' );
    logaction( "MEMBERS", "MODIFY", 1, "test operation");
    my $logs = GetLogs();
    is( @{$logs}[0]->{ interface }, 'commandline', 'Interface correctly deduced (commandline)');

    # No interface passed, using C4::Context->interface
    $dbh->do("DELETE FROM action_logs;");
    C4::Context->interface( 'opac' );
    logaction( "MEMBERS", "MODIFY", 1, "test operation");
    $logs = GetLogs();
    is( @{$logs}[0]->{ interface }, 'opac', 'Interface correctly deduced (opac)');

    # Explicit interfaces
    $dbh->do("DELETE FROM action_logs;");
    C4::Context->interface( 'intranet' );
    logaction( "MEMBERS", "MODIFY", 1, 'test info', 'intranet');
    $logs = GetLogs();
    is( @{$logs}[0]->{ interface }, 'intranet', 'Passed interface is respected (intranet)');

    # Explicit interfaces
    $dbh->do("DELETE FROM action_logs;");
    C4::Context->interface( 'sip' );
    logaction( "MEMBERS", "MODIFY", 1, 'test info', 'sip');
    $logs = GetLogs();
    is( @{$logs}[0]->{ interface }, 'sip', 'Passed interface is respected (sip)');
};

subtest 'GetLogs() respects interface filters' => sub {

    plan tests => 5;

    $dbh->do("DELETE FROM action_logs;");

    logaction( 'MEMBERS', 'MODIFY', 1, 'opac info',        'opac');
    logaction( 'MEMBERS', 'MODIFY', 1, 'sip info',         'sip');
    logaction( 'MEMBERS', 'MODIFY', 1, 'intranet info',    'intranet');
    logaction( 'MEMBERS', 'MODIFY', 1, 'commandline info', 'commandline');

    my $logs = scalar @{ GetLogs() };
    is( $logs, 4, 'If no filter on interfaces is passed, all logs are returned');

    $logs = GetLogs(undef,undef,undef,undef,undef,undef,undef,['opac']);
    is( @{$logs}[0]->{ interface }, 'opac', 'Interface correctly filtered (opac)');

    $logs = GetLogs(undef,undef,undef,undef,undef,undef,undef,['sip']);
    is( @{$logs}[0]->{ interface }, 'sip', 'Interface correctly filtered (sip)');

    $logs = GetLogs(undef,undef,undef,undef,undef,undef,undef,['intranet']);
    is( @{$logs}[0]->{ interface }, 'intranet', 'Interface correctly filtered (intranet)');

    $logs = GetLogs(undef,undef,undef,undef,undef,undef,undef,['commandline']);
    is( @{$logs}[0]->{ interface }, 'commandline', 'Interface correctly filtered (commandline)');
};

subtest 'GDPR logging' => sub {
    plan tests => 6;

    my $builder = t::lib::TestBuilder->new;
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );

    t::lib::Mocks::mock_userenv({ patron => $patron });
    logaction( 'AUTH', 'FAILURE', $patron->id, '', 'opac' );
    my $logs = GetLogs( undef, undef, $patron->id, ['AUTH'], ['FAILURE'], $patron->id );
    is( @$logs, 1, 'We should find one auth failure' );

    t::lib::Mocks::mock_preference('AuthFailureLog', 1);
    my $strong_password = 'N0tStr0ngAnyM0reN0w:)';
    $patron->set_password({ password => $strong_password });
    my @ret = checkpw( $dbh, $patron->userid, 'WrongPassword', undef, undef, 1);
    is( $ret[0], 0, 'Authentication failed' );
    # Look for auth failure but NOT on patron id, pass userid in info parameter
    $logs = GetLogs( undef, undef, 0, ['AUTH'], ['FAILURE'], undef, $patron->userid );
    is( @$logs, 1, 'We should find one auth failure with this userid' );
    t::lib::Mocks::mock_preference('AuthFailureLog', 0);
    @ret = checkpw( $dbh, $patron->userid, 'WrongPassword', undef, undef, 1);
    $logs = GetLogs( undef, undef, 0, ['AUTH'], ['FAILURE'], undef, $patron->userid );
    is( @$logs, 1, 'Still only one failure with this userid' );
    t::lib::Mocks::mock_preference('AuthSuccessLog', 1);
    @ret = checkpw( $dbh, $patron->userid, $strong_password, undef, undef, 1);
    is( $ret[0], 1, 'Authentication succeeded' );
    # Now we can look for patron id
    $logs = GetLogs( undef, undef, $patron->id, ['AUTH'], ['SUCCESS'], $patron->id );
    is( @$logs, 1, 'We expect only one auth success line for this patron' );
};

$schema->storage->txn_rollback;
