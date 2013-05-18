package MogileFS::Plugin::MetaData;

use strict;
use warnings;

our $VERSION = '0.01';
$VERSION = eval $VERSION;

sub load {
    return 1;
}

sub unload {
    return 1;
}

sub delete_metadata {
    my ($fid) = @_;

    # delete all meta-data for this fid
    my $sto = Mgd::get_store();
    $sto->plugin_metadata_delete_metadata($fid);
}

sub get_metadata {
    my ($fid) = @_;

    # retrieve all meta-data for this fid
    my $sto = Mgd::get_store();
    my $meta = $sto->plugin_metadata_get_metadata_by_fid($fid);

    # replace $nameid with $name
    my $meta_by_name = {};
    foreach my $nameid (keys %$meta) {
        my $name = _get_name($nameid);
        $meta_by_name->{$name} = $meta->{$nameid};
    }

    return $meta_by_name;
}

# return the metadata for all the listed fids in the format: $meta->{$fid}->{$name}
sub get_bulk_metadata {
    my @fids = @_;

    # retrieve all the meta-data for the specified fids
    my $sto = Mgd::get_store();
    my $meta = $sto->plugin_metadata_get_metadata_by_fids;

    # replace $nameid with $name
    my $meta_by_name = {};
    foreach my $fid (keys %$meta) {
        foreach my $nameid (keys %{$meta->{$fid}}) {
            $meta_by_name->{$fid}->{_get_name($nameid)} = $meta->{$fid}->{$nameid};
        }
    }

    return $meta_by_name;
}

sub set_metadata {
    my ($fid, $meta_by_name) = @_;

    my $meta_by_nameid = {};
    foreach my $name (keys %$meta_by_name) {
        my $nameid = _get_nameid($name, 1);

        if (!defined $nameid) {
            die "Bailing out, unable to get a metadata nameid for '$name'";
        }

        $meta_by_nameid->{$nameid} = $meta_by_name->{$name};
    }

    my $sto = Mgd::get_store();
    foreach my $nameid (keys %$meta_by_nameid) {
        $sto->plugin_metadata_add_metadata(
            'fid'    => $fid,
            'nameid' => $nameid,
            'data'   => $meta_by_nameid->{$nameid},
        );
    }

    return 1;
}

# in memory cache of metadata names
# id => name mappings are never deleted so cache them indefinitely
my %name_to_nameid;
my %nameid_to_name;

sub _get_name {
    my ($nameid) = @_;

    unless(defined $nameid_to_name{$nameid}) {
        # retrieve the name for the specified nameid
        my $sto = Mgd::get_store();
        my $name = $sto->plugin_metadata_get_name_by_nameid($nameid);

        # update the namemap
        if(defined $name) {
            $nameid_to_name{$nameid} = $name;
            $name_to_nameid{lc($name)} = $nameid;
        }
    }

    return $nameid_to_name{$nameid};
}

sub _get_nameid {
    my ($name, $create) = @_;
    my $sto = Mgd::get_store();

    unless(defined $name_to_nameid{lc($name)}) {
        # retrieve the nameid for the specified name
        my $nameid = $sto->plugin_metadata_get_nameid_by_name($name);

        # update the namemap
        if(defined($nameid)) {
            $name_to_nameid{lc($name)} = $nameid;
            $nameid_to_name{$nameid} = $name;
        }
    }

    if(!defined $name_to_nameid{lc($name)} && $create) {
        # register the metadata name
        my $nameid = $sto->plugin_metadata_add_name($name);

        # update the namemap
        if(defined($nameid)) {
            $name_to_nameid{lc($name)} = $nameid;
            $nameid_to_name{$nameid} = $name;
        }

        return _get_nameid($name);
    }

    return $name_to_nameid{$name};
}

package MogileFS::Store;

use MogileFS::Store;

use strict;
use warnings;

sub TABLE_plugin_metadata_names { "
CREATE TABLE plugin_metadata_names (
    nameid BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    PRIMARY KEY (nameid)
)
" }

sub TABLE_plugin_metadata_data { "
CREATE TABLE plugin_metadata_data (
    fid BIGINT UNSIGNED NOT NULL,
    nameid BIGINT UNSIGNED NOT NULL,
    data VARCHAR(255) NOT NULL,
    PRIMARY KEY (fid, nameid)
)
" }

sub plugin_metadata_add_metadata {
    my $self = shift;
    my %arg  = $self->_valid_params([qw(fid nameid data)], @_);

    return $self->retry_on_deadlock(sub {
        my $dbh = $self->dbh;
        $dbh->do('INSERT INTO plugin_metadata_data (fid, nameid, data) '.
                 'VALUES (?,?,?) ', undef,
                 @arg{'fid', 'nameid', 'data'});
        return 1;
    });
}

sub plugin_metadata_delete_metadata {
    my $self = shift;
    my ($fid) = @_;
    return $self->retry_on_deadlock(sub {
        my $dbh = $self->dbh;
        $dbh->do('DELETE FROM plugin_metadata_data WHERE fid = ?', undef, $fid);
        return undef if $dbh->err;
        return 1;
    });
}

sub plugin_metadata_get_metadata_by_fid {
    my $self = shift;
    my ($fid) = @_;
    my $dbh = $self->dbh;
    my $sth = $dbh->prepare('SELECT nameid, data FROM plugin_metadata_data WHERE fid = ?');
    $sth->execute($fid);

    my $meta = {};
    while (my $row = $sth->fetchrow_arrayref()) {
        $meta->{$row->[0]} = $row->[1];
    }

    return $meta;
}

sub plugin_metadata_get_metadata_by_fids {
    my $self = shift;
    my @fids = @_;
    return {} if(!@fids);

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare('SELECT fid, nameid, data ' .
                            'FROM plugin_metadata_data ' .
                            'WHERE fid IN (' . join(',', (('?') x scalar @fids)) . ')');
    $sth->execute(@fids);

    my $meta = {};
    while (my $row = $sth->fetchrow_arrayref()) {
        $meta->{$row->[0]}->{$row->[1]} = $row->[2];
    }

    return $meta;
}

sub plugin_metadata_get_name_by_nameid {
    my $self = shift;
    my ($nameid) = @_;
    my $dbh = $self->dbh;
    my ($name) = $dbh->selectrow_array('SELECT name FROM plugin_metadata_names WHERE nameid = ?', undef, $nameid);
    return $name;
}

sub plugin_metadata_get_nameid_by_name {
    my $self = shift;
    my ($name) = @_;
    my $dbh = $self->dbh;
    my ($nameid) = $dbh->selectrow_array('SELECT nameid FROM plugin_metadata_names WHERE name = ?', undef, $name);
    return $nameid;
}

sub plugin_metadata_add_name {
    my $self = shift;
    my ($name) = @_;
    return $self->retry_on_deadlock(sub {
        my $dbh = $self->dbh;
        $dbh->do('INSERT INTO plugin_metadata_names (name) VALUES (?) ', undef, $name);
        return $dbh->last_insert_id(undef, undef, 'plugin_metadata_names', 'nameid');
    });
}

__PACKAGE__->add_extra_tables("plugin_metadata_names", "plugin_metadata_data");

1;
