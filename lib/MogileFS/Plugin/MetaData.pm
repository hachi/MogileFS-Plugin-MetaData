package MogileFS::Plugin::MetaData;

use strict;
use warnings;

our $VERSION = '0.01';
$VERSION = eval $VERSION;

my %name_to_nameid;
my %nameid_to_name;

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

    my $meta_by_name = {};
    foreach my $nameid (keys %$meta) {
        my $name = $nameid_to_name{$nameid};
        unless (exists $nameid_to_name{$nameid}) {
            ($name) = $dbh->selectrow_array('SELECT name FROM plugin_metadata_names WHERE nameid=?', undef, $nameid);
            die "DBH Error while getting nameid->name mapping: " . $dbh->errstr if $dbh->err;
            $nameid_to_name{$nameid} = $name;
            $name_to_nameid{$name} = $nameid;
        }
        $meta_by_name->{$name} = $meta->{$nameid};
    }

    return $meta_by_name;
}

sub set_metadata {
    my ($fid, $meta_by_name) = @_;

    my $dbh = Mgd::get_dbh();

    my $meta_by_nameid = {};

    # Flag indicating if we've inserted and decided to redo the loop, to prevent infinite loops.
    my $inserted = 0;

    foreach my $name (keys %$meta_by_name) {
        my $nameid = $name_to_nameid{$name};

        unless (exists $name_to_nameid{$name}) {
            ($nameid) = $dbh->selectrow_array('SELECT nameid FROM plugin_metadata_names WHERE name=?', undef, $name);
            warn "DBH Error on SELECT: " . $dbh->errstr if $dbh->err;
            $nameid_to_name{$nameid} = $name;
            $name_to_nameid{$name} = $nameid;
        }

        if ($inserted && ! $nameid) {
            die "Bailing out, unable to get a metadata nameid for '$name'";
        }

        unless ($nameid) {
            $dbh->do('INSERT IGNORE INTO plugin_metadata_names (name) VALUES (?)', undef, $name);
            warn "DBH Error on insert: " . $dbh->errstr if $dbh->err;
            $nameid = $dbh->{mysql_insertid};

            unless ($nameid) {
                $inserted = 1;
                redo;
            }
        }

        $nameid += 0;

        $meta_by_nameid->{$nameid} = $meta_by_name->{$name};
    } continue {
        $inserted = 0;
    }

    foreach my $nameid (keys %$meta_by_nameid) {
        $dbh->do('INSERT INTO plugin_metadata_data (fid, nameid, data) VALUES (?, ?, ?)',
                 undef, $fid, $nameid, $meta_by_nameid->{$nameid});
        warn "DBH Error on insert of metadata: " . $dbh->errstr if $dbh->err;
    }

    return 1;
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

__PACKAGE__->add_extra_tables("plugin_metadata_names", "plugin_metadata_data");

1;
