#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Scalar::Util qw(refaddr reftype blessed);
use Storable qw(dclone);

use KiokuDB::TypeMap::Entry::Callback;
use KiokuDB::TypeMap::Entry::Ref;
use KiokuDB::TypeMap::Resolver;
use KiokuDB::Collapser;
use KiokuDB::Linker;
use KiokuDB::LiveObjects;
use KiokuDB::Backend::Hash;

use Tie::RefHash;

{
    package KiokuDB_Test_Foo;
    use Moose;

    has bar => ( is => "rw" );

    package KiokuDB_Test_Bar;
    use Moose;

    has blah => ( is => "rw" );
}

tie my %h, 'Tie::RefHash';

$h{KiokuDB_Test_Bar->new( blah => "two" )} = "bar";

my $obj = KiokuDB_Test_Foo->new(
    bar => \%h,
);

for my $i ( 0, 1 ) {
    my $tr = KiokuDB::TypeMap::Resolver->new(
        typemap => KiokuDB::TypeMap->new(
            entries => {
                'Tie::RefHash' => KiokuDB::TypeMap::Entry::Callback->new(
                    intrinsic => $i,
                    collapse  => "STORABLE_freeze",
                    expand    => sub {
                        my ( $class, @args ) = @_;
                        my $self = (bless [], $class);
                        $self->STORABLE_thaw(0, @args);
                        return $self;
                    },
                ),
                ARRAY => KiokuDB::TypeMap::Entry::Ref->new,
                HASH  => KiokuDB::TypeMap::Entry::Ref->new,
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

    my $sv = $v->live_objects->new_scope;
    my $sl = $l->live_objects->new_scope;

    my ( $buffer, @ids ) = $v->collapse( objects => [ $obj ] );

    my $entries = $buffer->_entries;

    is( scalar(@ids), 1, "one root set ID" );

    my $copy = dclone($entries);

    $l->live_objects->register_entry( $_->id => $_ ) for values %$entries;

    my $loaded = $l->expand_object($copy->{$ids[0]});

    isa_ok( $loaded, "KiokuDB_Test_Foo" );

    is( ref(my $h = $loaded->bar), "HASH", "KiokuDB_Test_Foo->bar is a hash" );

    isa_ok( tied(%$h), "Tie::RefHash", "tied to Tie::RefHash" );
}


done_testing;
