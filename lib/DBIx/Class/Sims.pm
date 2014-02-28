# vim: set sw=2 ft=perl:
package DBIx::Class::Sims;

use 5.008_004;

use strict;
use warnings FATAL => 'all';

use Data::Walk qw( walk );
use DBIx::Class::TopoSort ();
use Hash::Merge qw( merge );
use List::Util qw( shuffle );
use List::MoreUtils qw( natatime );
use Scalar::Util qw( reftype );
use String::Random qw( random_regex );

our $VERSION = '0.300002';

{
  my %sim_types;

  sub set_sim_type {
    shift;
    my $types = shift;
    return unless ref($types||'') eq 'HASH';

    while ( my ($name, $meth) = each(%$types) ) {
      next unless ref($meth) eq 'CODE';

      $sim_types{$name} = $meth;
    }

    return;
  }
  BEGIN { *set_sim_types = \&set_sim_type; }

  sub sim_type {
    shift;

    return if @_ == 0;
    return $sim_types{$_[0]} if @_ == 1;
    return map { $sim_types{$_} } @_;
  }
  BEGIN { *sim_types = \&sim_type; }
}
use DBIx::Class::Sims::Types;

sub add_sims {
  my $class = shift;
  my ($schema, $source, @remainder) = @_;

  my $rsrc = $schema->source($source);
  my $it = natatime(2, @remainder);
  while (my ($column, $sim_info) = $it->()) {
    my $col_info = $schema->source($source)->column_info($column) || next;
    $col_info->{sim} = merge(
      $col_info->{sim} || {},
      $sim_info || {},
    );
  }

  return;
}
*add_sim = \&add_sims;

