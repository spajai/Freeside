<%

my $html_init = 
  'Agent types define groups of packages that you can then assign to'.
  ' particular agents.<BR><BR>'.
  qq!<A HREF="${p}edit/agent_type.cgi"><I>Add a new agent type</I></A><BR><BR>!;

my $count_query = 'SELECT COUNT(*) FROM agent_type';

#false laziness w/access_user.html
my $packages_sub = sub {
  my $agent_type = shift;

  [ map  {
           my $type_pkgs = $_;
           my $part_pkg = $type_pkgs->part_pkg;
           [
             {
               'data'  => $part_pkg->pkg. ' - '. $part_pkg->comment,
               'align' => 'left',
               'link'  => $p. 'edit/part_pkg.cgi?'. $type_pkgs->pkgpart,
             },
           ];
         }
    #sort {
    #     }
    grep {
           $_->part_pkg and ! $_->part_pkg->disabled
         }
    $agent_type->type_pkgs #XXX the method should order itself by something
  ];

};

my $link = [ $p.'edit/agent_type.cgi?', 'typenum' ];

%><%= include( 'elements/browse.html',
                 'title'   => 'Agent Types',
                 'menubar'     => [ #'Main menu' => $p,
                                    'Agents'    =>"${p}browse/agent.cgi",
                                  ],
                 'html_init'   => $html_init,
                 'name'        => 'agent types',
                 'query'       => { 'table'     => 'agent_type',
                                    'hashref'   => {},
                                    'extra_sql' => 'ORDER BY typenum', # 'ORDER BY atype',
                                  },
                 'count_query' => $count_query,
                 'header'      => [ '#',
                                    'Agent Type',
                                    'Packages',
                                  ],
                 'fields'      => [ 'typenum',
                                    'atype',
                                    $packages_sub,
                                  ],
                 'links'       => [ $link,
                                    $link,
                                    '',
                                  ],
             )
%>
