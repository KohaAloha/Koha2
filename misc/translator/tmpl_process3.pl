#!/usr/bin/perl
# This file is part of Koha
# Parts copyright 2003-2004 Paul Poulain
# Parts copyright 2003-2004 Jerome Vizcaino
# Parts copyright 2004 Ambrose Li

=head1 NAME

tmpl_process3.pl - Experimental version of tmpl_process.pl
using gettext-compatible translation files

=cut

use strict;
use Getopt::Long;
use Locale::PO;
use File::Temp qw( :POSIX );
use TmplTokenizer;
use VerboseWarnings qw( error_normal warn_normal );

###############################################################################

use vars qw( @in_files $in_dir $str_file $out_dir );
use vars qw( @excludes $exclude_regex );
use vars qw( $recursive_p );
use vars qw( $pedantic_p );
use vars qw( $href );
use vars qw( $type );	# file extension (DOS form without the dot) to match
use vars qw( $charset_in $charset_out );

###############################################################################

sub find_translation ($) {
    my($s) = @_;
    my $key = $s;
    if ($s =~ /\S/s) {
    print STDERR "DEBUG: before: ($key)\n";
	$key = TmplTokenizer::string_canon($key);
	$key = TmplTokenizer::charset_convert($key, $charset_in, $charset_out);
	$key = TmplTokenizer::quote_po($key);
    print STDERR "DEBUG: after: ($key)\n";
    }
    return defined $href->{$key}
		&& !$href->{$key}->fuzzy
		&& length Locale::PO->dequote($href->{$key}->msgstr)?
	   Locale::PO->dequote($href->{$key}->msgstr): $s;
}

