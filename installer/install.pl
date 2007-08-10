#!/usr/bin/perl -w # please develop with -w

#use diagnostics;

# use Install;
use InstallAuth;
use C4::Context;
use C4::Output;
use C4::Languages;

use strict; # please develop with the strict pragma

use CGI;

my $query=new CGI;
my $step=$query->param('step');

my $language=$query->param('language');
my ($template, $loggedinuser, $cookie);


my $all_languages=getAllLanguages();

if (defined($language) ){
  setlanguagecookie($query,$language,"install.pl?step=1");
}
($template, $loggedinuser, $cookie)
        = get_template_and_user({template_name => "installer/step".($step?$step:1).".tmpl",
                query => $query,
                type => "intranet",
                authnotrequired => 0,
                debug => 1,
                });

my %info;
$info{'dbname'}=C4::Context->config("database");
$info{'dbms'}=(C4::Context->config("db_scheme")?C4::Context->config("db_scheme"):"mysql");
$info{'hostname'}=C4::Context->config("hostname");
($info{'hostname'},$info{'port'})=($1,$2) if $info{'hostname'}=~/([^:]*):([0-9]+)/;
$info{'user'}=C4::Context->config("user");
$info{'password'}=C4::Context->config("pass");
my $dbh= DBI->connect("DBI:$info{dbms}:$info{dbname}:$info{hostname}".($info{port}?":$info{port}":""),$info{'user'}, $info{'password'});


if ($step && $step==1){
  #First Step
  #Checking ALL perl Modules and services needed are installed.
  #Whenever there is an error, adding a report to the page
  # I suppose here that Apache user can access /usr/bin/
  # If mysql or zebra are in some fancy directory not in PATH
  # Performing a disk search.
  $template->param(language=>1);
  my $problem;
  
  unless ($] >= 5.006001) {			# Bug 179
      $template->param("problems"=>1,"perlversion"=>1);
      $problem=1;
  }
  unless (-x "/usr/bin/perl") {
    my $realperl=`which perl`;
    $realperl=`find / -name perl` unless ($realperl);
    chomp $realperl;
    $template->param("problems"=>1,'perllocation'=>1) unless ($realperl);
    $problem=1 unless($realperl);
  }
  unless (-x "/usr/local/bin/mysql") {
    my $mysql=`which mysql`;
    $mysql=`find / -name mysql` unless ($mysql);
    chomp $mysql;
    $template->param("problems"=>1,'mysql'=>1) unless ($mysql);
    $problem=1 unless($mysql);
  }
  unless (-x "/usr/local/bin/zebraidx" ||-x "/usr/local/bin/zebraidx-2.0") {
    my $zebra=`which zebraidx`;
    $zebra=`which zebraidx-2.0` unless ($zebra);
    $zebra=`find / -name "zebraidx*"` unless ($zebra);
    chomp $zebra;
    $template->param("problems"=>1,'zebra'=>1) unless ($zebra);
    $problem=1 unless ($zebra);
  }
  unless (-x "/usr/local/bin/zebrasrv" ||-x "/usr/local/bin/zebrasrv-2.0") {
    my $zebra=`which zebrasrv`;
    $zebra=`which zebrasrv-2.0` unless ($zebra);
    $zebra=`find / -name "zebrasrv*"` unless ($zebra);
    chomp $zebra;
    $template->param("problems"=>1,'zebra'=>1) unless ($zebra);
    $problem=1 unless ($zebra);
  }
  unless (-x "/usr/local/bin/yaz-client") {
    my $yaz=`which yaz-client`;
    $yaz=`find / -name "yaz-client*"` unless ($yaz);
    chomp $yaz;
    $template->param("problems"=>1,'yaz'=>1) unless ($yaz);
    $problem=1 unless ($yaz);
  }
  # We could here use a special find 
  my @missing = ();
  unless (eval {require ZOOM})       {
          push @missing, {name=>"ZOOM"};
  }
  unless (eval {require LWP::Simple})       {
          push @missing, {name=>"LWP::Simple"};
  }
  unless (eval {require XML::Simple})       {
          push @missing, {name=>"XML::Simple"};
  }
  unless (eval {require MARC::File::XML})       {
          push @missing, {name=>"MARC::File::XML"};
  }
  unless (eval {require MARC::File::USMARC})       {
          push @missing, {name=>"MARC::File::USMARC"};
  }
  unless (eval {require DBI})              { push @missing,{name=>"DBI"} };
  unless (eval {require Date::Manip})      { push @missing,{name=>"Date::Manip"} };
  unless (eval {require DBD::mysql})       { push @missing,{name=>"DBD::mysql"} };
  unless (eval {require HTML::Template})   { push @missing,{name=>"HTML::Template::Pro"} };
  unless (eval {require HTML::Template})   { push @missing,{name=>"Date::Calc"} };
  unless (eval {require Digest::MD5})      { push @missing,{name=>"Digest::MD5"} };
  unless (eval {require MARC::Record})     { push @missing,{name=>"MARC::Record"} };
  unless (eval {require Mail::Sendmail})   { push @missing,{name=>"Mail::Sendmail",usagemail=>1} };
  unless (eval {require List::MoreUtils})  { push @missing,{name=>"List::MoreUtils"} };
  unless (eval {require XML::RSS})         { push @missing,{name=>"XML::RSS"} };
