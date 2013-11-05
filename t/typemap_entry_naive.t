#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Scalar::Util qw(refaddr reftype blessed);

use KiokuDB::TypeMap::Entry::Naive;
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
}

my $obj = KiokuDB_Test_Foo->new( foo => "HALLO" );

my $deep = KiokuDB_Test_Foo->new( foo => "la", bar => KiokuDB_Test_Bar->new( blah => "hai" ) );

my $n = KiokuDB::TypeMap::Entry::Naive->new();
my $i = KiokuDB::TypeMap::Entry::Naive->new( intrinsic => 1 );

my $tr = KiokuDB::TypeMap::Resolver->new(
    typemap => KiokuDB::TypeMap->new(
        entries => {
            KiokuDB_Test_Foo => $n,
            KiokuDB_Test_Bar => $i,
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
    is( reftype($entry->data), reftype($obj), "reftype" );
    is_deeply( $entry->data, {%$obj}, "is_deeply" );

    my $sl = $l->live_objects->new_scope;

    my $expanded = $l->expand_object($entry);

    isa_ok( $expanded, "KiokuDB_Test_Foo", "expanded object" );
    isnt( refaddr($expanded), refaddr($obj), "refaddr doesn't equal" );
    isnt( refaddr($expanded), refaddr($entry->data), "refaddr doesn't entry data refaddr" );
    is_deeply( $expanded, $obj, "is_deeply" );
}

{
    my $s = $v->live_objects->new_scope;

    my $bar = $deep->bar;

    my ( $buffer ) = $v->collapse( objects => [ $deep ],  );

    my $entries = $buffer->_entries;

    is( scalar(keys %$entries), 1, "one entry" );

    my $entry = ( values %$entries )[0];

    isnt( refaddr($entry->data), refaddr($deep), "refaddr doesn't equal" );
    ok( !blessed($entry->data), "entry data is not blessed" );
    is( reftype($entry->data), reftype($deep), "reftype" );
    is_deeply(
        $entry->data,
        {%$deep, bar => KiokuDB::Entry->new( class => "KiokuDB_Test_Bar", data => {%$bar}, object => $bar ) },
        "is_deeply"
    );

    my $sl = $l->live_objects->new_scope;

    my $expanded = $l->expand_object($entry);

    isa_ok( $expanded, "KiokuDB_Test_Foo", "expanded object" );
    isnt( refaddr($expanded), refaddr($deep), "refaddr doesn't equal" );
    isnt( refaddr($expanded), refaddr($entry->data), "refaddr doesn't entry data refaddr" );
    is_deeply( $expanded, $deep, "is_deeply" );
}


done_testing;
