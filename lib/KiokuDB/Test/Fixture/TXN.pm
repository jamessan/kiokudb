package KiokuDB::Test::Fixture::TXN;
use Moose;

use Test::More;
use Test::Exception;

use namespace::clean -except => 'meta';

extends qw(KiokuDB::Test::Fixture::Small);

use constant required_backend_roles => qw(TXN);

sub sort { 150 }

around populate => sub {
    my ( $next, $self, @args ) = @_;
    $self->txn_do(sub { $self->$next(@args) });
};

sub verify {
    my $self = shift;

    my $l = $self->directory->live_objects;

    $self->exists_ok($self->joe);

    my $keep = $self->directory->live_objects->keep_entries;

    {
        my $s = $self->new_scope;

        my $joe = $self->lookup_ok( $self->joe );

        is( $joe->name, "joe", "name attr" );

        my $entry = $l->objects_to_entries($joe);

        isa_ok( $entry, "KiokuDB::Entry" ) if $keep;

        lives_ok {
            $self->txn_do(sub {
                $joe->name("HALLO");
                $self->update_ok($joe);

                if ( $keep ) {
                    my $updated_entry = $l->objects_to_entries($joe);

                    isnt( $updated_entry, $entry, "entry updated" );
                    is( $updated_entry->prev, $entry, "parent of updated is orig" );
                }
            });
        } "successful transaction";

        if ( $keep ) {
            my $updated_entry = $l->objects_to_entries($joe);

            isnt( $updated_entry, $entry, "entry updated" );
            is( $updated_entry->prev, $entry, "parent of updated is orig" );
        }

        is( $joe->name, "HALLO", "name attr" );

        undef $joe;
    }

    $self->no_live_objects;

    {
        {
            my $s = $self->new_scope;

            my $joe = $self->lookup_ok( $self->joe );

            my $entry = $l->objects_to_entries($joe);

            isa_ok( $entry, "KiokuDB::Entry" ) if $keep;

            throws_ok {
                $self->txn_do(sub {
                    $joe->name("YASE");
                    $self->update_ok($joe);

                    if ( $keep ) {
                        my $updated_entry = $l->objects_to_entries($joe);

                        isnt( $updated_entry, $entry, "entry updated" );
                        is( $updated_entry->prev, $entry, "parent of updated is orig" );
                    }

                    die "foo";
                });
            } qr/foo/, "failed transaction";

            if ( $keep ) {
                my $updated_entry = $l->objects_to_entries($joe);

                is( $updated_entry, $entry, "entry rolled back" );
            }

            is( $joe->name, "YASE", "name not rolled back in live object" );

            undef $joe;
        }

        $self->no_live_objects;

        {
            my $s = $self->new_scope;

            my $joe = $self->lookup_ok( $self->joe );

            is( $joe->name, "HALLO", "name rolled back in DB" );

            undef $joe;
        }

        $self->no_live_objects;
    }

    # txn_do nesting should still work, even if nested transactions are not supported
    {
        {
            my $s = $self->new_scope;

            my $joe = $self->lookup_ok( $self->joe );

            is( $joe->name, "HALLO", "name attr" );

            my $entry = $l->objects_to_entries($joe);

            isa_ok( $entry, "KiokuDB::Entry" ) if $keep;

            throws_ok {
                $self->txn_do(sub {
                    $joe->name("lalalala");
                    $self->update_ok($joe);
                    $self->txn_do(sub {
                        $joe->name("oi");
                        $self->update_ok($joe);

                        if ( $keep ) {
                            my $updated_entry = $l->objects_to_entries($joe);

                            isnt( $updated_entry, $entry, "entry updated" );
                            is( $updated_entry->prev->prev, $entry, "parent of parent of updated is orig" );
                        }

                        die "foo";
                    });
                });
            } qr/foo/, "failed transaction";

            if ( $keep ) {
                my $updated_entry = $l->objects_to_entries($joe);

                is( $updated_entry, $entry, "entry rolled back" );
            }

            is( $joe->name, "oi", "name attr of object" );

            undef $joe;
        }

        $self->no_live_objects;

        {
            my $s = $self->new_scope;

            my $joe = $self->lookup_ok( $self->joe );

            is( $joe->name, "HALLO", "name rolled back in DB" );

            undef $joe;
        }

        $self->no_live_objects;
    }

    {
        $self->txn_do( scope => 1, body => sub {
            my $s = $self->new_scope;
            {
                my $s = $self->new_scope;

                my $joe = $self->lookup_ok( $self->joe );

                $joe->name("YASE");
                $self->update_ok($joe);
            }

            $self->no_live_entries
                unless $self->backend->does("KiokuDB::Backend::Role::TXN::Memory");
        });

        $self->no_live_entries
            unless $self->backend->does("KiokuDB::Backend::Role::TXN::Memory");
    }

    {
        {
            my $s = $self->new_scope;

            my $joe = $self->lookup_ok( $self->joe );

            throws_ok {
                $self->txn_do(sub {
                    $self->delete_ok($joe);
                    $self->deleted_ok($self->joe);
                    die "foo";
                });
            } qr/foo/, "failed transaction";

            $self->exists_ok($self->joe);

            undef $joe;
        }

        $self->no_live_objects;

        {
            my $s = $self->new_scope;

            $self->exists_ok($self->joe);

            $self->lookup_ok( $self->joe );
        }

        $self->no_live_objects;
    }

    {
        {
            my $s = $self->new_scope;

            throws_ok {
                $self->txn_do(sub {
                    $self->delete_ok($self->joe);
                    $self->deleted_ok($self->joe);
                    die "foo";
                });
            } qr/foo/, "failed transaction";

            $self->exists_ok($self->joe);
        }

        $self->no_live_objects;

        $self->exists_ok($self->joe);
    }

    {
        {
            my $s = $self->new_scope;

            $self->txn_do(sub {
                $self->delete_ok($self->joe);
                $self->deleted_ok($self->joe);
            });

            $self->deleted_ok($self->joe);
        }

        $self->no_live_objects;

        $self->deleted_ok($self->joe);
    }
}

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__
