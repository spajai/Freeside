#!/usr/bin/perl -Tw
#
# $Id: cust_pkg.cgi,v 1.11 2000-07-17 16:45:41 ivan Exp $
#
# based on search/svc_acct.cgi ivan@sisd.com 98-jul-17
#
# $Log: cust_pkg.cgi,v $
# Revision 1.11  2000-07-17 16:45:41  ivan
# first shot at invoice browsing and some other cleanups
#
# Revision 1.10  2000/07/17 12:49:29  ivan
# better error message if a package isn't linked to a customer (that shouldn't happen)
#
# Revision 1.9  1999/07/17 10:38:52  ivan
# scott nelson <scott@ultimanet.com> noticed this mod_perl-triggered bug and
# gave me a great bugreport at the last rhythmethod
#
# Revision 1.8  1999/02/09 09:22:57  ivan
# visual and bugfixes
#
# Revision 1.7  1999/02/07 09:59:37  ivan
# more mod_perl fixes, and bugfixes Peter Wemm sent via email
#
# Revision 1.6  1999/01/19 05:14:13  ivan
# for mod_perl: no more top-level my() variables; use vars instead
# also the last s/create/new/;
#
# Revision 1.5  1999/01/18 09:41:38  ivan
# all $cgi->header calls now include ( '-expires' => 'now' ) for mod_perl
# (good idea anyway)
#
# Revision 1.4  1999/01/18 09:22:33  ivan
# changes to track email addresses for email invoicing
#
# Revision 1.3  1998/12/23 03:05:59  ivan
# $cgi->keywords instead of $cgi->query_string
#
# Revision 1.2  1998/12/17 09:41:09  ivan
# s/CGI::(Base|Request)/CGI.pm/;
#

use strict;
use vars qw ( $cgi @cust_pkg $sortby $query );
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use FS::UID qw(cgisuidsetup);
use FS::Record qw(qsearch qsearchs);
use FS::CGI qw(header eidiot popurl);
use FS::cust_pkg;
use FS::pkg_svc;
use FS::cust_svc;
use FS::cust_main;

$cgi = new CGI;
&cgisuidsetup($cgi);

($query) = $cgi->keywords;
#this tree is a little bit redundant
if ( $query eq 'pkgnum' ) {
  $sortby=\*pkgnum_sort;
  @cust_pkg=qsearch('cust_pkg',{});
} elsif ( $query eq 'APKG_pkgnum' ) {
  $sortby=\*pkgnum_sort;
  @cust_pkg=();
  #perhaps this should go in cust_pkg as a qsearch-like constructor?
  my($cust_pkg);
  foreach $cust_pkg (qsearch('cust_pkg',{})) {
    my($flag)=0;
    my($pkg_svc);
    PKG_SVC: 
    foreach $pkg_svc (qsearch('pkg_svc',{ 'pkgpart' => $cust_pkg->pkgpart })) {
      if ( $pkg_svc->quantity 
           > scalar(qsearch('cust_svc',{
               'pkgnum' => $cust_pkg->pkgnum,
               'svcpart' => $pkg_svc->svcpart,
             }))
         )
      {
        $flag=1;
        last PKG_SVC;
      }
    }
    push @cust_pkg, $cust_pkg if $flag;
  }
} else {
  die "Empty QUERY_STRING!";
}

if ( scalar(@cust_pkg) == 1 ) {
  my($pkgnum)=$cust_pkg[0]->pkgnum;
  print $cgi->redirect(popurl(2). "view/cust_pkg.cgi?$pkgnum");
  exit;
} elsif ( scalar(@cust_pkg) == 0 ) { #error
  eidiot("No packages found");
} else {
  my($total)=scalar(@cust_pkg);
  print $cgi->header( '-expires' => 'now' ), header('Package Search Results',''), <<END;
    $total matching packages found
    <TABLE BORDER=4 CELLSPACING=0 CELLPADDING=0>
      <TR>
        <TH>Package #</TH>
        <TH>Customer #</TH>
        <TH>Contact name</TH>
        <TH>Company</TH>
      </TR>
END

  my(%saw,$cust_pkg);
  foreach $cust_pkg (
    sort $sortby grep(!$saw{$_->pkgnum}++, @cust_pkg)
  ) {
    my($cust_main)=qsearchs('cust_main',{'custnum'=>$cust_pkg->custnum});
    my($pkgnum,$custnum,$name,$company)=(
      $cust_pkg->pkgnum,
      $cust_pkg->custnum,
      $cust_main ? $cust_main->last. ', '. $cust_main->first : '',
      $cust_main ? $cust_main->company : '',
    );
    my $p = popurl(2);
    print <<END;
    <TR>
      <TD><A HREF="${p}view/cust_pkg.cgi?$pkgnum"><FONT SIZE=-1>$pkgnum</FONT></A></TD>
END
    if ( $cust_main ) {
      print <<END;
      <TD><FONT SIZE=-1><A HREF="${p}view/cust_main.cgi?$custnum">$custnum</A></FONT></TD>
      <TD><FONT SIZE=-1><A HREF="${p}view/cust_main.cgi?$custnum">$name</A></FONT></TD>
      <TD><FONT SIZE=-1><A HREF="${p}view/cust_main.cgi?$custnum">$company</A></FONT></TD>
    </TR>
END
    } else {
      print <<END;
      <TD COLSPAN=3>WARNING: couldn't find cust_main.custnum $custnum (cust_pkg.pkgnum $pkgnum)</TD>
    </TR>
END
    }
  }
 
  print <<END;
    </TABLE>
  </BODY>
</HTML>
END
  exit;

}

sub pkgnum_sort {
  $a->getfield('pkgnum') <=> $b->getfield('pkgnum');
}