sub load_sims {
  my $self = shift;
  my $schema;
  if (ref($self) && $self->isa('DBIx::Class::Schema')) {
    $schema = $self;
  }
  else {
    $schema = shift(@_);
  }
  my ($spec_proto, $opts_proto) = @_;

  my $spec = expand_dots(normalize_input($spec_proto));
  my $opts = normalize_input($opts_proto || {});

  ###### FROM HERE ######
  # These are utility methods to help navigate the rel_info hash.
  my $is_fk = sub { return exists $_[0]{attrs}{is_foreign_key_constraint} };
  my $short_source = sub {
    (my $x = $_[0]{source}) =~ s/.*:://;
    return $x;
  };

  # ribasushi says: at least make sure the cond is a hashref (not guaranteed)
  my $self_fk_cols = sub { map {/^self\.(.*)/; $1} values %{$_[0]{cond}} };
  my $self_fk_col  = sub { ($self_fk_cols->(@_))[0] };
  my $foreign_fk_cols = sub { map {/^foreign\.(.*)/; $1} keys %{$_[0]{cond}} };
  my $foreign_fk_col  = sub { ($foreign_fk_cols->(@_))[0] };
  ###### TO HERE ######

  # 1. Ensure the belongs_to relationships are in $reqs
  # 2. Set the rel_info as the leaf in $reqs
  my $reqs = normalize_input($opts->{constraints} || {});
  my %is_foreign_key;
  foreach my $name ( $schema->sources ) {
    my $source = $schema->source($name);

    $reqs->{$name} ||= {};
    foreach my $rel_name ( $source->relationships ) {
      my $rel_info = $source->relationship_info($rel_name);

      if ($is_fk->($rel_info)) {
        $reqs->{$name}{$rel_name} = 1;
        $is_foreign_key{$name}{$_} = 1 for $self_fk_cols->($rel_info);
      }
    }
  }

  # 2: Create the rows in toposorted order
  my $hooks = $opts->{hooks} || {};
  $hooks->{preprocess}  ||= sub {};
  $hooks->{postprocess} ||= sub {};

  # Prepopulate column values (as appropriate)
  my %subs;
  $subs{fix_fk_dependencies} = sub {
    my ($name, $item) = @_;

    # 1. If we have something, then:
    #   a. If it's a scalar, then, COND = { $fk => scalar }
    #   b. Look up the row by COND
    #   c. If the row is not there, then $create_item->($fksrc, COND)
    # 2. If we don't have something and the column is non-nullable, then:
    #   a. If rows exists, pick a random one.
    #   b. If rows don't exist, $create_item->($fksrc, {})
    my %child_deps;
    my $source = $schema->source($name);
    foreach my $rel_name ( $source->relationships ) {
      my $rel_info = $source->relationship_info($rel_name);
      unless ( $is_fk->($rel_info) ) {
        if ($item->{$rel_name}) {
          $child_deps{$rel_name} = delete $item->{$rel_name};
        }
        next;
      }

      next unless $reqs->{$name}{$rel_name};

      my $col = $self_fk_col->($rel_info);
      my $fkcol = $foreign_fk_col->($rel_info);

      my $fk_src = $short_source->($rel_info);
      my $rs = $schema->resultset($fk_src);

      my $cond;
      if ( $item->{$rel_name} ) {
        $cond = delete $item->{$rel_name};
        if ( !ref($cond) ) {
          $cond = { $fkcol => $cond };
        }
      }
      elsif ( $item->{$col} ) {
        $cond = { $fkcol => $item->{$col} };
      }

      my $col_info = $source->column_info($col);
      if ( $cond ) {
        $rs = $rs->search($cond);
      }
      elsif ( $col_info->{is_nullable} ) {
        next;
      }
      else {
        $cond = {};
      }

      my $parent = $rs->first || $subs{create_item}->($fk_src, $cond);
      $item->{$col} = $parent->get_column($fkcol);
    }

    return \%child_deps;
  };
  {
    my %added_by;
    my $are_columns_equal = sub {
      my ($src, $row, $compare) = @_;
      foreach my $col ($schema->source($src)->columns) {
        next if $is_foreign_key{$src}{$col};

        next unless exists $row->{$col};
        return unless exists $compare->{$col};
        return if $compare->{$col} ne $row->{$col};
      }
      return 1;
    };
    $subs{add_child} = sub {
      my ($src, $fkcol, $row, $adder) = @_;
      # If $row has the same keys (other than parent columns) as another row
      # added by a different parent table, then set the foreign key for this
      # parent in the existing row.
      foreach my $name (keys %added_by) {
        next if $name eq $adder;
        foreach my $compare (@{$added_by{$name}}) {
          if ($are_columns_equal->($src, $row, $compare)) {
            $compare->{$fkcol} = $row->{$fkcol};
            return;
          }
        }
      }
      push @{$spec->{$src}}, $row;
      push @{$added_by{$adder} ||= []}, $row;
    };
  }
  $subs{fix_child_dependencies} = sub {
    my ($name, $row, $child_deps) = @_;

    # 1. If we have something, then:
    #   a. If it's not an array, then make it an array
    # 2. If we don't have something,
    #   a. Make an array with an empty item
    #   XXX This is more than one item would be supported
    # In all cases, make sure to add { $fkcol => $row->get_column($col) } to the
    # child's $item
    my $source = $schema->source($name);
    foreach my $rel_name ( $source->relationships ) {
      my $rel_info = $source->relationship_info($rel_name);
      next if $is_fk->($rel_info);
      next unless $child_deps->{$rel_name} || $reqs->{$name}{$rel_name};

      my $col = $self_fk_col->($rel_info);
      my $fkcol = $foreign_fk_col->($rel_info);

      my $fk_src = $short_source->($rel_info);

      # Need to ensure that $child_deps >= $reqs

      my @children = @{$child_deps->{$rel_name} || []};
      @children = ( ({}) x $reqs->{$name}{$rel_name} ) unless @children;
      foreach my $child (@children) {
        $child->{$fkcol} = $row->get_column($col);
        $subs{add_child}->($fk_src, $fkcol, $child, $name);
      }
    }
  };
  $subs{fix_columns} = sub {
    my ($name, $item) = @_;
    my $source = $schema->source($name);
    foreach my $col_name ( $source->columns ) {
      my $sim_spec;
      if ( exists $item->{$col_name} ) {
        if ((reftype($item->{$col_name}) || '') eq 'REF' &&
          reftype(${$item->{$col_name}}) eq 'HASH' ) {
          $sim_spec = ${ delete $item->{$col_name} };
        }
        # Pass the value along to DBIC - we don't know how to deal with it.
        else {
          next;
        }
      }

      my $info = $source->column_info($col_name);

      $sim_spec ||= $info->{sim};
      if ( ref($sim_spec || '') eq 'HASH' ) {
        if ( exists $sim_spec->{null_chance} && !$info->{nullable} ) {
          # Add check for not a number
          if ( rand() < $sim_spec->{null_chance} ) {
            $item->{$col_name} = undef;
            next;
          }
        }

        if ( ref($sim_spec->{func} || '') eq 'CODE' ) {
          $item->{$col_name} = $sim_spec->{func}->($info);
        }
        elsif ( exists $sim_spec->{value} ) {
          $item->{$col_name} = $sim_spec->{value};
        }
        elsif ( $sim_spec->{type} ) {
          my $meth = $self->sim_type($sim_spec->{type});
          if ( $meth ) {
            $item->{$col_name} = $meth->($info);
          }
          else {
            warn "Type '$sim_spec->{type}' is not loaded";
          }
        }
        else {
          if ( $info->{data_type} eq 'int' ) {
            my $min = $sim_spec->{min} || 0;
            my $max = $sim_spec->{max} || 100;
            $item->{$col_name} = int(rand($max-$min))+$min;
          }
          elsif ( $info->{data_type} eq 'varchar' ) {
            my $min = $sim_spec->{min} || 1;
            my $max = $sim_spec->{max} || $info->{data_length} || 255;
            $item->{$col_name} = random_regex(
              '\w' . "{$min,$max}"
            );
          }
        }
      }
    }
  };
  $subs{create_item} = sub {
    my ($name, $item) = @_;

    my $child_deps = $subs{fix_fk_dependencies}->($name, $item);
    $subs{fix_columns}->($name, $item);

    my $source = $schema->source($name);
    $hooks->{preprocess}->($name, $source, $item);
    my $row = $schema->resultset($name)->create($item);
    $hooks->{postprocess}->($name, $source, $row);

    $subs{fix_child_dependencies}->($name, $row, $child_deps);

    return $row;
  };

  # Create a lookup of the items passed in so we can return them back.
  my $initial_spec = {};
  foreach my $name (keys %$spec) {
    # Allow a number to be passed in
    if ( (reftype($spec->{$name})||'') ne 'ARRAY' ) {
      if ( !ref($spec->{$name}) ) {
        if ( $spec->{$name} =~ /^\d+$/ ) {
          $spec->{$name} = [ map { {} } 1 .. $spec->{$name} ];
        }
        # I don't know what to do with it.
        else {
          warn "Skipping $name - I don't know what to do!\n";
          delete $spec->{$name};
          next;
        }
      }
      # If they pass a hashref, wrap it in an arrayref.
      elsif ( reftype($spec->{$name}) eq 'HASH' ) {
        $spec->{$name} = [ $spec->{$name} ];
      }
      # I don't know what to do with it.
      else {
        warn "Skipping $name - I don't know what to do!\n";
        delete $spec->{$name};
        next;
      }
    }

    foreach my $item (@{$spec->{$name}}) {
      $initial_spec->{$name}{$item} = 1;
    }
  }

  my ($rows, $additional) = ({}, {});
  if (keys %{$spec}) {
    # Yes, this invokes srand() twice, once in implicitly in rand() and once
    # again right after. But, that's okay. We don't care what the seed is and
    # this allows DBIC to be called multiple times in the same process in the
    # same second without problems.
    $additional->{seed} = $opts->{seed} ||= rand(time & $$);
    srand($opts->{seed});

    $rows = $schema->txn_do(sub {
      my %rows;
      foreach my $name ( DBIx::Class::TopoSort->toposort($schema, %{$opts->{toposort} || {}}) ) {
        next unless $spec->{$name};

        while ( my $item = shift @{$spec->{$name}} ) {
          my $x = $subs{create_item}->($name, $item);
          push @{$rows{$name} ||= []}, $x if $initial_spec->{$name}{$item};
        }
      }

      return \%rows;
    });
  }

  if (wantarray) {
    return ($rows, $additional);
  }
  else {
    return $rows;
  }
}

