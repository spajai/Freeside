package FS::part_export;

use strict;
use vars qw( @ISA @EXPORT_OK %exports );
use Exporter;
use FS::Record qw( qsearch qsearchs dbh );
use FS::part_svc;
use FS::part_export_option;
use FS::export_svc;

@ISA = qw(FS::Record);
@EXPORT_OK = qw(export_info);

=head1 NAME

FS::part_export - Object methods for part_export records

=head1 SYNOPSIS

  use FS::part_export;

  $record = new FS::part_export \%hash;
  $record = new FS::part_export { 'column' => 'value' };

  #($new_record, $options) = $template_recored->clone( $svcpart );

  $error = $record->insert( { 'option' => 'value' } );
  $error = $record->insert( \%options );

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::part_export object represents an export of Freeside data to an external
provisioning system.  FS::part_export inherits from FS::Record.  The following
fields are currently supported:

=over 4

=item exportnum - primary key

=item machine - Machine name 

=item exporttype - Export type

=item nodomain - blank or "Y" : usernames are exported to this service with no domain

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new export.  To add the export to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'part_export'; }

=cut

#=item clone SVCPART
#
#An alternate constructor.  Creates a new export by duplicating an existing
#export.  The given svcpart is assigned to the new export.
#
#Returns a list consisting of the new export object and a hashref of options.
#
#=cut
#
#sub clone {
#  my $self = shift;
#  my $class = ref($self);
#  my %hash = $self->hash;
#  $hash{'exportnum'} = '';
#  $hash{'svcpart'} = shift;
#  ( $class->new( \%hash ),
#    { map { $_->optionname => $_->optionvalue }
#        qsearch('part_export_option', { 'exportnum' => $self->exportnum } )
#    }
#  );
#}

=item insert HASHREF

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

If a hash reference of options is supplied, part_export_option records are
created (see L<FS::part_export_option>).

=cut

