%
%
%$cgi->param('svcnum') =~ /^(\d*)$/ or die "Illegal svcnum!";
%my $svcnum =$1;
%
%my $old = qsearchs('svc_forward',{'svcnum'=>$svcnum}) if $svcnum;
%
%my $new = new FS::svc_forward ( {
%  map {
%    ($_, scalar($cgi->param($_)));
%  } ( fields('svc_forward'), qw( pkgnum svcpart ) )
%} );
%
%my $error = '';
%if ( $svcnum ) {
%  $error = $new->replace($old);
%} else {
%  $error = $new->insert;
%  $svcnum = $new->getfield('svcnum');
%} 
%
%if ($error) {
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "svc_forward.cgi?". $cgi->query_string );
%} else {
%  print $cgi->redirect(popurl(3). "view/svc_forward.cgi?$svcnum");
%}
%
%