use YAML::Any qw( LoadFile Load );
sub normalize_input {
  my ($proto) = @_;

  if ( ref($proto) ) {
    return $proto;
  }

  # Doing a stat on a filename with a newline throws an error.
  my $x = eval {
    if ( -e $proto ) {
      return LoadFile($proto);
    }
  };
  return $x if $x;

  return Load($proto);
}

sub expand_dots {
  my $struct = shift;

  walk sub {
    if ( ref($_) eq 'HASH' ) {
      foreach my $k ( keys %$_ ) {
        my $t = $_;
        while ( $k =~ /([^.]*)\.(.*)/ ) {
          $t->{$1} = { $2 => delete($t->{$k}) };
          $t = $t->{$1}; $k = $2;
        }
      }
    }
  }, $struct;

  return $struct;
}

1;
__END__

=head1 NAME

DBIx::Class::Sims - The addition of simulating data to DBIx::Class

=head1 SYNPOSIS (CLASS VERSION)

  DBIx::Class::Sims->add_sims(
      $schema, 'source_name',
      address => { type => 'us_address' },
      zip_code => { type => 'us_zipcode' },
      # ...
  );

  my $rows = DBIx::Class::Sims->load_sims($schema, {
    Table1 => [
      {}, # Take sims or default values for everything
      { # Override some values, take sim values for others
        column1 => 20,
        column2 => 'something',
      },
    ],
  });

