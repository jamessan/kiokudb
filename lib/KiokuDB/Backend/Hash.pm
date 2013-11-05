package KiokuDB::Backend::Hash;
use Moose;
# ABSTRACT: In memory backend for testing purposes.

use Data::Stream::Bulk::Util qw(bulk);

use Carp qw(croak);

use namespace::clean -except => 'meta';

with (
    'KiokuDB::Backend::Serialize::Delegate',
    'KiokuDB::Backend',
    'KiokuDB::Backend::Role::Query::Simple::Linear',
    'KiokuDB::Backend::Role::TXN::Memory::Scan',
);

has storage => (
    isa => "HashRef",
    is  => "rw",
    default => sub { {} },
);

sub clear_storage {
    my $self = shift;
    %{ $self->storage } = ();
}

sub get_from_storage {
    my ( $self, @uids ) = @_;

    my $s = $self->storage;

    return if grep { not exists $s->{$_} } @uids;

    my @objs = map { $self->deserialize($_) } @{ $s }{@uids};

    if ( @objs == 1 ) {
        return $objs[0];
    } else {
        return @objs;
    }
}

sub commit_entries {
    my ( $self, @entries ) = @_;

    my $s = $self->storage;

    foreach my $entry ( @entries ) {
        my $id = $entry->id;

        if ( $entry->deleted ) {
            delete $s->{$id};
        } else {
            if ( exists $s->{$id} and not $entry->has_prev ) {
                croak "Entry $id already exists in the database";
            }
            $s->{$id} = $self->serialize($entry);
        }
    }
}

sub exists_in_storage {
    my ( $self, @uids ) = @_;

    map { exists $self->storage->{$_} } @uids;
}

sub all_storage_entries {
    my $self = shift;
    return bulk(map { $self->deserialize($_) } values %{ $self->storage });
}

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__

=pod

=head1 SYNOPSIS

    my $dir = KiokuDB->new(
        backend => KiokuDB::Backend::Hash->new(),
    );

=head1 DESCRIPTION

This L<KiokuDB> backend provides in memory storage and retrieval of
L<KiokuDB::Entry> objects using L<Storable>'s C<dclone> to make dumps of the
backend clear.

=cut
