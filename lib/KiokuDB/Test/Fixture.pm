package KiokuDB::Test::Fixture;
use Moose::Role;

use Test::More;
use Test::Exception;

sub _lives_and_ret (&;$) {
    my ( $sub, @args ) = @_;

    my @ret;
    my $wrapped = sub { @ret = $sub->() };

    local $Test::Builder::Level = $Test::Builder::Level + 2;
    &lives_ok($wrapped, @args);

    return ( ( @ret == 1 ) ? $ret[0] : @ret );
}

use namespace::clean -except => 'meta';

requires qw(create verify);

sub sort { 0 }

sub required_backend_roles { return () }

has populate_ids => (
    isa => "ArrayRef[Str]",
    is  => "rw",
    predicate => "has_populate_ids",
    clearer   => "clear_populate_ids",
);

sub populate {
    my $self = shift;

    {
        my $s = $self->new_scope;

        my @objects = $self->create;

        my @ids = $self->store_ok(@objects);

        $self->populate_ids(\@ids);
    }

    $self->no_live_objects;
}

sub name {
    my $self = shift;
    my $class = ref($self) || $self;
    $class =~ s{KiokuDB::Test::Fixture::}{};
    return $class;
}

sub skip_fixture {
    my ( $self, $reason, $count ) = @_;

    skip $self->name . " fixture ($reason)", $count || 1
}

sub precheck {
    my $self = shift;

    my $backend = $self->backend;

    if ( $backend->does("KiokuDB::Backend::Role::Broken") ) {
        foreach my $fixture ( $backend->skip_fixtures ) {
            $self->skip_fixture("broken backend") if $fixture eq ref($self) or $fixture eq $self->name;
        }
    }

    my @missing;

    role: foreach my $role ( $self->required_backend_roles ) {
        foreach my $role_fmt ( $role, "KiokuDB::Backend::Role::$role", "KiokuDB::Backend::$role" ) {
            next role if $backend->does($role_fmt) or $backend->can("serializer") and $backend->serializer->does($role_fmt);
        }
        push @missing, $role;
    }

    if ( @missing ) {
        $_ =~ s/^KiokuDB::Backend::Role::// for @missing;
        $self->skip_fixture("Backend does not implement required roles (@missing)")
    }
}

sub run {
    my $self = shift;

    SKIP: {
        local $Test::Builder::Level = $Test::Builder::Level + 1;

        $self->precheck;

        $self->clear_live_objects;

        is_deeply( [ $self->live_objects ], [ ], "no live objects at start of " . $self->name . " fixture" );
        is_deeply( [ $self->live_entries ], [ ], "no live entries at start of " . $self->name . " fixture" );

        lives_ok {
            local $Test::Builder::Level = $Test::Builder::Level - 1;
            $self->txn_do(sub {
                my $s = $self->new_scope;
                $self->populate;
            });
            $self->verify;
        } "no error in fixture";

        is_deeply( [ $self->live_objects ], [ ], "no live objects at end of " . $self->name . " fixture" );
        is_deeply( [ $self->live_entries ], [ ], "no live entries at end of " . $self->name . " fixture" );

        $self->clear_live_objects;
    }
}

has get_directory => (
    isa => "CodeRef|Str",
    is  => "ro",
);

has directory => (
    is  => "ro",
    isa => "KiokuDB",
    lazy_build => 1,
    handles => [qw(
        lookup exists
        store
        insert update delete

        clear_live_objects

        backend
        linker
        collapser

        search
        simple_search
        backend_search

        is_root
        set_root
        unset_root

        all_objects
        root_set
        scan
        grep

        new_scope

        txn_do

        object_to_id
        objects_to_ids
    )],
);

sub _build_directory {
    my $self = shift;
    my $method = $self->get_directory or die "either 'directory' or 'get_directory' is required";
    return $self->$method;
}

sub live_objects {
    shift->directory->live_objects->live_objects
}

sub live_entries {
    shift->directory->live_objects->live_entries
}


sub update_live_objects {
    my $self = shift;

    _lives_and_ret { $self->update( $self->live_objects ) } "updated live objects";
}

