package KiokuDB::Util;
use strict;
use warnings;
# ABSTRACT: Utility functions for working with KiokuDB

use Path::Class;

use Carp qw(croak);
use MooseX::YAML 0.04;
use Scalar::Util qw(blessed);

use namespace::clean;

use Sub::Exporter -setup => {
    exports => [qw(set weak_set dsn_to_backend import_yaml deprecate)],
};

sub weak_set {
    require KiokuDB::Set::Transient;
    KiokuDB::Set::Transient->new( set => Set::Object::Weak->new(@_) )
}

sub set {
    require KiokuDB::Set::Transient;
    KiokuDB::Set::Transient->new( set => Set::Object->new(@_) );
}

my %monikers = (
    "hash"    => "Hash",
    "bdb"     => "BDB",
    "bdb-gin" => "BDB::GIN",
    "dbi"     => "DBI",
    "jspon"   => "JSPON",
    "files"   => "Files",
    "couchdb" => "CouchDB",
    "mongodb" => "MongoDB",
);

sub _try_json {
    my $json = shift;

    require JSON;
    JSON->new->decode($json);
}

sub dsn_to_backend {
    my ( $dsn, @args ) = @_;

    if ( my ( $moniker, $rest ) = ( $dsn =~ /^([\w-]+)(?::(.*))?$/ ) ) {
        $moniker = $monikers{$moniker} || $moniker;
        my $class = "KiokuDB::Backend::$moniker";

        Class::MOP::load_class($class);
        return $class->new_from_dsn($rest, @args);
    } elsif ( my $args = _try_json($dsn) ) {
        my $dsn;

        if ( ref $args eq 'ARRAY' ) {
            ( $dsn, $args ) = @$args;
        }

        if ( ref $args eq 'HASH' ) {
            $dsn ||= delete $args->{dsn};
            return dsn_to_backend($dsn, %$args, @args);
        }
    }

    croak "Malformed DSN: $dsn";
}

sub load_config {
    my ( $base ) = @_;

    my $config_file;
    if ( $base =~ /\.yml$/ ) {
        $config_file = $base;
    } else {
        $config_file = dir($base)->file("kiokudb.yml");
        $config_file->openr;
    }

    MooseX::YAML::LoadFile($config_file);
}

sub config_to_backend {
    my ( $config, %args ) = @_;

    my $base = delete($args{base});

    my $backend = $config->{backend};

    return $backend if blessed($backend);

    my $backend_class = $backend->{class};
    Class::MOP::load_class($backend_class);

    return $backend_class->new_from_dsn_params(
        ( defined($base) ? ( dir => $base->subdir("data") ) : () ),
        %$backend,
        %args,
    );
}

sub import_yaml {
    my ( $kiokudb, @src ) = @_;

    my @objects = load_yaml_files( find_yaml_files(@src) );

    $kiokudb->txn_do(sub {
        my $scope = $kiokudb->new_scope;
        $kiokudb->insert(@objects);
    });
}

sub find_yaml_files {
    my ( @src ) = @_;

    my @files;

    foreach my $src ( @src ) {
        if ( -d $src ) {
            dir($src)->recurse( callback => sub {
                my $file = shift;

                if ( -f $file && $file->basename =~ /\.yml$/ ) {
                    push @files, $file;
                }
            });
        } else {
            push @files, $src;
        }
    }

    return @files;
}

sub load_yaml_files {
    my ( @files ) = @_;

    my @objects;

    foreach my $file ( @files ) {
        my @data = MooseX::YAML::LoadFile($file);

        if ( @data == 1 ) {
            unless ( blessed $data[0] ) {
                if ( ref $data[0] eq 'ARRAY' ) {
                    @data = @{ $data[0] };
                } else {
                    @data = %{ $data[0] }; # with IDs
                }
            }
        }

        push @objects, @data;
    }

    return @objects;
}

my %seen_deprecation;

use constant HARNESS_ACTIVE => not not $ENV{HARNESS_ACTIVE};

sub deprecate ($$) {
    if ( HARNESS_ACTIVE ) {
        my ( $version, $reason ) = @_;

        # parts stolen from Devel::Deprecate, but we're doing version based
        # deprecation, not date based deprecation

        require KiokuDB;

        if ( $KiokuDB::VERSION >= $version ) {
            my ( $package, $filename, $line ) = caller(1);
            my ( undef, undef, undef, $subroutine ) = caller(2);

            return if $seen_deprecation{"${filename}:$line"}++; # no need to warn more than once

            $subroutine ||= 'n/a';
            my $padding = ' ' x 18;
            $reason =~ s/\n/\n#$padding/g;

            Carp::cluck(<<"END");
# DEPRECATION WARNING
#
#     Package:     $package
#     File:        $filename
#     Line:        $line
#     Subroutine:  $subroutine
#
#     Reason:      $reason
END
        }
    }
}

__PACKAGE__

__END__

=pod

=head1 SYNOPSIS

    use KiokuDB::Util qw(set weak_set);

    my $set = set(@objects); # create a transient set

    my $weak = weak_set(@objects); # to avoid circular refs

=head1 DESCRIPTION

This module provides various helper functions for working with L<KiokuDB>.

=head1 EXPORTS

=over 4

=item dsn_to_backend $dsn, %args

Tries to parse C<$dsn>, load the backend and invoke C<new> on it.

Used by L<KiokuDB/connect> and the various command line interfaces.

=item set

=item weak_set

Instantiate a L<Set::Object> or L<Set::Object::Weak> from the arguments, and
then creates a L<KiokuDB::Set::Transient> with the result.

=item import_yaml $kiokudb, @files_or_dirs

Loads YAML files with L<MooseX::YAML> (if given a directory it will be searched
recursively for files with a C<.yml> extension are) into the specified KiokuDB
directory in a single transaction.

The YAML files can contain multiple documents, with each document treated as an
object. If the YAML file contains a single non blessed array or hash then that
structure will be dereferenced as part of the arguments to C<insert>.

Here is an example of an array of objects, and a custom tag alias to ease
authoring of the YAML file:

    %YAML 1.1
    %TAG ! !MyFoo::
    ---
    - !User
      id:        foo
      real_name: Foo Bar
      email:     foo@myfoo.com
      password:  '{cleartext}test123'

You can use a hash to specify custom IDs:

    %YAML 1.1
    ---
    the_id: !Some::Class
        attr: moose

=back

=cut