=head1 SYNOPSIS (COMPONENT VERSION)

Within your schema class:

  __PACKAGE__->load_components('Sims');

Within your resultsources, specify the sims generation rules for columns that
need specified.

  __PACKAGE__->add_columns(
    ...
    address => {
      data_type => 'varchar',
      is_nullable => 1,
      data_length => 10,
      sim => { type => 'us_address' },
    },
    zipcode => {
      data_type => 'varchar',
      is_nullable => 1,
      data_length => 10,
      sim => { type => 'us_zipcode' },
    },
    column1 => {
      data_type => 'int',
      is_nullable => 0,
      sim => {
        min => 10,
        max => 20,
      },
    },
    column2 => {
      data_type => 'varchar',
      is_nullable => 1,
      data_length => 10,
      default_value => 'foobar',
    },
    ...
  );

Later:

  $schema->deploy({
    add_drop_table => 1,
  });

  my $rows = $schema->load_sims({
    Table1 => [
      {}, # Take sims or default values for everything
      { # Override some values, take sim values for others
        column1 => 20,
        column2 => 'something',
      },
    ],
  });

=head1 PURPOSE

Generating test data for non-simplistic databases is extremely hard, especially
as the schema grows and changes. Designing scenarios B<should> be doable by only
specifying the minimal elements actually used in the test with the test being
resilient to any changes in the schema that don't affect the elements specified.
This includes changes like adding a new parent table, new required child tables,
and new non-NULL columns to the table being tested.

With Sims, you specify only what you care about. Any required parent rows are
automatically generated. If a row requires a certain number of child rows (all
artists must have one or more albums), that can be set as well. If a column must
have specific data in it (a US zipcode or a range of numbers), you can specify
that in the table definition.

And, in all cases, you can override anything.

=head1 DESCRIPTION