sub store_ok {
    my ( $self, @objects ) = @_;

    local $Test::Builder::Level = 1;

    _lives_and_ret { $self->store( @objects ) } "stored " . scalar(grep { ref } @objects) . " objects";
}

sub update_ok {
    my ( $self, @objects ) = @_;

    _lives_and_ret { $self->update( @objects ) } "updated " . scalar(@objects) . " objects";
}

sub insert_ok {
    my ( $self, @objects ) = @_;

    _lives_and_ret { $self->insert( @objects ) } "inserted " . scalar(@objects) . " objects";
}

sub delete_ok {
    my ( $self, @objects ) = @_;

    _lives_and_ret { $self->delete( @objects ) } "deleted " . scalar(@objects) . " objects";
}

sub lookup_ok {
    my ( $self, @ids ) = @_;

    my @ret;
    _lives_and_ret { @ret = $self->lookup( @ids ) } "lookup " . scalar(@ids) . " objects";

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is( scalar(grep { ref } @ret), scalar(@ids), "all lookups succeeded" );

    return ( ( @ret == 1 ) ? $ret[0] : @ret );
}

sub exists_ok {
    my ( $self, @ids ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is( scalar(grep { $_ } $self->exists(@ids)), scalar(@ids), "[@ids] exist in DB" );
}

sub root_ok {
    my ( $self, @objects ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is( scalar(grep { $_ } $self->is_root(@objects)), scalar(@objects), "[@{[ $self->objects_to_ids(@objects) ]}] are in the root set" );
}

sub not_root_ok {
    my ( $self, @objects ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is( scalar(grep { not $_ } $self->is_root(@objects)), scalar(@objects), "[@{[ $self->objects_to_ids(@objects) ]}] aren't in the root set" );
}

sub deleted_ok {
    my ( $self, @ids ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is( scalar(grep { !$_ } $self->exists(@ids)), scalar(@ids), "@ids do not exist in DB" );
}

sub lookup_obj_ok {
    my ( $self, $id, $class ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    ok( my $obj = $self->lookup($id), "lookup $id" );

    isa_ok( $obj, $class ) if $class;

    return $obj;
}

sub no_live_objects {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $fail;

    my @l = $self->live_objects;
    my @e;

    my $failed;

    $failed++ unless is( scalar(@l), 0, "no live objects" );

    unless ( $self->directory->live_objects->txn_scope ) {
        # no live objects should imply no live entries
        # however, under keep_entries a txn stack is maintained
        $failed++ unless is( scalar(@e), 0, "no live entries" );
        @e = $self->directory->live_objects->live_entries;
    }

    if ( $failed ) {
        diag "live objects: " . join ", ", map { $self->object_to_id($_) . " ($_)" } @l if @l;
        diag "live entries: " . join ", ", map { $_->id . " (" . $_->class . ")" } @e;

        #use Scalar::Util qw(weaken);
        #weaken($_) for @l;

        $self->directory->live_objects->clear;

        #use Devel::FindRef;
        #my $track = Devel::FindRef::track(@l);
        #warn $track;
        #my ( @ids ) = map { hex } ( $track =~ /by \w+\(0x([a-z0-9]+)\)/ );
        #warn Data::Dumper::Dumper(map { Devel::FindRef::ptr2ref($_) } @ids);
    }
}

sub no_live_entries {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my @e = $self->directory->live_objects->live_entries;

    unless ( is( scalar(@e), 0, "no live entries" ) ) {
        diag "live entries: " . join ", ", map { $_->id . " (" . $_->class . ")" } @e;

        $self->directory->live_objects->clear;
    }
}

sub live_objects_are {
    my ( $self, @objects ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is_deeply( [ sort $self->live_objects ], [ sort @objects ], "correct live objects" );
}

sub txn_lives {
    my ( $self, $code, @args ) = @_;

    lives_ok {
        $self->txn_do(sub {
            my $s = $self->new_scope;
            $code->(@_);
        }, @args);
    } "transaction finished without errors";
}

__PACKAGE__

__END__
