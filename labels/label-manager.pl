#!/usr/bin/perl

use strict;
use CGI;
use C4::Auth;
use C4::Labels;
use C4::Output;
use HTML::Template::Pro;
#use POSIX qw(ceil);
#use Data::Dumper;
#use Smart::Comments;

use vars qw($debug);

BEGIN { 
	$debug = $ENV{DEBUG} || 0;
}

my $dbh            = C4::Context->dbh;
my $query          = new CGI;
$query->param('debug') and $debug = $query->param('debug');
my $op             = $query->param('op');
my $layout_id      = $query->param('layout_id');
my $layoutname     = $query->param('layoutname');
my $barcodetype    = $query->param('barcodetype');
my $bcn            = $query->param('tx_barcode');
my $title          = $query->param('tx_title');
my $subtitle       = $query->param('tx_subtitle');
my $isbn           = $query->param('tx_isbn');
my $issn           = $query->param('tx_issn');
my $itemtype       = $query->param('tx_itemtype');
my $dcn            = $query->param('tx_dewey');
my $classif        = $query->param('tx_classif');
my $itemcallnumber = $query->param('tx_itemcallnumber');
my $subclass       = $query->param('tx_subclass');
my $author         = $query->param('tx_author');
my $tmpl_id        = $query->param('tmpl_id');
my $summary        = $query->param('summary');
my $startlabel     = $query->param('startlabel');
my $printingtype   = $query->param('printingtype');
my $guidebox       = $query->param('guidebox');
my $fontsize       = $query->param('fontsize');
my @itemnumber     = $query->param('itemnumber');
my $batch_type     = $query->param('type');

# little block for displaying active layout/template/batch in templates
# ----------
my $batch_id                    = $query->param('batch_id');
my $active_layout               = get_active_layout();
my $active_template             = GetActiveLabelTemplate();
my $active_layout_name          = $active_layout->{'layoutname'};
my $active_template_name        = $active_template->{'tmpl_code'};
# ----------

#if (!$batch_id ) {
#    $batch_id  = get_highest_batch();
#}

#my $batch_type = "labels";      #FIXME: Hardcoded for testing/development...
my @messages;
my ($itemnumber) = @itemnumber if (scalar(@itemnumber) == 1);

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "labels/label-manager.tmpl",
        query           => $query,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { catalogue => 1 },
        debug           => 1,
    }
);

if ( $op eq 'save_conf' ) {    # this early sub is depreciated, use save_layout()
	SaveConf(
		$barcodetype,    $title,  $isbn, 
		$issn,    $itemtype,         $bcn,            $dcn, 
		$classif, $subclass,         $itemcallnumber,      $author, 
		$tmpl_id, $printingtype,   $guidebox,       $startlabel, $layoutname
	);
	print $query->redirect("label-home.pl");
	exit;
}
elsif  ( $op eq 'save_layout' ) {
	save_layout(
		$barcodetype,    $title,  $subtitle, $isbn, 
		$issn,    $itemtype,         $bcn,            $dcn, 
		$classif, $subclass,         $itemcallnumber,      $author, 
		$tmpl_id, $printingtype,   $guidebox,       $startlabel, $layoutname,
		$layout_id
		);
	### $layoutname
	print $query->redirect("label-home.pl");
	exit;
}
elsif  ( $op eq 'add_layout' ) {
	add_layout(
		$barcodetype,    $title, $subtitle,  $isbn, 
		$issn,    $itemtype,         $bcn,            $dcn, 
		$classif, $subclass,         $itemcallnumber,      $author, 
		$tmpl_id, $printingtype,   $guidebox,       $startlabel, $layoutname,
		$layout_id
	);
	### $layoutname
	print $query->redirect("label-home.pl");
	exit;
}

# FIXME: The trinary conditionals here really need to be replaced with a more robust form of db abstraction -fbcit

elsif ( $op eq 'add' ) {   # add item
	my $query2 = "INSERT INTO $batch_type ( " . (($batch_type eq 'labels') ? 'itemnumber' : 'borrowernumber') . ", batch_id ) values ( ?,? )";
	my $sth2   = $dbh->prepare($query2);
	for my $inum (@itemnumber) {
		$sth2->execute($inum, $batch_id);
	}
	$sth2->finish;
}
elsif ( $op eq 'deleteall' ) {
	my $query2 = "DELETE FROM $batch_type";
	my $sth2   = $dbh->prepare($query2);
	$sth2->execute();
	$sth2->finish;
}
elsif ( $op eq 'delete' ) {
	my @labelids = $query->param((($batch_type eq 'labels') ? 'labelid' : 'cardid'));
	scalar @labelids or push @messages, (($batch_type eq 'labels') ? "ERROR: No labelid(s) supplied for deletion." : "ERROR: No cardid(s) supplied for deletion.");
	my $ins = "?," x (scalar @labelids);
	$ins =~ s/\,$//;
	my $query2 = "DELETE FROM $batch_type WHERE " . (($batch_type eq 'labels') ? 'labelid' : 'cardid') ." IN ($ins) ";
	$debug and push @messages, "query2: $query2 -- (@labelids)";
	my $sth2   = $dbh->prepare($query2);
	$sth2->execute(@labelids);
	$sth2->finish;
}
elsif ( $op eq 'delete_batch' ) {
	delete_batch($batch_id, $batch_type);
	print $query->redirect("label-manager.pl");
	exit;
}
elsif ( $op eq 'add_batch' ) {
	$batch_id= add_batch($batch_type);
}
elsif ( $op eq 'set_active_layout' ) {
	set_active_layout($layout_id);
	print $query->redirect("label-home.pl");
	exit;
}
elsif ( $op eq 'deduplicate' ) {
	my $return = deduplicate_batch($batch_id);
	my $msg = (($return) ? "Removed $return" : "Error revoving") . " duplicate items from Batch $batch_id";
	push @messages, $msg;
}

#  first lets do a read of the labels table , to get the a list of the
# currently entered items to be prinited
my @batches = get_batches($batch_type);
my @resultsloop = ($batch_type eq 'labels') ? GetLabelItems($batch_id) : GetPatronCardItems($batch_id);
#warn "$batches[0] (id $batch_id)";
#warn Dumper(@resultsloop);

#calc-ing number of sheets
#my $number_of_results = scalar @resultsloop;
#my $sheets_needed = ceil( ( --$number_of_results + $startrow ) / 8 ); # rounding up
#my $tot_labels       = ( $sheets_needed * 8 );
#my $start_results    = ( $number_of_results + $startrow );
#my $labels_remaining = ( $tot_labels - $start_results );

if (scalar @messages) {
	$template->param(message => 1);
	my @complex = ();
	foreach (@messages) {
		my %hash = (message_text => $_);
		push @complex, \%hash;
	}
	$template->param(message_loop => \@complex);
}
$template->param(
    batch_type                  => $batch_type,
    batch_id                    => $batch_id,
    batch_count                 => scalar @resultsloop,
    active_layout_name          => $active_layout_name,
    active_template_name        => $active_template_name,

    resultsloop                 => \@resultsloop,
    batches                     => \@batches,
    tmpl_desc                   => $active_template->{'tmpl_desc'},

    #  startrow         => $startrow,
    #  sheets           => $sheets_needed,
    #  labels_remaining => $labels_remaining,
);
output_html_with_http_headers $query, $cookie, $template->output;
