package KiokuDB::Serializer::JSON;
use Moose;

use namespace::clean -except => 'meta';

with qw(
    KiokuDB::Serializer
    KiokuDB::Backend::Serialize::JSON
);

sub file_extension { "json" }

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__
