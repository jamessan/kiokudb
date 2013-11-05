package KiokuDB::LiveObjects::Guard;
use strict;
use warnings;

use Scalar::Util qw(weaken);

use namespace::clean -except => 'meta';

sub new {
    my ( $class, $hash, $key ) = @_;
    my $self = bless [ $hash, $key ], $class;
    weaken $self->[0];
    return $self;
}

sub key {
    $_[0][1];
}

sub DESTROY {
    my $self = shift;
    my ( $hash, $key ) = splice @$self;
    delete $hash->{$key} if $hash;
}

sub dismiss {
    my $self = shift;
    @$self = ();
}


__PACKAGE__

__END__
