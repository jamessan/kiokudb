#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use KiokuDB::LinkChecker;
use KiokuDB::Backend::Hash;
use KiokuDB::Test::Fixture::ObjectGraph;
use KiokuDB;

my $dir = KiokuDB->new(
    backend => my $backend = KiokuDB::Backend::Hash->new(),
);

my $f = KiokuDB::Test::Fixture::ObjectGraph->new( directory => $dir );

$f->populate;

{
    my $l = KiokuDB::LinkChecker->new( backend => $backend );

    cmp_ok( $l->seen->size, '>', 0, "seen some entries" );
    cmp_ok( $l->missing->size, '==', 0, "no missing entries" );
}

$f->verify; # deletes putin, and removes the ref from Dubya

{
    my $l = KiokuDB::LinkChecker->new( backend => $backend );

    cmp_ok( $l->seen->size, '>', 0, "seen some entries" );
    cmp_ok( $l->missing->size, '==', 0, "no missing entries" );
}

my $deleted_id = do {
    my $s = $dir->new_scope;

    my $dubya = $dir->lookup($f->dubya);

    my $delete = $dubya->friends->[-1];

    my $id = $dir->object_to_id($delete);

    $dir->delete($delete);

    $id;
};

{
    my $l = KiokuDB::LinkChecker->new( backend => $backend );

    cmp_ok( $l->seen->size, '>', 0, "seen some entries" );
    cmp_ok( $l->missing->size, '==', 1, "one missing entry" );
    is_deeply( [ $l->missing->members ], [ $deleted_id ], "ID is correct" );
}


done_testing;
