package FS::Schema;

use vars qw(@ISA @EXPORT_OK $DEBUG $setup_hack %dbdef_cache);
use subs qw(reload_dbdef);
use Exporter;
use DBIx::DBSchema 0.25;
use DBIx::DBSchema::Table;
use DBIx::DBSchema::Column;
use DBIx::DBSchema::ColGroup::Unique;
use DBIx::DBSchema::ColGroup::Index;
use FS::UID qw(datasrc);

@ISA = qw(Exporter);
@EXPORT_OK = qw( dbdef dbdef_dist reload_dbdef );

$DEBUG = 0;
$me = '[FS::Schema]';

#ask FS::UID to run this stuff for us later
FS::UID->install_callback( sub {
  #$conf = new FS::Conf; 
  &reload_dbdef("/usr/local/etc/freeside/dbdef.". datasrc)
    unless $setup_hack; #$setup_hack needed now?
} );

=head1 NAME

FS::Schema - Freeside database schema

=head1 SYNOPSYS

    use FS::Schema qw(dbdef dbdef_dist reload_dbdef);

    $dbdef = reload_dbdef;
    $dbdef = reload_dbdef "/non/standard/filename";
    $dbdef = dbdef;
    $dbdef_dist = dbdef_dist;

=head1 DESCRIPTION

This class represents the database schema.

=head1 METHODS

=over 4

=item reload_dbdef([FILENAME])

Load a database definition (see L<DBIx::DBSchema>), optionally from a
non-default filename.  This command is executed at startup unless
I<$FS::Schema::setup_hack> is true.  Returns a DBIx::DBSchema object.

=cut

sub reload_dbdef {
  my $file = shift;

  unless ( exists $dbdef_cache{$file} ) {
    warn "[debug]$me loading dbdef for $file\n" if $DEBUG;
    $dbdef_cache{$file} = DBIx::DBSchema->load( $file )
                            or die "can't load database schema from $file";
  } else {
    warn "[debug]$me re-using cached dbdef for $file\n" if $DEBUG;
  }
  $dbdef = $dbdef_cache{$file};
}

=item dbdef

Returns the current database definition (represents the current database,
assuming it is up-to-date).  See L<DBIx::DBSchema>.

=cut

sub dbdef { $dbdef; }

=item dbdef_dist [ OPTION => VALUE ... ]

Returns the current canoical database definition as defined in this file.

=cut

sub dbdef_dist {

  ###
  # create a dbdef object from the old data structure
  ###

  my $tables_hashref = tables_hashref();

  #turn it into objects
  my $dbdef = new DBIx::DBSchema map {  
    my @columns;
    while (@{$tables_hashref->{$_}{'columns'}}) {
      my($name, $type, $null, $length) =
        splice @{$tables_hashref->{$_}{'columns'}}, 0, 4;
      push @columns, new DBIx::DBSchema::Column ( $name,$type,$null,$length );
    }
    DBIx::DBSchema::Table->new(
      $_,
      $tables_hashref->{$_}{'primary_key'},
      DBIx::DBSchema::ColGroup::Unique->new($tables_hashref->{$_}{'unique'}),
      DBIx::DBSchema::ColGroup::Index->new($tables_hashref->{$_}{'index'}),
      @columns,
    );
  } keys %$tables_hashref;

  if ( $DEBUG ) {
    warn "[debug]$me initial dbdef_dist created ($dbdef) with tables:\n";
    warn "[debug]$me   $_\n" foreach $dbdef->tables;
  }
  
  my $cust_main = $dbdef->table('cust_main');
  #unless ($ship) { #remove ship_ from cust_main
  #  $cust_main->delcolumn($_) foreach ( grep /^ship_/, $cust_main->columns );
  #} else { #add indices
    push @{$cust_main->index->lol_ref},
      map { [ "ship_$_" ] } qw( last company daytime night fax );
  #}
  
  #add radius attributes to svc_acct
  #
  #my($svc_acct)=$dbdef->table('svc_acct');
  # 
  #my($attribute);
  #foreach $attribute (@attributes) {
  #  $svc_acct->addcolumn ( new DBIx::DBSchema::Column (
  #    'radius_'. $attribute,
  #    'varchar',
  #    'NULL',
  #    $char_d,
  #  ));
  #}
  # 
  #foreach $attribute (@check_attributes) {
  #  $svc_acct->addcolumn( new DBIx::DBSchema::Column (
  #    'rc_'. $attribute,
  #    'varchar',
  #    'NULL',
  #    $char_d,
  #  ));
  #}

  #create history tables (false laziness w/create-history-tables)
  foreach my $table (
    grep { ! /^clientapi_session/ }
    grep { ! /^h_/ }
    $dbdef->tables
  ) {
    my $tableobj = $dbdef->table($table)
      or die "unknown table $table";
  
    die "unique->lol_ref undefined for $table"
      unless defined $tableobj->unique->lol_ref;
    die "index->lol_ref undefined for $table"
      unless defined $tableobj->index->lol_ref;
  
    my $h_tableobj = DBIx::DBSchema::Table->new( {
      name        => "h_$table",
      primary_key => 'historynum',
      unique      => DBIx::DBSchema::ColGroup::Unique->new( [] ),
      'index'     => DBIx::DBSchema::ColGroup::Index->new( [
                       @{$tableobj->unique->lol_ref},
                       @{$tableobj->index->lol_ref}
                     ] ),
      columns     => [
                       DBIx::DBSchema::Column->new( {
                         'name'    => 'historynum',
                         'type'    => 'serial',
                         'null'    => 'NOT NULL',
                         'length'  => '',
                         'default' => '',
                         'local'   => '',
                       } ),
                       DBIx::DBSchema::Column->new( {
                         'name'    => 'history_date',
                         'type'    => 'int',
                         'null'    => 'NULL',
                         'length'  => '',
                         'default' => '',
                         'local'   => '',
                       } ),
                       DBIx::DBSchema::Column->new( {
                         'name'    => 'history_user',
                         'type'    => 'varchar',
                         'null'    => 'NOT NULL',
                         'length'  => '80',
                         'default' => '',
                         'local'   => '',
                       } ),
                       DBIx::DBSchema::Column->new( {
                         'name'    => 'history_action',
                         'type'    => 'varchar',
                         'null'    => 'NOT NULL',
                         'length'  => '80',
                         'default' => '',
                         'local'   => '',
                       } ),
                       map {
                         my $column = $tableobj->column($_);
  
                         #clone so as to not disturb the original
                         $column = DBIx::DBSchema::Column->new( {
                           map { $_ => $column->$_() }
                             qw( name type null length default local )
                         } );
  
                         if ( $column->type eq 'serial' ) {
                           $column->type('int');
                           $column->null('NULL');
                         }
                         #$column->default('')
                         #  if $column->default =~ /^nextval\(/i;
                         #( my $local = $column->local ) =~ s/AUTO_INCREMENT//i;
                         #$column->local($local);
                         $column;
                       } $tableobj->columns
                     ],
    } );
    $dbdef->addtable($h_tableobj);
  }

  $dbdef;

}