sub text_replace_tag ($$) {
    my($t, $attr) = @_;
    my $it;
    # value [tag=input], meta
    my $tag = lc($1) if $t =~ /^<(\S+)/s;
    my $translated_p = 0;
    for my $a ('alt', 'content', 'title', 'value') {
	if ($attr->{$a}) {
	    next if $a eq 'content' && $tag ne 'meta';
	    next if $a eq 'value' && ($tag ne 'input'
		|| (ref $attr->{'type'} && $attr->{'type'}->[1] =~ /^(?:hidden|radio)$/)); # FIXME
	    my($key, $val, $val_orig, $order) = @{$attr->{$a}}; #FIXME
	    my($pre, $trimmed, $post) = TmplTokenizer::trim $val;
	    if ($val =~ /\S/s) {
		my $s = $pre . find_translation($trimmed) . $post;
		if ($attr->{$a}->[1] ne $s) { #FIXME
		    $attr->{$a}->[1] = $s; # FIXME
		    $attr->{$a}->[2] = ($s =~ /"/s)? "'$s'": "\"$s\""; #FIXME
		    $translated_p = 1;
		}
	    }
	}
    }
    if ($translated_p) {
	$it = "<$tag"
	    . join('', map {
		    sprintf(' %s=%s', $_, $attr->{$_}->[2]) #FIXME
		} sort {
		    $attr->{$a}->[3] <=> $attr->{$b}->[3] #FIXME
		} keys %$attr)
	    . '>';
    } else {
	$it = $t;
    }
    return $it;
}

sub text_replace (**) {
    my($h, $output) = @_;
    for (;;) {
	my $s = TmplTokenizer::next_token $h;
    last unless defined $s;
	my($kind, $t, $attr) = ($s->type, $s->string, $s->attributes);
	if ($kind eq TmplTokenType::TEXT) {
	    my($pre, $trimmed, $post) = TmplTokenizer::trim $t;
	    print $output $pre, find_translation($trimmed), $post;
	} elsif ($kind eq TmplTokenType::TEXT_PARAMETRIZED) {
	    my $fmt = find_translation($s->form);
	    print $output TmplTokenizer::parametrize($fmt, [ map {
		my($kind, $t, $attr) = ($_->type, $_->string, $_->attributes);
		$kind == TmplTokenType::TAG && %$attr?
		    text_replace_tag($t, $attr): $t } $s->parameters ], [ $s->anchors ]);
	} elsif ($kind eq TmplTokenType::TAG && %$attr) {
	    print $output text_replace_tag($t, $attr);
	} elsif (defined $t) {
	    print $output $t;
	}
    }
}

sub listfiles ($$) {
    my($dir, $type) = @_;
    my @it = ();
    if (opendir(DIR, $dir)) {
	my @dirent = readdir DIR;	# because DIR is shared when recursing
	closedir DIR;
	for my $dirent (@dirent) {
	    my $path = "$dir/$dirent";
	    if ($dirent =~ /^\./ || $dirent eq 'CVS' || $dirent eq 'RCS'
	    || (defined $exclude_regex && $dirent =~ /^(?:$exclude_regex)$/)) {
		;
	    } elsif (-f $path) {
		push @it, $path if !defined $type || $dirent =~ /\.(?:$type)$/;
	    } elsif (-d $path && $recursive_p) {
		push @it, listfiles($path, $type);
	    }
	}
    } else {
	warn_normal "$dir: $!", undef;
    }
    return @it;
}

###############################################################################

sub usage_error (;$) {
    for my $msg (split(/\n/, $_[0])) {
	print STDERR "$msg\n";
    }
    print STDERR "Try `$0 --help' for more information.\n";
    exit(-1);
}

###############################################################################

GetOptions(
    'input|i=s'				=> \@in_files,
    'outputdir|o=s'			=> \$out_dir,
    'recursive|r'			=> \$recursive_p,
    'str-file|s=s'			=> \$str_file,
    'exclude|x=s'			=> \@excludes,
    'pedantic-warnings|pedantic'	=> sub { $pedantic_p = 1 },
) || usage_error;

VerboseWarnings::set_application_name $0;
VerboseWarnings::set_pedantic_mode $pedantic_p;

# try to make sure .po files are backed up (see BUGS)
$ENV{VERSION_CONTROL} = 't';

# keep the buggy Locale::PO quiet if it says stupid things
$SIG{__WARN__} = sub {
	my($s) = @_;
	print STDERR $s unless $s =~ /^Strange line in [^:]+: #~/s
    };

my $action = shift or usage_error('You must specify an ACTION.');
usage_error('You must at least specify input and string list filenames.')
    if !@in_files || !defined $str_file;

# Type match defaults to *.tmpl plus *.inc if not specified
$type = "tmpl|inc" if !defined($type);

# Check the inputs for being files or directories
for my $input (@in_files) {
    usage_error("$input: Input must be a file or directory.\n"
	    . "(Symbolic links are not supported at the moment)")
	unless -d $input || -f $input;;
}

# Generates the global exclude regular expression
$exclude_regex =  '(?:'.join('|', @excludes).')' if @excludes;

# Generate the list of input files if a directory is specified
if (-d $in_files[0]) {
    die "If you specify a directory as input, you must specify only it.\n"
	    if @in_files > 1;

    # input is a directory, generates list of files to process
    $in_dir = $in_files[0];
    $in_dir =~ s/\/$//; # strips the trailing / if any
    @in_files = listfiles($in_dir, $type);
} else {
    for my $input (@in_files) {
	die "You cannot specify input files and directories at the same time.\n"
		unless -f $input;
    }
}

# restores the string list from file
$href = Locale::PO->load_file_ashash($str_file);

# guess the charsets. HTML::Templates defaults to iso-8859-1
if (defined $href) {
    $charset_out = TmplTokenizer::charset_canon $2
	    if $href->{'""'}->msgstr =~ /\bcharset=(["']?)([^;\s"'\\]+)\1/;
    for my $msgid (keys %$href) {
	if ($msgid =~ /\bcharset=(["']?)([^;\s"'\\]+)\1/) {
	    my $candidate = TmplTokenizer::charset_canon $2;
	    die "Conflicting charsets in msgid: $charset_in vs $candidate\n"
		    if defined $charset_in && $charset_in ne $candidate;
	    $charset_in = $2;
	}
    }
}
if (!defined $charset_in) {
    $charset_in = TmplTokenizer::charset_canon 'iso8859-1';
    warn "Warning: Can't determine original templates' charset, defaulting to $charset_in\n";
}

if ($action eq 'create')  {
    # updates the list. As the list is empty, every entry will be added
    die "$str_file: Output file already exists" if -f $str_file;
    my($tmph, $tmpfile) = tmpnam();
    # Generate the temporary file that acts as <MODULE>/POTFILES.in
    for my $input (@in_files) {
	print $tmph "$input\n";
    }
    close $tmph;
    # Generate the specified po file ($str_file)
    system ('xgettext.pl', '-s', '-f', $tmpfile, '-o', $str_file);
    unlink $tmpfile || warn_normal "$tmpfile: unlink failed: $!\n", undef;

} elsif ($action eq 'update') {
    my($tmph1, $tmpfile1) = tmpnam();
    my($tmph2, $tmpfile2) = tmpnam();
    close $tmph2; # We just want a name
    # Generate the temporary file that acts as <MODULE>/POTFILES.in
    for my $input (@in_files) {
	print $tmph1 "$input\n";
    }
    close $tmph1;
    # Generate the temporary file that acts as <MODULE>/<LANG>.pot
    system('./xgettext.pl', '-s', '-f', $tmpfile1, '-o', $tmpfile2,
	    (defined $charset_in? ('-I', $charset_in): ()),
	    (defined $charset_out? ('-O', $charset_out): ()));
    # Merge the temporary "pot file" with the specified po file ($str_file)
    # FIXME: msgmerge(1) is a Unix dependency
    # FIXME: need to check the return value
    system('msgmerge', '-U', '-s', $str_file, $tmpfile2);
    unlink $tmpfile1 || warn_normal "$tmpfile1: unlink failed: $!\n", undef;
    unlink $tmpfile2 || warn_normal "$tmpfile2: unlink failed: $!\n", undef;

} elsif ($action eq 'install') {
    if(!defined($out_dir)) {
	usage_error("You must specify an output directory when using the install method.");
    }
	
    if ($in_dir eq $out_dir) {
	warn "You must specify a different input and output directory.\n";
	exit -1;
    }

    # Make sure the output directory exists
    # (It will auto-create it, but for compatibility we should not)
    -d $out_dir || die "$out_dir: The directory does not exist\n";

    # Try to open the file, because Locale::PO doesn't check :-/
    open(INPUT, "<$str_file") || die "$str_file: $!\n";
    close INPUT;

    # creates the new tmpl file using the new translation
    for my $input (@in_files) {
	die "Assertion failed"
		unless substr($input, 0, length($in_dir) + 1) eq "$in_dir/";

	my $h = TmplTokenizer->new( $input );
	$h->set_allow_cformat( 1 );
	VerboseWarnings::set_input_file_name $input;

	my $target = $out_dir . substr($input, length($in_dir));
	my $targetdir = $` if $target =~ /[^\/]+$/s;
	if (!-d $targetdir) {
	    print STDERR "Making directory $targetdir...";
	    # creates with rwxrwxr-x permissions
	    mkdir($targetdir, 0775) || warn_normal "$targetdir: $!", undef;
	}
	print STDERR "Creating $target...\n";
	open( OUTPUT, ">$target" ) || die "$target: $!\n";
	text_replace( $h, *OUTPUT );
	close OUTPUT;
    }

} else {
    usage_error('Unknown action specified.');
}
exit 0;

###############################################################################

=head1 SYNOPSIS

./tmpl_process3.pl [ I<tmpl_process.pl options> ]

=head1 DESCRIPTION

This is an experimental version of the tmpl_process.pl script,
using standard gettext-style PO files.  Note that the behaviour
of this script should still be considered unstable.

Currently, the create, update, and install actions have all been
reimplemented and seem to work.

The create action calls xgettext.pl to do the actual work;
the update action calls xgettext.pl and msgmerge(1) to do the
actual work.

The script can detect <TMPL_VAR> directives embedded inside what
appears to be a full sentence (this actual work being done by
TmplTokenizer(3)); these larger patterns appear in the translation
file as c-format strings with %s.

Whitespace in extracted strings are folded to single blanks, in
order to prevent new strings from appearing when minor changes in
the original templates occur, and to prevent overly difficult to
read strings in the PO file.

=head1 BUGS

The --help option has not been implemented yet.

xgettext.pl must be present in the current directory; the
msgmerge(1) command must also be present in the search path.
The script currently does not check carefully whether these
dependent commands are present.

If xgettext.pl is interrupted by the user, a corrupted po file
will result. This is very seriously wrong.

Locale::PO(3) has a lot of bugs. It can neither parse nor
generate GNU PO files properly; a couple of workarounds have
been written in TmplTokenizer and more is likely to be needed
(e.g., to get rid of the "Strange line" warning for #~).

There are probably some other bugs too, since this has not been
tested very much.

=head1 SEE ALSO

xgettext.pl,
msgmerge(1),
Locale::PO(3),
translator_doc.txt

=cut