This is a L<DBIx::Class> component that adds a few methods to your
L<DBIx::Class::Schema> object. These methods make it much easier to create data
for testing purposes (though, obviously, it's not limited to just test data).

Alternately, it can be used as a class method vs. a component, if that fits your
needs better.

=head1 METHODS

=head2 load_sims

C<< $rv, $addl? = $schema->load_sims( $spec, ?$opts ) >>
C<< $rv, $addl? = DBIx::Class::Sims->load_sims( $schema, $spec, ?$opts ) >>

This method will load the rows requested in C<$spec>, plus any additional rows
necessary to make those rows work. This includes any parent rows (as defined by
C<belongs_to>) and per any constraints defined in C<$opts->{constraints}>. If
need-be, you can pass in hooks (as described below) to manipulate the data.

load_sims does all of its work within a call to L<DBIx::Class::Schema/txn_do>.
If anything goes wrong, load_sims will rethrow the error after the transaction
is rolled back.

This, of course, assumes that the tables you are working with support
transactions. (I'm looking at you, MyISAM!) If they do not, that is on you.

=head3 Return value

This returns one or two values, depending on if you call load_sims in a scalar
or array context.

The first value is a hash of arrays of hashes. This will match the C<$spec>,
except that where the C<$spec> has a requested set of things to make, the return
will have the DBIx::Class::Row objects that were created.

Note that you do not get back the objects for anything other than the objects
specified at the top level.

This second value is a hashref with additional items that may be useful. It may
contain:

=over 4

=item * seed

This is the random seed that was used in this run. If you set the seed in the
opts parameter in the load_sims call, it will be that value. Otherwise, it will
be set to a usefullly random value for you. It will be different every time even
if you call load_sims multiple times within the same process in the same second.

=back

=head2 set_sim_type

C<< $class_or_obj->set_sim_type({ $name => $handler, ... }); >>

This method will set the handler for the C<$name> sim type. The handler must be
a reference to a subroutine. You may pass in as many name/handler pairs as you
like.

This method may be called as a class or object method.

This method returns nothing.

C<set_sim_types()> is an alias to this method.

=head1 SPECIFICATION

The specification can be passed along as a filename that contains YAML or JSON,
a string that contains YAML or JSON, or as a hash of arrays of hashes. The
structure should look like:

  {
    ResultSourceName => [
      {
        column => $value,
        column => $value,
        relationship => {
          column => $value,
        },
        'relationship.column' => $value,
        'rel1.rel2.rel3.column' => $value,
      },
    ],
  }

If a column is a belongs_to relationship name, then the row associated with that
relationship specifier will be used. This is how you would specify a specific
parent-child relationship. (Otherwise, a random choice will be made as to which
parent to use, creating one as necessary if possible.) The dots will be followed
as far as necessary.

If a column's value is a reference to a hashref, then that will be treated as a
sim entry. Example:

  {
    Artist => [
      {
        name => \{ type => 'us_name' },
      },
    ],
  }

That will use the provided sim type 'us_name'. This will override any sim entry
specified on the column. See L</SIM ENTRY> for more information.

Columns that have not been specified will be populated in one of two ways. The
first is if the database has a default value for it. Otherwise, you can specify
the C<sim> key in the column_info for that column. This is a new key that is not
used by any other component. See L</SIM ENTRY> for more information.

(Please see L<DBIx::Class::ResultSource/add_columns> for details on column_info)

B<NOTE>: The keys of the outermost hash are resultsource names. The keys within
the row-specific hashes are either columns or relationships. Not resultsources.

=head2 Alternatives

=head3 Hard-coded number of things

If you only want N of a thing, not really caring just what the column values end
up being, you can take a shortcut:

  {
    ResultSourceName => 3,
  }

That will create 3 of that thing, taking all the defaults and sim'ed options as
exist.

=head3 Just one thing

If you are creating one of a thing and setting some of the values, you can skip
the arrayref and pass the hashref directly.

  {
    ResultSourceName => {
      column => $value,
      column => $value,
      relationship => {
        column => $value,
      },
      'relationship.column' => $value,
      'rel1.rel2.rel3.column' => $value,
    },
  }

And that will work exactly as expected.

=head2 Notes

=over 4

=item * Multiply-specified children

Sometimes, you will have a table with more than one parent (q.v. t/t5.t for an
example of this). If you specify a row for each parent and, in each parent,
specify a child with the same characteristics, only one child will be created.
The assumption is that you meant the same row.

This does B<not> apply to creating multiple rows with the same characteristics
as children of the same table. The assumption is that you meant to do that.

=back

=head1 OPTS

There are several possible options.

=head2 constraints

The constraints can be passed along as a filename that contains YAML or JSON, a
string that contains YAML or JSON, or as a hash of arrays of hashes. The
structure should look like:

  {
    Person => {
      addresses => 2,
    },
  }

All the C<belongs_to> relationships are automatically added to the constraints.
You can add additional constraints, as needed. The most common use for this will
be to add required child rows. For example, C<< Person->has_many('addresses') >>
would normally mean that if you create a Person, no Address rows would be
created.  But, we could specify a constraint that says "Every person must have
at least 2 addresses." Now, whenever a Person is created, two Addresses will be
added along as well, if they weren't already created through some other
specification.

=head2 seed

If set, this will be the srand() seed used for this invocation.

=head2 toposort

This is passed directly to the call to C<< DBIx::Class::TopoSort->toposort >>.

=head2 hooks

Most people will never need to use this. But, some schema definitions may have
reasons that prevent a clean simulating with this module. For example, there may
be application-managed sequences. To that end, you may specify the following
hooks:

=over 4

=item * preprocess

This receives C<$name, $source, $spec> and expects nothing in return. C<$spec>
is the hashref that will be passed to C<<$schema->resultset($name)->create()>>.
This hook is expected to modify C<$spec> as needed.

=item * postprocess

This receives C<$name, $source, $row> and expects nothing in return. This hook
is expected to modify the newly-created row object as needed.

=back

=head1 SIM ENTRY

To control how a column's values are simulated, add a "sim" entry in the
column_info for that column. The sim entry is a hash that can have the followingkeys:

=over 4

=item * value

This behaves just like default_value would behave, but doesn't require setting a
default value on the column.

  sim => {
      value => 'The value to always use',
  },

=item * type

This labels the column as having a certain type. A type is registered using
L</set_sim_type>. The type acts as a name for a function that's used to generate
the value. See L</Types> for more information.

=item * min / max

If the column is numeric, then the min and max bound the random value generated.
If the column is a string, then the min and max are the length of the random
value generated.

=item * func

This is a function that is provided the column info. Its return value is used to
populate the column.

=item * null_chance

If the column is nullable I<and> this is set I<and> it is a number between 0 and
1, then if C<rand()> is less than that number, the column will be set to null.
Otherwise, the standard behaviors will apply.

If the column is B<not> nullable, this setting is ignored.

=back

(Please see L<DBIx::Class::ResultSource/add_columns> for details on column_info)

=head2 Types

The handler for a sim type will receive the column info (as defined in
L<DBIx::Class::ResultSource/add_columns>). From that, the handler returns the
value that will be used for this column.

Please see L<DBIx::Class::Sims::Types> for the list of included sim types.

=head1 TODO

=head2 Multi-column types

In some applications, columns like "state" and "zipcode" are correlated. Values
for one must be legal for the value in the other. The Sims currently has no way
of generating correlated columns like this.

This is most useful for saying "These 6 columns should be a coherent address".

=head2 Allow a column to reference other columns

Sometimes, a column should alter its behavior based on other columns. A fullname
column may have the firstname and lastname columns concatenated, with other
things thrown in. Or, a zipcode column should only generate a zipcode that're
legal for the state.

=head1 BUGS/SUGGESTIONS

This module is hosted on Github at
L<https://github.com/robkinyon/dbix-class-sims>. Pull requests are strongly
encouraged.

=head1 DBIx::Class::Fixtures

L<DBIx::Class::Fixtures> is another way to load data into a database. Unlike
this module, L<DBIx::Class::Fixtures> approaches the problem by loading the same
data every time. This is complementary because some tables (such as lookup
tables of countries) want to be seeded with the same data every time. The ideal
solution would be to have a set of tables loaded with fixtures and another set
of tables loaded with sims.

=head1 SEE ALSO

L<DBIx::Class>, L<DBIx::Class::Fixtures>

=head1 AUTHOR

Rob Kinyon <rob.kinyon@gmail.com>

=head1 LICENSE

Copyright (c) 2013 Rob Kinyon. All Rights Reserved.
This is free software, you may use it and distribute it under the same terms
as Perl itself.

=cut
