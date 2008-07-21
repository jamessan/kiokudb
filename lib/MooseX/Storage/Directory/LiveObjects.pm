#!/usr/bin/perl

package MooseX::Storage::Directory::LiveObjects;
use Moose;

use MooseX::AttributeHelpers;

use Scalar::Util qw(weaken);
use Scope::Guard;
use Hash::Util::FieldHash::Compat qw(fieldhash);
use Carp qw(croak);
use Devel::PartialDump qw(dump);
use Check::ISA qw(obj);

use namespace::clean -except => 'meta';

has _objects => (
    isa => "HashRef",
    is  => "ro",
    init_arg => undef,
    default => sub { fieldhash my %hash },
);

has _ids => (
    metaclass => 'Collection::Hash',
    isa => "HashRef",
    is  => "ro",
    init_arg => undef,
    default => sub { my %hash; \%hash },
    provides => {
        get    => "ids_to_objects",
        keys   => "live_ids",
        values => "live_objects",
    },
);

sub id_to_object {
    my ( $self, $id ) = @_;
    scalar $self->ids_to_objects($id);
}

# stringification takes care of this... is that bad?
#sub ids_to_objects {
#    my ( $self, @ids ) = @_;
#    $self->string_ids_to_objects(map { obj($_, 'Data::GUID') ? $_->as_string : $_ } @ids);
#}

sub objects_to_ids {
    my ( $self, @objects ) = @_;
    my $o = $self->_objects;

    return map {
        my $ent = $o->{$_};
        $ent ? $ent->{id} : undef;
    } @objects;
}

sub object_to_id {
    my ( $self, $obj ) = @_;

    if ( my $ent = $self->_objects->{$obj} ){
        return $ent->{id};
    }

    return undef;
}

sub remove {
    my ( $self, @stuff ) = @_;   

    my ( $o, $i ) = ( $self->_objects, $self->_ids );

    foreach my $thing ( @stuff ) {
        if ( ref $thing && !obj($thing, "Data::GUID") ) {
            if ( my $ent = delete $o->{$thing} ) {
                delete $i->{$ent->{id}};
                $ent->{guard}->dismiss;
            }
        } else {
            $thing = $thing->as_string if ref $thing;
            if ( ref( my $object = delete $i->{$thing} ) ) {
                if ( my $ent = delete $o->{$object} ) {
                    $ent->{guard}->dismiss;
                }
            }
        }
    }
}

sub insert {
    my ( $self, @pairs ) = @_;

    croak "The arguments must be an list of pairs of IDs to objects"
        unless @pairs % 2 == 0;

    my ( $o, $i ) = ( $self->_objects, $self->_ids );

    my %id_to_obj = map { obj($_, 'Data::GUID') ? $_->as_string : $_ } @pairs;

    foreach my $object ( values %id_to_obj ) {
        croak dump($object, " is not a reference") unless ref($object);
    }

    foreach my $id ( keys %id_to_obj ) {
        croak "An object with the id '$id' is already registered"
            if exists $i->{$id};
    }

    foreach my $id ( keys %id_to_obj ) {
        my $object = $id_to_obj{$id};

        next if exists $o->{$object};

        weaken($i->{$id} = $object);

        $o->{$object} = {
            id => $id,
            guard => Scope::Guard->new(sub {
                delete $i->{$id};
            }),
        },
    }
}

sub DEMOLISH {
    my $self = shift;

    foreach my $ent ( values %{ $self->_objects } ) {
        if ( my $guard = $ent->{guard} ) { # sometimes gone in global destruction
            $guard->dismiss;
        }
    }

    # avoid the now needless weaken magic, should be faster
    %{ $self->_objects } = ();
    %{ $self->_ids }     = ();
}

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__

=pod

=head1 NAME

MooseX::Storage::Directory::LiveObjects - Live object set tracking

=head1 SYNOPSIS

=head1 DESCRIPTION

This object keeps track of the set of live objects and their associated UIDs.

=cut