#false laziness w/queue.pm
sub insert {
  my $self = shift;
  my $options = shift;
  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error = $self->SUPER::insert;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  foreach my $optionname ( keys %{$options} ) {
    my $part_export_option = new FS::part_export_option ( {
      'exportnum'   => $self->exportnum,
      'optionname'  => $optionname,
      'optionvalue' => $options->{$optionname},
    } );
    $error = $part_export_option->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';

};

=item delete

Delete this record from the database.

=cut

#foreign keys would make this much less tedious... grr dumb mysql
sub delete {
  my $self = shift;
  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error = $self->SUPER::delete;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  foreach my $part_export_option ( $self->part_export_option ) {
    my $error = $part_export_option->delete;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  foreach my $export_svc ( $self->export_svc ) {
    my $error = $export_svc->delete;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';

}

=item replace OLD_RECORD HASHREF

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

If a hash reference of options is supplied, part_export_option records are
created or modified (see L<FS::part_export_option>).

=cut

sub replace {
  my $self = shift;
  my $old = shift;
  my $options = shift;
  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error = $self->SUPER::replace($old);
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  foreach my $optionname ( keys %{$options} ) {
    my $old = qsearchs( 'part_export_option', {
        'exportnum'   => $self->exportnum,
        'optionname'  => $optionname,
    } );
    my $new = new FS::part_export_option ( {
        'exportnum'   => $self->exportnum,
        'optionname'  => $optionname,
        'optionvalue' => $options->{$optionname},
    } );
    $new->optionnum($old->optionnum) if $old;
    my $error = $old ? $new->replace($old) : $new->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  #remove extraneous old options
  foreach my $opt (
    grep { !exists $options->{$_->optionname} } $old->part_export_option
  ) {
    my $error = $opt->delete;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';

};

=item check

Checks all fields to make sure this is a valid export.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

sub check {
  my $self = shift;
  my $error = 
    $self->ut_numbern('exportnum')
    || $self->ut_domain('machine')
    || $self->ut_alpha('exporttype')
  ;
  return $error if $error;

  warn $self->machine. "!!!\n";

  $self->machine =~ /^([\w\-\.]*)$/
    or return "Illegal machine: ". $self->machine;
  $self->machine($1);

  $self->nodomain =~ /^(Y?)$/ or return "Illegal nodomain: ". $self->nodomain;
  $self->nodomain($1);

  $self->deprecated(1); #BLAH

  #check exporttype?

  ''; #no error
}

#=item part_svc
#
#Returns the service definition (see L<FS::part_svc>) for this export.
#
#=cut
#
#sub part_svc {
#  my $self = shift;
#  qsearchs('part_svc', { svcpart => $self->svcpart } );
#}

sub part_svc {
  use Carp;
  croak "FS::part_export::part_svc deprecated";
  #confess "FS::part_export::part_svc deprecated";
}

=item export_svc

Returns a list of associated FS::export_svc records.

=cut

sub export_svc {
  my $self = shift;
  qsearch('export_svc', { 'exportnum' => $self->exportnum } );
}

=item part_export_option

Returns all options as FS::part_export_option objects (see
L<FS::part_export_option>).

=cut

sub part_export_option {
  my $self = shift;
  qsearch('part_export_option', { 'exportnum' => $self->exportnum } );
}

=item options 

Returns a list of option names and values suitable for assigning to a hash.

=cut

sub options {
  my $self = shift;
  map { $_->optionname => $_->optionvalue } $self->part_export_option;
}

=item option OPTIONNAME

Returns the option value for the given name, or the empty string.

=cut

sub option {
  my $self = shift;
  my $part_export_option =
    qsearchs('part_export_option', {
      exportnum  => $self->exportnum,
      optionname => shift,
  } );
  $part_export_option ? $part_export_option->optionvalue : '';
}

=item rebless

Reblesses the object into the FS::part_export::EXPORTTYPE class, where
EXPORTTYPE is the object's I<exporttype> field.  There should be better docs
on how to create new exports (and they should live in their own files and be
autoloaded-on-demand), but until then, see L</NEW EXPORT CLASSES>.

=cut

sub rebless {
  my $self = shift;
  my $exporttype = $self->exporttype;
  my $class = ref($self). "::$exporttype";
  eval "use $class;";
  bless($self, $class);
}

=item export_insert SVC_OBJECT

=cut

sub export_insert {
  my $self = shift;
  $self->rebless;
  $self->_export_insert(@_);
}

#sub AUTOLOAD {
#  my $self = shift;
#  $self->rebless;
#  my $method = $AUTOLOAD;
#  #$method =~ s/::(\w+)$/::_$1/; #infinite loop prevention
#  $method =~ s/::(\w+)$/_$1/; #infinite loop prevention
#  $self->$method(@_);
#}

=item export_replace NEW OLD

=cut

sub export_replace {
  my $self = shift;
  $self->rebless;
  $self->_export_replace(@_);
}

=item export_delete

=cut

sub export_delete {
  my $self = shift;
  $self->rebless;
  $self->_export_delete(@_);
}

#fallbacks providing useful error messages intead of infinite loops
sub _export_insert {
  my $self = shift;
  return "_export_insert: unknown export type ". $self->exporttype;
}

sub _export_replace {
  my $self = shift;
  return "_export_replace: unknown export type ". $self->exporttype;
}

sub _export_delete {
  my $self = shift;
  return "_export_delete: unknown export type ". $self->exporttype;
}

=back

=head1 SUBROUTINES

=over 4

=item export_info [ SVCDB ]

Returns a hash reference of the exports for the given I<svcdb>, or if no
I<svcdb> is specified, for all exports.  The keys of the hash are
I<exporttype>s and the values are again hash references containing information
on the export:

  'desc'     => 'Description',
  'options'  => {
                  'option'  => { label=>'Option Label' },
                  'option2' => { label=>'Another label' },
                },
  'nodomain' => 'Y', #or ''
  'notes'    => 'Additional notes',

=cut

sub export_info {
  #warn $_[0];
  return $exports{$_[0]} if @_;
  #{ map { %{$exports{$_}} } keys %exports };
  my $r = { map { %{$exports{$_}} } keys %exports };
}

=item exporttype2svcdb EXPORTTYPE

Returns the applicable I<svcdb> for an I<exporttype>.

=cut

sub exporttype2svcdb {
  my $exporttype = $_[0];
  foreach my $svcdb ( keys %exports ) {
    return $svcdb if grep { $exporttype eq $_ } keys %{$exports{$svcdb}};
  }
  '';
}

%exports = (
  'svc_acct' => {
    'sysvshell' => {
      'desc' =>
        'Batch export of /etc/passwd and /etc/shadow files (Linux/SysV)',
      'options' => {},
    },
    'bsdshell' => {
      'desc' =>
        'Batch export of /etc/passwd and /etc/master.passwd files (BSD)',
      'options' => {},
    },
#    'nis' => {
#      'desc' =>
#        'Batch export of /etc/global/passwd and /etc/global/shadow for NIS ',
#      'options' => {},
#    },
    'textradius' => {
      'desc' => 'Batch export of a text /etc/raddb/users file (Livingston, Cistron)',
    },

    'shellcommands' => {
      'desc' => 'Real-time export via arbitrary commands on a remote machine (i.e. useradd, userdel, etc.)',
      'options' => {
        'machine' => { label=>'Remote machine' },
        'user' => { label=>'Remote username', default=>'root' },
        'useradd' => { label=>'Insert command',
                       default=>'useradd -d $dir -m -s $shell -u $uid $username'
                      #default=>'cp -pr /etc/skel $dir; chown -R $uid.$gid $dir'
                     },
        'userdel' => { label=>'Delete command',
                       default=>'userdel $username',
                       #default=>'rm -rf $dir',
                     },
        'usermod' => { label=>'Modify command',
                       default=>'usermod -d $new_dir -l $new_username -s $new_shell -u $new_uid $old_username',
                      #default=>'[ -d $old_dir ] && mv $old_dir $new_dir || ( '.
                       #  'chmod u+t $old_dir; mkdir $new_dir; cd $old_dir; '.
                       #  'find . -depth -print | cpio -pdm $new_dir; '.
                       #  'chmod u-t $new_dir; chown -R $uid.$gid $new_dir; '.
                       #  'rm -rf $old_dir'.
                       #')'
                     },
      },
      'nodomain' => 'Y',
      'notes' => 'shellcommandsnotes... (this one is the nodomain one)',
    },

    'sqlradius' => {
      'desc' => 'Real-time export to SQL-backed RADIUS (ICRADIUS, FreeRADIUS)',
      'options' => {
        'datasrc'  => { label=>'DBI data source' },
        'username' => { label=>'Database username' },
        'password' => { label=>'Database password' },
      },
      'nodomain' => 'Y',
      'notes' => 'Real-time export of radcheck, radreply and usergroup tables to any SQL database for <a href="http://www.freeradius.org/">FreeRADIUS</a> or <a href="http://radius.innercite.com/">ICRADIUS</a>.  Use <a href="../docs/man/bin/freeside-sqlradius-reset">freeside-sqlradius-reset</a> to delete and repopulate the tables from the Freeside database.',
    },

    'cyrus' => {
      'desc' => 'Real-time export to Cyrus IMAP server',
      'options' => {
        'server' => { label=>'IMAP server' },
        'username' => { label=>'Admin username' },
        'password' => { label=>'Admin password' },
      },
      'nodomain' => 'Y',
      'notes' => 'Integration with <a href="http://asg.web.cmu.edu/cyrus/imapd/">Cyrus IMAP Server</a>.  Cyrus::IMAP::Admin should be installed locally and the connection to the server secured.  <B>svc_acct.quota</B> is used to set the Cyrus quota if available. '
    },

    'cp' => {
      'desc' => 'Real-time export to Critical Path Account Provisioning Protocol',
      'options' => {
        'host'      => { label=>'Hostname' },
        'port'      => { label=>'Port number' },
        'username'  => { label=>'Username' },
        'password'  => { label=>'Password' },
        'domain'    => { label=>'Domain' },
        'workgroup' => { label=>'Default Workgroup' },
      },
      'notes' => 'Real-time export to <a href="http://www.cp.net/">Critial Path Account Provisioning Protocol</a>.  Requires installation of <a href="http://search.cpan.org/search?dist=Net-APP">Net::APP</a> from CPAN.',
    },
    
    'infostreet' => {
      'desc' => 'Real-time export to InfoStreet streetSmartAPI',
      'options' => {
        'url'      => { label=>'XML-RPC Access URL', },
        'login'    => { label=>'InfoStreet login', },
        'password' => { label=>'InfoStreet password', },
        'groupID'  => { label=>'InfoStreet groupID', },
      },
      'nodomain' => 'Y',
      'notes' => 'Real-time export to <a href="http://www.infostreet.com/">InfoStreet</a> streetSmartAPI.  Requires installation of <a href="http://search.cpan.org/search?dist=Frontier-Client">Frontier::Client</a> from CPAN.',
    },

  },

  'svc_domain' => {},

  'svc_acct_sm' => {},

  'svc_forward' => {},

  'svc_www' => {},

);

=back

=head1 NEW EXPORT CLASSES

Should be added to the %export hash here, and a module should be added in
FS/FS/part_export/ (an example may be found in eg/export_template.pm)

=head1 BUGS

Probably.

Hmm... cust_export class (not necessarily a database table...) ... ?

deprecated column...

=head1 SEE ALSO

L<FS::part_export_option>, L<FS::export_svc>, L<FS::svc_acct>,
L<FS::svc_domain>,
L<FS::svc_forward>, L<FS::Record>, schema.html from the base documentation.

=cut

1;