# The following modules are not mandatory, depends on how the library want to use Koha
  unless (eval {require PDF::API2})   { 
          if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
              push @missing,{name=>"PDF::API2",usagebarcode=>1};
          }
  }
  unless (eval {require GD::Barcorde})   { 
    if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
      push @missing,{name=>"GD::Barcode",usagebarcode=>1,usagespine=>1};
    }
  }
  unless (eval {require Data::Random})   { 
    if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
      push @missing,{name=>"Data::Random",usagebarcode=>1};
    }
  }
  unless (eval {require PDF::Reuse::Barcode})   {
    if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
      push @missing,{name=>"PDF::Reuse::Barcode",usagebarcode=>1};
    }
  }
  unless (eval {require PDF::Report})   {
    if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
      push @missing,{name=>"PDF::Report",usagebarcode=>1};
    }
  }
  unless (eval {require GD::Barcode::UPCE})   {
    if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
      push @missing,{name=>"GD::Barcode::UPCE",usagepine=>1};
    }
  }
  unless (eval {require Net::LDAP})       {
    if ($#missing>=0) { # only when $#missing >= 0 so this isn't fatal
      push @missing,{name=>"Net::LDAP",usageLDAP=>1};
    }
  }

  $template->param(missings=>\@missing) if (scalar(@missing)>0);
  $template->param('checkmodule'=>1) unless (scalar(@missing) && $problem);
  
} elsif ($step && $step==2){
  # Check Database connection and access
  $template->param(%info);
  my $checkmysql=$query->param("checkmysql");
  $template->param('mysqlconnection'=>$checkmysql);
  if ($checkmysql){
    if ($dbh){
      # Can connect to the mysql
      $template->param("checkdatabaseaccess"=>1);
      if ($info{dbms} eq "mysql"){
        #Check if database created
        my $rv=$dbh->do("SHOW DATABASES LIKE \'$info{dbname}\'");
        if ($rv==1){$template->param('checkdatabasecreated'=>1);}
        #Check if user have all necessary grants on this database.
        my $rq=$dbh->prepare("SHOW GRANTS FOR \'$info{user}\'\@'$info{hostname}'");
        $rq->execute;
        my $grantaccess;
        while (my ($line)=$rq->fetchrow){
          my $dbname=$info{dbname};
          if ($line=~m/$dbname/ || index($line,'*.*')>0){
            $grantaccess=1 if (index($line,'ALL PRIVILEGES')>0 ||
            ((index($line,'SELECT')>0)&&(index($line,'INSERT')>0)&&(index($line,'UPDATE')>0)&&(index($line,'DELETE')>0)&&(index($line,'CREATE')>0)&&(index($line,'DROP')>0)));
          }
        }
        unless ($grantaccess){
          $rq=$dbh->prepare("SHOW GRANTS FOR \'$info{user}\'\@'\%'");
          $rq->execute;
          while (my ($line)=$rq->fetchrow){
            my $dbname=$info{dbname};
            if ($line=~m/$dbname/ || index($line,'*.*')>0){
              $grantaccess=1 if (index($line,'ALL PRIVILEGES')>0 ||
              ((index($line,'SELECT')>0)&&(index($line,'INSERT')>0)&&(index($line,'UPDATE')>0)&&(index($line,'DELETE')>0)&&(index($line,'CREATE')>0)&&(index($line,'DROP')>0)));
            }
          }
        }
        $template->param("checkgrantaccess"=>$grantaccess);
      }
    } else {
      $template->param("error"=>DBI::err,"message"=>DBI::errstr);
    }
  }
} elsif ($step && $step==3){
  my $op=$query->param('op');
  if ($op && $op eq 'finish'){
    if (C4::Context->preference('Version')) {
        warn "UPDATE Version";
      my $finish=$dbh->prepare("UPDATE systempreferences SET value=? WHERE variable='Version'");
      $finish->execute(C4::Context->config("kohaversion"));
    } else {
        warn "INSERT Version";
      my $finish=$dbh->prepare("INSERT into systempreferences (variable,value,explanation) values ('Version',?,'The Koha database version. Don t change this value manually, it s holded by the webinstaller')");
      $finish->execute(C4::Context->config("kohaversion"));
    }
    # Installation is finished.
    # We just deny anybody acess to install
    # And we redirect people to mainpage.
    # The installer wil have to relogin since we donot pass cookie to redirection.
    $template->param("$op"=>1);
  }elsif ($op && $op eq 'finished'){
    print $query->redirect("/cgi-bin/koha/mainpage.pl");
    exit 1;
  } elsif ($op && $op eq 'addframeworks'){
    #Framework importing and reports
    my $lang;
    my %hashlevel;
   # sort by filename -> prepend with numbers to specify order of insertion. 
    my @fnames = sort { my @aa = split /\/|\\/, ($a); my @bb = split /\/|\\/, ($b); $aa[-1] lt $bb[-1] } $query->param('framework')  ;
	$dbh->do('SET FOREIGN_KEY_CHECKS=0');
    my $request=$dbh->prepare("SELECT value FROM systempreferences WHERE variable='FrameworksLoaded'");
    $request->execute;
    my ($systempreference)=$request->fetchrow;
    foreach my $file (@fnames){
#      warn $file;
      undef $/;
      my $strcmd="mysql ".($info{hostname}?" -h $info{hostname} ":"").($info{port}?" -P $info{port} ":"").($info{user}?" -u $info{user} ":"").($info{password}?" -p$info{password}":"")." $info{dbname} ";
      my $error = qx($strcmd < $file 2>&1);
      my @file = split qr(\/|\\),$file;
      $lang=$file[scalar(@file)-3] unless ($lang);
      my $level=$file[scalar(@file)-2];
      unless ($error){
        $systempreference.="$file[scalar(@file)-1]|" unless(index($systempreference,$file[scalar(@file)-1])>=0);
      }
      #Bulding here a hierarchy to display files by level.
      push @{$hashlevel{$level}},{"fwkname"=>$file[scalar(@file)-1],"error"=>$error};
    }
    #systempreference contains an ending |
    chop $systempreference;
    my @list;
    map {push @list,{"level"=>$_,"fwklist"=>$hashlevel{$_}}} keys %hashlevel;
    my $fwk_language;
    for my $each_language(@$all_languages) {
# 		warn "CODE".$each_language->{'language_code'};
# 		warn "LANG:".$lang;
      if ($lang eq $each_language->{'language_code'}) {
              $fwk_language = $each_language->{language_locale_name};
      }
    }
    my $updateflag=$dbh->do("UPDATE systempreferences set value=\"$systempreference\" where variable='FrameworksLoaded'");
    unless ($updateflag==1){
      my $string="INSERT INTO systempreferences (value, variable, explanation, type) VALUES (\"$systempreference\",'FrameworksLoaded','Frameworks loaded through webinstaller','choice')";
      my $rq=$dbh->prepare($string);
      $rq->execute;
    }
    $template->param("fwklanguage"=>$fwk_language,
                     "list"=>\@list);
    $template->param("$op"=>1);
	$dbh->do('SET FOREIGN_KEY_CHECKS=1');
  } elsif ( $op && $op eq 'selectframeworks'){
    #Framework Selection
    #sql data for import are supposed to be located in misc/sql-datas/<language>/<level>
    # Where <language> is en|fr or any international abbreviation (provided language hash is updated... This will be a problem with internationlisation.)
    # Where <level> is a category of requirement : required, recommended optional
    # level should contain : 
    #   SQL File for import With a readable name.
    #   txt File taht explains what this SQL File is meant for.
    # Could be VERY useful to have A Big file for a kind of library.
    # But could also be useful to have some Authorised values data set prepared here.
    # Framework Selection is achieved through checking boxes.
    my $langchoice=$query->param('fwklanguage') ;
    $langchoice=$query->cookie('KohaOpacLanguage') unless ($langchoice);
    my $dir=C4::Context->config('intranetdir')."/misc/sql-datas/";
    opendir (MYDIR,$dir);
    my @listdir= grep { !/^\.|CVS/ && -d "$dir/$_"} readdir(MYDIR);
    closedir MYDIR;
    my $frmwklangs = getFrameworkLanguages();
    my @languages;
    map{
      push @languages,{'dirname'=>$_->{'language_code'}, 'languagedescription'=>$_->{'language_name'},'checked'=>($_->{'language_code'} eq $langchoice) } if ($_->{'language_code'});
    } @$frmwklangs;
    $template->param("languagelist"=>\@languages);
    undef $/;
    $dir=C4::Context->config('intranetdir')."/misc/sql-datas/$langchoice";
    opendir (MYDIR,$dir) || warn "no open $dir";
    @listdir= grep { !/^\.|CVS/ && -d "$dir/$_"} readdir(MYDIR);
    closedir MYDIR;
    my @levellist;
    my $request=$dbh->prepare("SELECT value FROM systempreferences WHERE variable='FrameworksLoaded'");
    $request->execute;
    my ($frameworksloaded)=$request->fetchrow;
    my %frameworksloaded;
    foreach (split(/\|/,$frameworksloaded)){
      $frameworksloaded{$_}=1;
    }
    foreach my $requirelevel (@listdir){
      $dir =C4::Context->config('intranetdir')."/misc/sql-datas/$langchoice/$requirelevel";
      opendir (MYDIR,$dir);
      my @listname = grep { !/^\.|CVS/ && -f "$dir/$_" && $_=~m/\.sql$/} readdir(MYDIR);
      closedir MYDIR;
      my %cell;
      my @frameworklist;
      map{
        my $name=substr($_,0,-4);
        open FILE, "< $dir/$name.txt";
        my $lines = <FILE>; 
        $lines=~s/\n|\r/<br \/>/g;
        use utf8;
        utf8::encode($lines) unless (utf8::is_utf8($lines));
        push @frameworklist,
          {'fwkname'=>$name, 
           'fwkfile'=>"$dir/$_",
           'fwkdescription'=>$lines,
           'checked'=>(($frameworksloaded{$_}||($requirelevel=~/(mandatory|requi|oblig|necess)/i))?1:0)
          };
      } @listname;
      my @fwks = sort { $a->{'fwkname'} lt $b->{'fwkname'} } @frameworklist;
#       $cell{"mandatory"}=($requirelevel=~/(mandatory|requi|oblig|necess)/i);
      $cell{"frameworks"}=\@fwks;
      $cell{"label"}=ucfirst($requirelevel);
      $cell{"code"}=lc($requirelevel);
      push @levellist,\%cell;
    }
    $template->param("levelloop"=>\@levellist);
    $template->param("$op"=>1);
  } elsif ($op && $op eq 'updatestructure'){
    #Do updatedatabase And report
    my $execstring=C4::Context->config("intranetdir")."/updater/updatedatabase";
    undef $/;
    my $string= qx|$execstring 2>&1|;
    if ($string){
      $string=~s/\n|\r/<br \/>/g;
      $string=~s/(DBD::mysql.*? failed: .*? line [0-9]*.|=================.*?====================)/<font color=red>$1<\/font>/g;
      $template->param("updatereport"=>$string) ;
    }
    $template->param($op=>1)
  }elsif ($op && $op eq 'importdatastructure'){
    #Import data structure and show errors if any
	#Uses DBI to read the file [MJR 2007-07-01]
    my $dbh= DBI->connect("DBI:$info{dbms}:$info{dbname}:$info{hostname}".($info{port}?":$info{port}":""),$info{'user'}, $info{'password'});
      open(INPUT,"<kohastructure.sql");
      my $file=do{ local $/=undef; <INPUT>};
      my @commands=split(/;/,$file);
      pop @commands;   
      map { $dbh->do($_)} @commands;
      close(INPUT);
	$template->param("error"=>$dbh->errstr ,
	                 "$op"=> 1, );
    $dbh->disconnect;
  } else {
    #Check if there are enough tables.
	# Paul has cleaned up tables so reduced the count
    #I put it there because it implied a data import if condition was not satisfied.
    my $dbh= DBI->connect("DBI:$info{dbms}:$info{dbname}:$info{hostname}".($info{port}?":$info{port}":""),$info{'user'}, $info{'password'});
    my $rq=$dbh->prepare("SHOW TABLES FROM ".$info{'dbname'});
    $rq->execute;
    my $data=$rq->fetchall_arrayref({});
    my $count=scalar(@$data);
    if ($count < 70){
      $template->param("count"=>$count,"proposeimport"=>1);
    } else {
      $template->param("count"=>$count,"default"=>1);
    }
    $dbh->disconnect;
  }
}else {
  # LANGUAGE SELECTION page by default
  # using opendir + language Hash
  
  my $langavail = getTranslatedLanguages();
  my @languages;
  foreach (@$langavail){
	push @languages,{'value'=>$_->{'language_code'}, 'description'=>$_->{'language_name'} } if ($_->{'language_code'});
  }
  $template->param(languages=>\@languages);
  if ($dbh){
    my $rq=$dbh->prepare("SELECT * from systempreferences WHERE variable='Version'");
    if ($rq->execute){
      my ($version)=$rq->fetchrow;
      if ($version){
        $query->redirect("install.pl?step=3");
      }
    }  
  }
}
output_html_with_http_headers $query, $cookie, $template->output;