sub tables_hashref {

  my $char_d = 80; #default maxlength for text fields

  #my(@date_type)  = ( 'timestamp', '', ''     );
  my @date_type  = ( 'int', 'NULL', ''     );
  my @perl_type = ( 'text', 'NULL', ''  ); 
  my @money_type = ( 'decimal',   '', '10,2' );

  my $username_len = 32; #usernamemax config file

  return {

    'agent' => {
      'columns' => [
        'agentnum', 'serial',            '',     '',
        'agent',    'varchar',           '',     $char_d,
        'typenum',  'int',            '',     '',
        'freq',     'int',       'NULL', '',
        'prog',     @perl_type,
        'disabled',     'char', 'NULL', 1,
        'username', 'varchar',       'NULL',     $char_d,
        '_password','varchar',       'NULL',     $char_d,
        'ticketing_queueid', 'int', 'NULL', '',
      ],
      'primary_key' => 'agentnum',
      'unique' => [],
      'index' => [ ['typenum'], ['disabled'] ],
    },

    'agent_type' => {
      'columns' => [
        'typenum',   'serial',  '', '',
        'atype',     'varchar', '', $char_d,
      ],
      'primary_key' => 'typenum',
      'unique' => [],
      'index' => [],
    },

    'type_pkgs' => {
      'columns' => [
        'typepkgnum', 'serial', '', '',
        'typenum',   'int',  '', '',
        'pkgpart',   'int',  '', '',
      ],
      'primary_key' => 'typepkgnum',
      'unique' => [ ['typenum', 'pkgpart'] ],
      'index' => [ ['typenum'] ],
    },

    'cust_bill' => {
      'columns' => [
        'invnum',    'serial',  '', '',
        'custnum',   'int',  '', '',
        '_date',     @date_type,
        'charged',   @money_type,
        'printed',   'int',  '', '',
        'closed',    'char', 'NULL', 1,
      ],
      'primary_key' => 'invnum',
      'unique' => [],
      'index' => [ ['custnum'], ['_date'] ],
    },

    'cust_bill_event' => {
      'columns' => [
        'eventnum',    'serial',  '', '',
        'invnum',   'int',  '', '',
        'eventpart',   'int',  '', '',
        '_date',     @date_type,
        'status', 'varchar', '', $char_d,
        'statustext', 'text', 'NULL', '',
      ],
      'primary_key' => 'eventnum',
      #no... there are retries now #'unique' => [ [ 'eventpart', 'invnum' ] ],
      'unique' => [],
      'index' => [ ['invnum'], ['status'] ],
    },

    'part_bill_event' => {
      'columns' => [
        'eventpart',    'serial',  '', '',
        'payby',       'char',  '', 4,
        'event',       'varchar',           '',     $char_d,
        'eventcode',    @perl_type,
        'seconds',     'int', 'NULL', '',
        'weight',      'int', '', '',
        'plan',       'varchar', 'NULL', $char_d,
        'plandata',   'text', 'NULL', '',
        'disabled',     'char', 'NULL', 1,
      ],
      'primary_key' => 'eventpart',
      'unique' => [],
      'index' => [ ['payby'], ['disabled'], ],
    },

    'cust_bill_pkg' => {
      'columns' => [
        'billpkgnum', 'serial', '', '',
        'pkgnum',  'int', '', '',
        'invnum',  'int', '', '',
        'setup',   @money_type,
        'recur',   @money_type,
        'sdate',   @date_type,
        'edate',   @date_type,
        'itemdesc', 'varchar', 'NULL', $char_d,
      ],
      'primary_key' => 'billpkgnum',
      'unique' => [],
      'index' => [ ['invnum'], [ 'pkgnum' ] ],
    },

    'cust_bill_pkg_detail' => {
      'columns' => [
        'detailnum', 'serial', '', '',
        'pkgnum',  'int', '', '',
        'invnum',  'int', '', '',
        'detail',  'varchar', '', $char_d,
      ],
      'primary_key' => 'detailnum',
      'unique' => [],
      'index' => [ [ 'pkgnum', 'invnum' ] ],
    },

    'cust_credit' => {
      'columns' => [
        'crednum',  'serial', '', '',
        'custnum',  'int', '', '',
        '_date',    @date_type,
        'amount',   @money_type,
        'otaker',   'varchar', '', 32,
        'reason',   'text', 'NULL', '',
        'closed',    'char', 'NULL', 1,
      ],
      'primary_key' => 'crednum',
      'unique' => [],
      'index' => [ ['custnum'] ],
    },

    'cust_credit_bill' => {
      'columns' => [
        'creditbillnum', 'serial', '', '',
        'crednum',  'int', '', '',
        'invnum',  'int', '', '',
        '_date',    @date_type,
        'amount',   @money_type,
      ],
      'primary_key' => 'creditbillnum',
      'unique' => [],
      'index' => [ ['crednum'], ['invnum'] ],
    },

    'cust_main' => {
      'columns' => [
        'custnum',  'serial',  '',     '',
        'agentnum', 'int',  '',     '',
#        'titlenum', 'int',  'NULL',   '',
        'last',     'varchar', '',     $char_d,
#        'middle',   'varchar', 'NULL', $char_d,
        'first',    'varchar', '',     $char_d,
        'ss',       'varchar', 'NULL', 11,
        'company',  'varchar', 'NULL', $char_d,
        'address1', 'varchar', '',     $char_d,
        'address2', 'varchar', 'NULL', $char_d,
        'city',     'varchar', '',     $char_d,
        'county',   'varchar', 'NULL', $char_d,
        'state',    'varchar', 'NULL', $char_d,
        'zip',      'varchar', 'NULL', 10,
        'country',  'char', '',     2,
        'daytime',  'varchar', 'NULL', 20,
        'night',    'varchar', 'NULL', 20,
        'fax',      'varchar', 'NULL', 12,
        'ship_last',     'varchar', 'NULL', $char_d,
#        'ship_middle',   'varchar', 'NULL', $char_d,
        'ship_first',    'varchar', 'NULL', $char_d,
        'ship_company',  'varchar', 'NULL', $char_d,
        'ship_address1', 'varchar', 'NULL', $char_d,
        'ship_address2', 'varchar', 'NULL', $char_d,
        'ship_city',     'varchar', 'NULL', $char_d,
        'ship_county',   'varchar', 'NULL', $char_d,
        'ship_state',    'varchar', 'NULL', $char_d,
        'ship_zip',      'varchar', 'NULL', 10,
        'ship_country',  'char', 'NULL', 2,
        'ship_daytime',  'varchar', 'NULL', 20,
        'ship_night',    'varchar', 'NULL', 20,
        'ship_fax',      'varchar', 'NULL', 12,
        'payby',    'char', '',     4,
        'payinfo',  'varchar', 'NULL', 512,
        'paycvv',   'varchar', 'NULL', 512,
	'paymask', 'varchar', 'NULL', $char_d,
        #'paydate',  @date_type,
        'paydate',  'varchar', 'NULL', 10,
        'paystart_month', 'int', 'NULL', '',
        'paystart_year',  'int', 'NULL', '',
        'payissue', 'varchar', 'NULL', 2,
        'payname',  'varchar', 'NULL', $char_d,
        'payip',    'varchar', 'NULL', 15,
        'tax',      'char', 'NULL', 1,
        'otaker',   'varchar', '',    32,
        'refnum',   'int',  '',     '',
        'referral_custnum', 'int',  'NULL', '',
        'comments', 'text', 'NULL', '',
      ],
      'primary_key' => 'custnum',
      'unique' => [],
      #'index' => [ ['last'], ['company'] ],
      'index' => [ ['last'], [ 'company' ], [ 'referral_custnum' ],
                   [ 'daytime' ], [ 'night' ], [ 'fax' ], [ 'refnum' ],
                   [ 'ship_last' ], [ 'ship_company' ],
                   [ 'county' ], [ 'state' ], [ 'country' ]
                 ],
    },

    'cust_main_invoice' => {
      'columns' => [
        'destnum',  'serial',  '',     '',
        'custnum',  'int',  '',     '',
        'dest',     'varchar', '',  $char_d,
      ],
      'primary_key' => 'destnum',
      'unique' => [],
      'index' => [ ['custnum'], ],
    },

    'cust_main_county' => { #county+state+country are checked off the
                            #cust_main_county for validation and to provide
                            # a tax rate.
      'columns' => [
        'taxnum',   'serial',   '',    '',
        'state',    'varchar',  'NULL',    $char_d,
        'county',   'varchar',  'NULL',    $char_d,
        'country',  'char',  '', 2, 
        'taxclass',   'varchar', 'NULL', $char_d,
        'exempt_amount', @money_type,
        'tax',      'real',  '',    '', #tax %
        'taxname',  'varchar',  'NULL',    $char_d,
        'setuptax',  'char', 'NULL', 1, # Y = setup tax exempt
        'recurtax',  'char', 'NULL', 1, # Y = recur tax exempt
      ],
      'primary_key' => 'taxnum',
      'unique' => [],
  #    'unique' => [ ['taxnum'], ['state', 'county'] ],
      'index' => [ [ 'county' ], [ 'state' ], [ 'country' ] ],
    },

    'cust_pay' => {
      'columns' => [
        'paynum',   'serial',    '',   '',
        #now cust_bill_pay #'invnum',   'int',    '',   '',
        'custnum',  'int',    '',   '',
        'paid',     @money_type,
        '_date',    @date_type,
        'payby',    'char',   '',     4, # CARD/BILL/COMP, should be index into
                                         # payment type table.
        'payinfo',  'varchar',   'NULL', $char_d,  #see cust_main above
        'paybatch', 'varchar',   'NULL', $char_d, #for auditing purposes.
        'closed',    'char', 'NULL', 1,
      ],
      'primary_key' => 'paynum',
      'unique' => [],
      'index' => [ [ 'custnum' ], [ 'paybatch' ], [ 'payby' ], [ '_date' ] ],
    },

    'cust_pay_void' => {
      'columns' => [
        'paynum',    'int',    '',   '',
        'custnum',   'int',    '',   '',
        'paid',      @money_type,
        '_date',     @date_type,
        'payby',     'char',   '',     4, # CARD/BILL/COMP, should be index into
                                          # payment type table.
        'payinfo',   'varchar',   'NULL', $char_d,  #see cust_main above
        'paybatch',  'varchar',   'NULL', $char_d, #for auditing purposes.
        'closed',    'char', 'NULL', 1,
        'void_date', @date_type,
        'reason',    'varchar',   'NULL', $char_d,
        'otaker',   'varchar', '', 32,
      ],
      'primary_key' => 'paynum',
      'unique' => [],
      'index' => [ [ 'custnum' ] ],
    },

    'cust_bill_pay' => {
      'columns' => [
        'billpaynum', 'serial',     '',   '',
        'invnum',  'int',     '',   '',
        'paynum',  'int',     '',   '',
        'amount',  @money_type,
        '_date',   @date_type
      ],
      'primary_key' => 'billpaynum',
      'unique' => [],
      'index' => [ [ 'paynum' ], [ 'invnum' ] ],
    },

    'cust_pay_batch' => { #what's this used for again?  list of customers
                          #in current CARD batch? (necessarily CARD?)
      'columns' => [
        'paybatchnum',   'serial',    '',   '',
        'invnum',   'int',    '',   '',
        'custnum',   'int',    '',   '',
        'last',     'varchar', '',     $char_d,
        'first',    'varchar', '',     $char_d,
        'address1', 'varchar', '',     $char_d,
        'address2', 'varchar', 'NULL', $char_d,
        'city',     'varchar', '',     $char_d,
        'state',    'varchar', 'NULL', $char_d,
        'zip',      'varchar', 'NULL', 10,
        'country',  'char', '',     2,
#        'trancode', 'int', '', '',
        'cardnum',  'varchar', '',     16,
        #'exp',      @date_type,
        'exp',      'varchar', '',     11,
        'payname',  'varchar', 'NULL', $char_d,
        'amount',   @money_type,
      ],
      'primary_key' => 'paybatchnum',
      'unique' => [],
      'index' => [ ['invnum'], ['custnum'] ],
    },

    'cust_pkg' => {
      'columns' => [
        'pkgnum',    'serial',    '',   '',
        'custnum',   'int',    '',   '',
        'pkgpart',   'int',    '',   '',
        'otaker',    'varchar', '', 32,
        'setup',     @date_type,
        'bill',      @date_type,
        'last_bill', @date_type,
        'susp',      @date_type,
        'cancel',    @date_type,
        'expire',    @date_type,
        'manual_flag', 'char', 'NULL', 1,
      ],
      'primary_key' => 'pkgnum',
      'unique' => [],
      'index' => [ ['custnum'], ['pkgpart'] ],
    },

    'cust_refund' => {
      'columns' => [
        'refundnum',    'serial',    '',   '',
        #now cust_credit_refund #'crednum',      'int',    '',   '',
        'custnum',  'int',    '',   '',
        '_date',        @date_type,
        'refund',       @money_type,
        'otaker',       'varchar',   '',   32,
        'reason',       'varchar',   '',   $char_d,
        'payby',        'char',   '',     4, # CARD/BILL/COMP, should be index
                                             # into payment type table.
        'payinfo',      'varchar',   'NULL', $char_d,  #see cust_main above
        'paybatch',     'varchar',   'NULL', $char_d,
        'closed',    'char', 'NULL', 1,
      ],
      'primary_key' => 'refundnum',
      'unique' => [],
      'index' => [],
    },

    'cust_credit_refund' => {
      'columns' => [
        'creditrefundnum', 'serial',     '',   '',
        'crednum',  'int',     '',   '',
        'refundnum',  'int',     '',   '',
        'amount',  @money_type,
        '_date',   @date_type
      ],
      'primary_key' => 'creditrefundnum',
      'unique' => [],
      'index' => [ [ 'crednum', 'refundnum' ] ],
    },


    'cust_svc' => {
      'columns' => [
        'svcnum',    'serial',    '',   '',
        'pkgnum',    'int',    'NULL',   '',
        'svcpart',   'int',    '',   '',
      ],
      'primary_key' => 'svcnum',
      'unique' => [],
      'index' => [ ['svcnum'], ['pkgnum'], ['svcpart'] ],
    },

    'part_pkg' => {
      'columns' => [
        'pkgpart',    'serial',    '',   '',
        'pkg',        'varchar',   '',   $char_d,
        'comment',    'varchar',   '',   $char_d,
        'promo_code', 'varchar', 'NULL', $char_d,
        'setup',      @perl_type,
        'freq',       'varchar',   '',   $char_d,  #billing frequency
        'recur',      @perl_type,
        'setuptax',  'char', 'NULL', 1,
        'recurtax',  'char', 'NULL', 1,
        'plan',       'varchar', 'NULL', $char_d,
        'plandata',   'text', 'NULL', '',
        'disabled',   'char', 'NULL', 1,
        'taxclass',   'varchar', 'NULL', $char_d,
      ],
      'primary_key' => 'pkgpart',
      'unique' => [],
      'index' => [ [ 'promo_code' ], [ 'disabled' ] ],
    },

#    'part_title' => {
#      'columns' => [
#        'titlenum',   'int',    '',   '',
#        'title',      'varchar',   '',   $char_d,
#      ],
#      'primary_key' => 'titlenum',
#      'unique' => [ [] ],
#      'index' => [ [] ],
#    },

    'pkg_svc' => {
      'columns' => [
        'pkgsvcnum',  'serial', '',  '',
        'pkgpart',    'int',    '',   '',
        'svcpart',    'int',    '',   '',
        'quantity',   'int',    '',   '',
        'primary_svc','char', 'NULL',  1,
      ],
      'primary_key' => 'pkgsvcnum',
      'unique' => [ ['pkgpart', 'svcpart'] ],
      'index' => [ ['pkgpart'] ],
    },

    'part_referral' => {
      'columns' => [
        'refnum',   'serial',    '',   '',
        'referral', 'varchar',   '',   $char_d,
        'disabled',     'char', 'NULL', 1,
      ],
      'primary_key' => 'refnum',
      'unique' => [],
      'index' => [ ['disabled'] ],
    },

    'part_svc' => {
      'columns' => [
        'svcpart',    'serial',    '',   '',
        'svc',        'varchar',   '',   $char_d,
        'svcdb',      'varchar',   '',   $char_d,
        'disabled',   'char',  'NULL',   1,
      ],
      'primary_key' => 'svcpart',
      'unique' => [],
      'index' => [ [ 'disabled' ] ],
    },

    'part_svc_column' => {
      'columns' => [
        'columnnum',   'serial',         '', '',
        'svcpart',     'int',         '', '',
        'columnname',  'varchar',     '', 64,
        'columnvalue', 'varchar', 'NULL', $char_d,
        'columnflag',  'char',    'NULL', 1, 
      ],
      'primary_key' => 'columnnum',
      'unique' => [ [ 'svcpart', 'columnname' ] ],
      'index' => [ [ 'svcpart' ] ],
    },

    #(this should be renamed to part_pop)
    'svc_acct_pop' => {
      'columns' => [
        'popnum',    'serial',    '',   '',
        'city',      'varchar',   '',   $char_d,
        'state',     'varchar',   '',   $char_d,
        'ac',        'char',   '',   3,
        'exch',      'char',   '',   3,
        'loc',       'char',   'NULL',   4, #NULL for legacy purposes
      ],
      'primary_key' => 'popnum',
      'unique' => [],
      'index' => [ [ 'state' ] ],
    },

    'part_pop_local' => {
      'columns' => [
        'localnum',  'serial',     '',     '',
        'popnum',    'int',     '',     '',
        'city',      'varchar', 'NULL', $char_d,
        'state',     'char',    'NULL', 2,
        'npa',       'char',    '',     3,
        'nxx',       'char',    '',     3,
      ],
      'primary_key' => 'localnum',
      'unique' => [],
      'index' => [ [ 'npa', 'nxx' ], [ 'popnum' ] ],
    },

    'svc_acct' => {
      'columns' => [
        'svcnum',    'int',    '',   '',
        'username',  'varchar',   '',   $username_len, #unique (& remove dup code)
        '_password', 'varchar',   '',   72, #13 for encryped pw's plus ' *SUSPENDED* (md5 passwords can be 34, blowfish 60)
        'sec_phrase', 'varchar',  'NULL',   $char_d,
        'popnum',    'int',    'NULL',   '',
        'uid',       'int', 'NULL',   '',
        'gid',       'int', 'NULL',   '',
        'finger',    'varchar',   'NULL',   $char_d,
        'dir',       'varchar',   'NULL',   $char_d,
        'shell',     'varchar',   'NULL',   $char_d,
        'quota',     'varchar',   'NULL',   $char_d,
        'slipip',    'varchar',   'NULL',   15, #four TINYINTs, bah.
        'seconds',   'int', 'NULL',   '', #uhhhh
        'domsvc',    'int', '',   '',
      ],
      'primary_key' => 'svcnum',
      #'unique' => [ [ 'username', 'domsvc' ] ],
      'unique' => [],
      'index' => [ ['username'], ['domsvc'] ],
    },

    #'svc_charge' => {
    #  'columns' => [
    #    'svcnum',    'int',    '',   '',
    #    'amount',    @money_type,
    #  ],
    #  'primary_key' => 'svcnum',
    #  'unique' => [ [] ],
    #  'index' => [ [] ],
    #},

    'svc_domain' => {
      'columns' => [
        'svcnum',    'int',    '',   '',
        'domain',    'varchar',    '',   $char_d,
        'catchall',  'int', 'NULL',    '',
      ],
      'primary_key' => 'svcnum',
      'unique' => [ ['domain'] ],
      'index' => [],
    },

    'domain_record' => {
      'columns' => [
        'recnum',    'serial',     '',  '',
        'svcnum',    'int',     '',  '',
        #'reczone',   'varchar', '',  $char_d,
        'reczone',   'varchar', '',  255,
        'recaf',     'char',    '',  2,
        'rectype',   'varchar',    '',  5,
        #'recdata',   'varchar', '',  $char_d,
        'recdata',   'varchar', '',  255,
      ],
      'primary_key' => 'recnum',
      'unique'      => [],
      'index'       => [ ['svcnum'] ],
    },

    'svc_forward' => {
      'columns' => [
        'svcnum',   'int',            '',   '',
        'srcsvc',   'int',        'NULL',   '',
        'src',      'varchar',    'NULL',  255,
        'dstsvc',   'int',        'NULL',   '',
        'dst',      'varchar',    'NULL',  255,
      ],
      'primary_key' => 'svcnum',
      'unique'      => [],
      'index'       => [ ['srcsvc'], ['dstsvc'] ],
    },

    'svc_www' => {
      'columns' => [
        'svcnum',   'int',    '',  '',
        'recnum',   'int',    '',  '',
        'usersvc',  'int',    '',  '',
      ],
      'primary_key' => 'svcnum',
      'unique'      => [],
      'index'       => [],
    },

    #'svc_wo' => {
    #  'columns' => [
    #    'svcnum',    'int',    '',   '',
    #    'svcnum',    'int',    '',   '',
    #    'svcnum',    'int',    '',   '',
    #    'worker',    'varchar',   '',   $char_d,
    #    '_date',     @date_type,
    #  ],
    #  'primary_key' => 'svcnum',
    #  'unique' => [ [] ],
    #  'index' => [ [] ],
    #},

    'prepay_credit' => {
      'columns' => [
        'prepaynum',   'serial',     '',   '',
        'identifier',  'varchar', '', $char_d,
        'amount',      @money_type,
        'seconds',     'int',     'NULL', '',
        'agentnum',    'int',     'NULL', '',
      ],
      'primary_key' => 'prepaynum',
      'unique'      => [ ['identifier'] ],
      'index'       => [],
    },

    'port' => {
      'columns' => [
        'portnum',  'serial',     '',   '',
        'ip',       'varchar', 'NULL', 15,
        'nasport',  'int',     'NULL', '',
        'nasnum',   'int',     '',   '',
      ],
      'primary_key' => 'portnum',
      'unique'      => [],
      'index'       => [],
    },

    'nas' => {
      'columns' => [
        'nasnum',   'serial',     '',    '',
        'nas',      'varchar', '',    $char_d,
        'nasip',    'varchar', '',    15,
        'nasfqdn',  'varchar', '',    $char_d,
        'last',     'int',     '',    '',
      ],
      'primary_key' => 'nasnum',
      'unique'      => [ [ 'nas' ], [ 'nasip' ] ],
      'index'       => [ [ 'last' ] ],
    },

    'session' => {
      'columns' => [
        'sessionnum', 'serial',       '',   '',
        'portnum',    'int',       '',   '',
        'svcnum',     'int',       '',   '',
        'login',      @date_type,
        'logout',     @date_type,
      ],
      'primary_key' => 'sessionnum',
      'unique'      => [],
      'index'       => [ [ 'portnum' ] ],
    },

    'queue' => {
      'columns' => [
        'jobnum', 'serial', '', '',
        'job', 'text', '', '',
        '_date', 'int', '', '',
        'status', 'varchar', '', $char_d,
        'statustext', 'text', 'NULL', '',
        'svcnum', 'int', 'NULL', '',
      ],
      'primary_key' => 'jobnum',
      'unique'      => [],
      'index'       => [ [ 'svcnum' ], [ 'status' ] ],
    },

    'queue_arg' => {
      'columns' => [
        'argnum', 'serial', '', '',
        'jobnum', 'int', '', '',
        'arg', 'text', 'NULL', '',
      ],
      'primary_key' => 'argnum',
      'unique'      => [],
      'index'       => [ [ 'jobnum' ] ],
    },

    'queue_depend' => {
      'columns' => [
        'dependnum', 'serial', '', '',
        'jobnum', 'int', '', '',
        'depend_jobnum', 'int', '', '',
      ],
      'primary_key' => 'dependnum',
      'unique'      => [],
      'index'       => [ [ 'jobnum' ], [ 'depend_jobnum' ] ],
    },

    'export_svc' => {
      'columns' => [
        'exportsvcnum' => 'serial', '', '',
        'exportnum'    => 'int', '', '',
        'svcpart'      => 'int', '', '',
      ],
      'primary_key' => 'exportsvcnum',
      'unique'      => [ [ 'exportnum', 'svcpart' ] ],
      'index'       => [ [ 'exportnum' ], [ 'svcpart' ] ],
    },

    'part_export' => {
      'columns' => [
        'exportnum', 'serial', '', '',
        #'svcpart',   'int', '', '',
        'machine', 'varchar', '', $char_d,
        'exporttype', 'varchar', '', $char_d,
        'nodomain',     'char', 'NULL', 1,
      ],
      'primary_key' => 'exportnum',
      'unique'      => [],
      'index'       => [ [ 'machine' ], [ 'exporttype' ] ],
    },

    'part_export_option' => {
      'columns' => [
        'optionnum', 'serial', '', '',
        'exportnum', 'int', '', '',
        'optionname', 'varchar', '', $char_d,
        'optionvalue', 'text', 'NULL', '',
      ],
      'primary_key' => 'optionnum',
      'unique'      => [],
      'index'       => [ [ 'exportnum' ], [ 'optionname' ] ],
    },

    'radius_usergroup' => {
      'columns' => [
        'usergroupnum', 'serial', '', '',
        'svcnum',       'int', '', '',
        'groupname',    'varchar', '', $char_d,
      ],
      'primary_key' => 'usergroupnum',
      'unique'      => [],
      'index'       => [ [ 'svcnum' ], [ 'groupname' ] ],
    },

    'msgcat' => {
      'columns' => [
        'msgnum', 'serial', '', '',
        'msgcode', 'varchar', '', $char_d,
        'locale', 'varchar', '', 16,
        'msg', 'text', '', '',
      ],
      'primary_key' => 'msgnum',
      'unique'      => [ [ 'msgcode', 'locale' ] ],
      'index'       => [],
    },

    'cust_tax_exempt' => {
      'columns' => [
        'exemptnum', 'serial', '', '',
        'custnum',   'int', '', '',
        'taxnum',    'int', '', '',
        'year',      'int', '', '',
        'month',     'int', '', '',
        'amount',   @money_type,
      ],
      'primary_key' => 'exemptnum',
      'unique'      => [ [ 'custnum', 'taxnum', 'year', 'month' ] ],
      'index'       => [],
    },

    'router' => {
      'columns' => [
        'routernum', 'serial', '', '',
        'routername', 'varchar', '', $char_d,
        'svcnum', 'int', 'NULL', '',
      ],
      'primary_key' => 'routernum',
      'unique'      => [],
      'index'       => [],
    },

    'part_svc_router' => {
      'columns' => [
        'svcrouternum', 'serial', '', '',
        'svcpart', 'int', '', '',
	'routernum', 'int', '', '',
      ],
      'primary_key' => 'svcrouternum',
      'unique'      => [],
      'index'       => [],
    },

    'addr_block' => {
      'columns' => [
        'blocknum', 'serial', '', '',
	'routernum', 'int', '', '',
        'ip_gateway', 'varchar', '', 15,
        'ip_netmask', 'int', '', '',
      ],
      'primary_key' => 'blocknum',
      'unique'      => [ [ 'blocknum', 'routernum' ] ],
      'index'       => [],
    },

    'svc_broadband' => {
      'columns' => [
        'svcnum', 'int', '', '',
        'blocknum', 'int', '', '',
        'speed_up', 'int', '', '',
        'speed_down', 'int', '', '',
        'ip_addr', 'varchar', '', 15,
      ],
      'primary_key' => 'svcnum',
      'unique'      => [],
      'index'       => [],
    },

    'part_virtual_field' => {
      'columns' => [
        'vfieldpart', 'int', '', '',
        'dbtable', 'varchar', '', 32,
        'name', 'varchar', '', 32,
        'check_block', 'text', 'NULL', '',
        'length', 'int', 'NULL', '',
        'list_source', 'text', 'NULL', '',
        'label', 'varchar', 'NULL', 80,
      ],
      'primary_key' => 'vfieldpart',
      'unique' => [],
      'index' => [],
    },

    'virtual_field' => {
      'columns' => [
        'vfieldnum', 'serial', '', '',
        'recnum', 'int', '', '',
        'vfieldpart', 'int', '', '',
        'value', 'varchar', '', 128,
      ],
      'primary_key' => 'vfieldnum',
      'unique' => [ [ 'vfieldpart', 'recnum' ] ],
      'index' => [],
    },

    'acct_snarf' => {
      'columns' => [
        'snarfnum',  'int', '', '',
        'svcnum',    'int', '', '',
        'machine',   'varchar', '', 255,
        'protocol',  'varchar', '', $char_d,
        'username',  'varchar', '', $char_d,
        '_password', 'varchar', '', $char_d,
      ],
      'primary_key' => 'snarfnum',
      'unique' => [],
      'index'  => [ [ 'svcnum' ] ],
    },

    'svc_external' => {
      'columns' => [
        'svcnum', 'int', '', '',
        'id',     'int', 'NULL', '',
        'title',  'varchar', 'NULL', $char_d,
      ],
      'primary_key' => 'svcnum',
      'unique'      => [],
      'index'       => [],
    },

    'cust_pay_refund' => {
      'columns' => [
        'payrefundnum', 'serial', '', '',
        'paynum',  'int', '', '',
        'refundnum',  'int', '', '',
        '_date',    @date_type,
        'amount',   @money_type,
      ],
      'primary_key' => 'payrefundnum',
      'unique' => [],
      'index' => [ ['paynum'], ['refundnum'] ],
    },

    'part_pkg_option' => {
      'columns' => [
        'optionnum', 'serial', '', '',
        'pkgpart', 'int', '', '',
        'optionname', 'varchar', '', $char_d,
        'optionvalue', 'text', 'NULL', '',
      ],
      'primary_key' => 'optionnum',
      'unique'      => [],
      'index'       => [ [ 'pkgpart' ], [ 'optionname' ] ],
    },

    'rate' => {
      'columns' => [
        'ratenum',  'serial', '', '',
        'ratename', 'varchar', '', $char_d,
      ],
      'primary_key' => 'ratenum',
      'unique'      => [],
      'index'       => [],
    },

    'rate_detail' => {
      'columns' => [
        'ratedetailnum',   'serial', '', '',
        'ratenum',         'int',     '', '',
        'orig_regionnum',  'int', 'NULL', '',
        'dest_regionnum',  'int',     '', '',
        'min_included',    'int',     '', '',
        'min_charge',      @money_type,
        'sec_granularity', 'int',     '', '',
        #time period (link to table of periods)?
      ],
      'primary_key' => 'ratedetailnum',
      'unique'      => [ [ 'ratenum', 'orig_regionnum', 'dest_regionnum' ] ],
      'index'       => [ [ 'ratenum', 'dest_regionnum' ] ],
    },

    'rate_region' => {
      'columns' => [
        'regionnum',   'serial',      '', '',
        'regionname',  'varchar',     '', $char_d,
      ],
      'primary_key' => 'regionnum',
      'unique'      => [],
      'index'       => [],
    },

    'rate_prefix' => {
      'columns' => [
        'prefixnum',   'serial',    '', '',
        'regionnum',   'int',       '', '',,
        'countrycode', 'varchar',     '', 3,
        'npa',         'varchar', 'NULL', 6,
        'nxx',         'varchar', 'NULL', 3,
      ],
      'primary_key' => 'prefixnum',
      'unique'      => [],
      'index'       => [ [ 'countrycode' ], [ 'regionnum' ] ],
    },

    'reg_code' => {
      'columns' => [
        'codenum',   'serial',    '', '',
        'code',      'varchar',   '', $char_d,
        'agentnum',  'int',       '', '',
      ],
      'primary_key' => 'codenum',
      'unique'      => [ [ 'agentnum', 'code' ] ],
      'index'       => [ [ 'agentnum' ] ],
    },

    'reg_code_pkg' => {
      'columns' => [
        'codepkgnum', 'serial', '', '',
        'codenum',   'int',    '', '',
        'pkgpart',   'int',    '', '',
      ],
      'primary_key' => 'codepkgnum',
      'unique'      => [ [ 'codenum', 'pkgpart' ] ],
      'index'       => [ [ 'codenum' ] ],
    },

    'clientapi_session' => {
      'columns' => [
        'sessionnum',  'serial',  '', '',
        'sessionid',  'varchar',  '', $char_d,
        'namespace',  'varchar',  '', $char_d,
      ],
      'primary_key' => 'sessionnum',
      'unique'      => [ [ 'sessionid', 'namespace' ] ],
      'index'       => [],
    },

    'clientapi_session_field' => {
      'columns' => [
        'fieldnum',    'serial',     '', '',
        'sessionnum',     'int',     '', '',
        'fieldname',  'varchar',     '', $char_d,
        'fieldvalue',    'text', 'NULL', '',
      ],
      'primary_key' => 'fieldnum',
      'unique'      => [ [ 'sessionnum', 'fieldname' ] ],
      'index'       => [],
    },

    'payment_gateway' => {
      'columns' => [
        'gatewaynum',       'serial',   '',     '',
        'gateway_module',   'varchar',  '',     $char_d,
        'gateway_username', 'varchar',  'NULL', $char_d,
        'gateway_password', 'varchar',  'NULL', $char_d,
        'gateway_action',   'varchar',  'NULL', $char_d,
        'disabled',   'char',  'NULL',   1,
      ],
      'primary_key' => 'gatewaynum',
      'unique' => [],
      'index'  => [ [ 'disabled' ] ],
    },

    'payment_gateway_option' => {
      'columns' => [
        'optionnum',   'serial',  '',     '',
        'gatewaynum',  'int',     '',     '',
        'optionname',  'varchar', '',     $char_d,
        'optionvalue', 'text',    'NULL', '',
      ],
      'primary_key' => 'optionnum',
      'unique'      => [],
      'index'       => [ [ 'gatewaynum' ], [ 'optionname' ] ],
    },

    'agent_payment_gateway' => {
      'columns' => [
        'agentgatewaynum', 'serial', '', '',
        'agentnum',        'int', '', '',
        'gatewaynum',      'int', '', '',
        'cardtype',        'varchar', 'NULL', $char_d,
        'taxclass',        'varchar', 'NULL', $char_d,
      ],
      'primary_key' => 'agentgatewaynum',
      'unique'      => [],
      'index'       => [ [ 'agentnum', 'cardtype' ], ],
    },

    'banned_pay' => {
      'columns' => [
        'bannum',  'serial',   '',     '',
        'payby',   'char',     '',       4,
        'payinfo', 'varchar',  '',     128, #say, a 512-big digest _hex encoded
	#'paymask', 'varchar',  'NULL', $char_d,
        '_date',   @date_type,
        'otaker',  'varchar',  '',     32,
        'reason',  'varchar',  'NULL', $char_d,
      ],
      'primary_key' => 'bannum',
      'unique'      => [ [ 'payby', 'payinfo' ] ],
      'index'       => [],
    },

    'cancel_reason' => {
      'columns' => [
        'reasonnum', 'serial',  '',     '',
        'reason',    'varchar', '',     $char_d,
        'disabled',  'char',    'NULL', 1,
      ],
      'primary_key' => 'reasonnum',
      'unique' => [],
      'index'  => [ [ 'disabled' ] ],
    },

  };

}

=back

=head1 BUGS

=head1 SEE ALSO

L<DBIx::DBSchema>

=cut

1;

