#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Scalar::Util qw(refaddr reftype blessed);

use KiokuDB::TypeMap::Entry::Callback;
use KiokuDB::TypeMap::Resolver;
use KiokuDB::Collapser;
use KiokuDB::Linker;
use KiokuDB::LiveObjects;
use KiokuDB::Backend::Hash;

{
    package KiokuDB_Test_Foo;
    use Moose;

    has foo => ( is => "rw" );

    has bar => ( is => "rw", isa => "KiokuDB_Test_Bar" );

    package KiokuDB_Test_Bar;
    use Moose;

    has blah => ( is => "rw" );

    sub pack {
        my $self = shift;
        return ( blah => $self->blah );
    }
}

my $obj = KiokuDB_Test_Foo->new( foo => "HALLO" );

my $deep = KiokuDB_Test_Foo->new( foo => "la", bar => KiokuDB_Test_Bar->new( blah => "hai" ) );

my $bar = KiokuDB::TypeMap::Entry::Callback->new(
    collapse => "pack",
    expand   => "new",
);

my $foo = KiokuDB::TypeMap::Entry::Callback->new(
    collapse => sub {
        my $self = shift;
        my $meta = $self->meta;
        return map { $_->name => $_->get_value($self) } grep { $_->has_value($self) } map { $meta->find_attribute_by_name($_) } qw(foo bar);
    },
    expand => sub {
        my ( $class, @args ) = @_;
        $class->new(@args);
    }
);

my $tr = KiokuDB::TypeMap::Resolver->new(
    typemap => KiokuDB::TypeMap->new(
        entries => {
            KiokuDB_Test_Bar => $bar,
            KiokuDB_Test_Foo => $foo,
        },
    ),
);

my $v = KiokuDB::Collapser->new(
    backend => KiokuDB::Backend::Hash->new,
    live_objects => KiokuDB::LiveObjects->new,
    typemap_resolver => $tr,
);

my $l = KiokuDB::Linker->new(
    backend => KiokuDB::Backend::Hash->new,
    live_objects => KiokuDB::LiveObjects->new,
    typemap_resolver => $tr,
);

{
    my $s = $v->live_objects->new_scope;

    my ( $buffer ) = $v->collapse( objects => [ $obj ],  );

    my $entries = $buffer->_entries;

    is( scalar(keys %$entries), 1, "one entry" );

    my $entry = ( values %$entries )[0];

    isnt( refaddr($entry->data), refaddr($obj), "refaddr doesn't equal" );
    ok( !blessed($entry->data), "entry data is not blessed" );

    my $sl = $l->live_objects->new_scope;

    my $expanded = $l->expand_object($entry);

    isa_ok( $expanded, "KiokuDB_Test_Foo", "expanded object" );
    isnt( refaddr($expanded), refaddr($obj), "refaddr doesn't equal" );
    isnt( refaddr($expanded), refaddr($entry->data), "refaddr doesn't entry data refaddr" );
    is_deeply( $expanded, $obj, "is_deeply" );
}


done_testing;
