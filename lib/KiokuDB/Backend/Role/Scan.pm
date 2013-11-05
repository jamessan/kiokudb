package KiokuDB::Backend::Role::Scan;
use Moose::Role;
# ABSTRACT: Root set iteration

sub entries_to_ids {
    my $stream = shift;
    $stream->filter(sub {[ map { $_->id } @$_ ]});
}

use namespace::clean -except => 'meta';

requires "all_entries";

sub root_entries {
    my $self = shift;
    return $self->all_entries->filter(sub {[ grep { $_->root } @$_ ]});
}

sub child_entries {
    my $self = shift;
    return $self->all_entries->filter(sub {[ grep { not $_->root } @$_ ]});
}

sub all_entry_ids {
    my $self = shift;
    entries_to_ids($self->all_entries);
}

sub root_entry_ids {
    my $self = shift;
    entries_to_ids($self->root_entries);
}

sub child_entry_ids {
    my $self = shift;
    entries_to_ids($self->child_entries);
}

__PACKAGE__

__END__

=pod

=head1 SYNOPSIS

    with qw(KiokuDB::Backend::Role::Scan);

    sub all_entries {
        my $self = shift;

        # return all root set entries
        return Data::Stream::Bulk::Foo->new(...);
    }

=head1 DESCRIPTION

This is a role for iterative scanning of all entries in a backend.

It is used for database backups, and various other tasks.

=head1 REQUIRED METHODS

=over 4

=item all_entries

Should return a L<Data::Stream::Bulk> stream enumerating all entries in the
database.

=back

=head1 OPTIONAL METHODS

These method have default implementations defined in terms of C<all_entries>
but maybe overridden if there is a more optimal solution than just filtering
that stream.

=over 4

=item root_entries

Should return a L<Data::Stream::Bulk> of just the root entries.

=item child_entries

Should return a L<Data::Stream::Bulk> of everything but the root entries.

=back

=cut
