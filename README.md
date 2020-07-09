![CI](https://github.com/robkinyon/dbix-class-sims/workflows/CI/badge.svg)

# NAME

DBIx::Class::Sims - The addition of simulating data to DBIx::Class

# SYNOPSIS (CLASS VERSION)

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

# SYNOPSIS (COMPONENT VERSION)

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

# PURPOSE

Generating test data for non-simplistic databases is extremely hard, especially
as the schema grows and changes. Designing scenarios **should** be doable by only
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

# DESCRIPTION

This is a [DBIx::Class](https://metacpan.org/pod/DBIx::Class) component that adds a few methods to your
[DBIx::Class::Schema](https://metacpan.org/pod/DBIx::Class::Schema) object. These methods make it much easier to create data
for testing purposes (though, obviously, it's not limited to just test data).

Alternately, it can be used as a class method vs. a component, if that fits your
needs better.

# METHODS

## load\_sims

`$rv, $addl? = $schema->load_sims( $spec, ?$opts )`
`$rv, $addl? = DBIx::Class::Sims->load_sims( $schema, $spec, ?$opts )`

This method will load the rows requested in `$spec`, plus any additional rows
necessary to make those rows work. This includes any parent rows (as defined by
`belongs_to`) and per any constraints defined in `$opts->{constraints}`. If
need-be, you can pass in hooks (as described below) to manipulate the data.

load\_sims does all of its work within a call to ["txn\_do" in DBIx::Class::Schema](https://metacpan.org/pod/DBIx::Class::Schema#txn_do).
If anything goes wrong, load\_sims will rethrow the error after the transaction
is rolled back.

This, of course, assumes that the tables you are working with support
transactions. (I'm looking at you, MyISAM!) If they do not, that is on you.

### Return value

This returns one or two values, depending on if you call load\_sims in a scalar
or array context.

The first value is a hash of arrays of hashes. This will match the `$spec`,
except that where the `$spec` has a requested set of things to make, the return
will have the DBIx::Class::Row objects that were created.

Note that you do not get back the objects for anything other than the objects
specified at the top level.

This second value is a hashref with additional items that may be useful. It may
contain:

- error

    This will contain any error that happened while trying to create the rows.

    This is most useful when `die_on_failure` is set to 0.

- seed

    This is the random seed that was used in this run. If you set the seed in the
    opts parameter in the load\_sims call, it will be that value. Otherwise, it will
    be set to a usefully random value for you. It will be different every time even
    if you call load\_sims multiple times within the same process in the same second.

- created

    This is a hashref containing a count of each source that was created. This is
    different from the first return value in that this lists everything created, not
    just what was requested. It also only has counts, not the actual rows.

- duplicates

    This is a hashref containing a list for each source of all the duplicates that
    were found when creating rows for that source. For each duplicate found, there
    will be an entry that specifies the criteria used to find that duplicate and the
    row in the database that was found.

    The list will be ordered by when the duplicate was found, but that ordering will
    **NOT** be stable across different runs unless the same `seed` is used.

## set\_sim\_type

`$class_or_obj->set_sim_type({ $name => $handler, ... });`
`$class_or_obj->set_sim_type([ [ $name, $regex, $handler ], ... ]);`

This method will set the handler for the `$name` sim type. The `$handler` must
be a reference to a subroutine. You may pass in as many name/handler pairs as you
like.

You may alternately pass in an arrayref of triplets. This allows you to use a
regex to match the provided type. `$name` will be returned when the user
introspects the list of loaded sim types. `$regex` will be used when finding the
type to handle this column. `$handler` must be a reference to a subroutine.

You cannot set pairs and triplets in the same invocation.

This method may be called as a class or object method.

This method returns nothing.

`set_sim_types()` is an alias to this method.

## sim\_types

`$class_or_obj->sim_types();`

This method will return a sorted list of all registered sim types.

This method may be called as a class or object method.

## add\_sims

Given a `$schema`, source name, and pairs of column/sim\_type info, this
method will decorate the source's columns with appropriate sim types. This is
in lieu of adding the sim information to the column definition.

This method is only meant for usage as a class method. Do not use this method if
you load Sims as a component.

# SPECIFICATION

The specification can be passed along as a filename that contains YAML or JSON,
a string that contains YAML or JSON, or as a hash of arrays of hashes. The
structure should look like:

    {
      ResultSourceName => [
        {
          column => $value,
          column => $value,
          relationship => $parent_object,
          relationship => {
            column => $value,
          },
          'relationship.column' => $value,
          'rel1.rel2.rel3.column' => $value,
        },
      ],
    }

If a column is a belongs\_to relationship name, then the row associated with that
relationship specifier will be used. This is how you would specify a specific
parent-child relationship. (Otherwise, a random choice will be made as to which
parent to use, creating one as necessary if possible.) The dots will be followed
as far as necessary.

If a column's value is a hashref, then that will be treated as a sim entry.
Example:

    {
      Artist => [
        {
          name => { type => 'us_name' },
        },
      ],
    }

That will use the provided sim type 'us\_name'. This will override any sim entry
specified on the column. See ["SIM ENTRY"](#sim-entry) for more information.

Note: Before 0.300800, this behavior was triggered by a reference to a hashref.
That will still work, but is deprecated, throws a warning, and will be removed
in a future release.

Columns that have not been specified will be populated in one of two ways. The
first is if the database has a default value for it. Otherwise, you can specify
the `sim` key in the column\_info for that column. This is a new key that is not
used by any other component. See ["SIM ENTRY"](#sim-entry) for more information.

(Please see ["add\_columns" in DBIx::Class::ResultSource](https://metacpan.org/pod/DBIx::Class::ResultSource#add_columns) for details on column\_info)

**NOTE**: The keys of the outermost hash are resultsource names. The keys within
the row-specific hashes are either columns or relationships. Not resultsources.

## Reuse wherever possible

The Sims's normal behavior is to attempt to reuse whenever possible. The theory
is that if you didn't say you cared about something, you do **NOT** care about
that thing.

### Unique constraints

If a source has unique constraints defined, the Sims will use them to determine
if a new row with these values _can_ be created or not. If a row already
exists with these values for the unique constraints, then that row will be used
instead of creating a new one.

This is **REGARDLESS** of the values for the non-unique-constraint rows.

### Forcing creation of a parent

If you do not specify values for a parent (i.e., belongs\_to), then the first row
for that parent will be be used. If you don't care what values the parent has,
but you care that a different parent is used, then you can set the C<< __META__ >> key
as follows:

    $schema->load_sims({
      Album => {
        artist => { __META__ => { create => 1 } },
        name => 'Some name',
      }
    })

This will force the creation of a parent instead of reusing the parent.

**NOTE**: If the simmed values within the parent's class would result in values
that are the same across a unique constraint with an existing row, then that
row will be used. This just bypasses the "attempt to use the first parent".

## Alternatives

### Hard-coded number of things

If you only want N of a thing, not really caring just what the column values end
up being, you can take a shortcut:

    {
      ResultSourceName => 3,
    }

That will create 3 of that thing, taking all the defaults and sim'ed options as
exist.

This will also work if you want 3 of a child via a has\_many relationship. For
example, you can do:

    {
        Artist => {
            name => 'Someone Famous',
            albums => 240,
        },
    }

That will create 240 different albums for that artist, all with the defaults.

### Just one thing

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

### References

Let's say you have a table that's a child of two other tables. You can specify
that relationship as follows:

    {
        Parent1 => 1,
        Parent2 => {
            Child => {
                parent1 => \"Parent1[0]",
            },
        },
    }

That's a reference to a string with the tablename as a pseudo-array, then the
index into that array. This only works for rows that you are going to return
back from the `load_sims()` call.

This also only works for belongs\_to relationships. Since all parents are created
before all children, the Sims cannot back-reference into children.

## Notes

- Multiply-specified children

    Sometimes, you will have a table with more than one parent (q.v. t/t5.t for an
    example of this). If you specify a row for each parent and, in each parent,
    specify a child with the same characteristics, only one child will be created.
    The assumption is that you meant the same row.

    This does **not** apply to creating multiple rows with the same characteristics
    as children of the same parent. The assumption is that you meant to do that.

## Other uses of META

### Setting a condition in a spec

    $schema->load_sims({
      Album => {
        __META__ => {
          restriction => {
            cond  => { 'artist.name => { '!=' => 'Bob Dillon' } },
            extra => { join => 'artist' },
          },
        },
        name => 'Some name',
      }
    })

# OPTS

There are several possible options.

## allow\_set\_pk\_value

If this is false or omitted, then a warning will be emitted if a sims spec sets
a value for a column that is:

- in a primary key (either alone or with other columns)
- NOT NULLL
- set to auto\_increment

If this is true, then the warning is suppressed.

## constraints

The constraints can be passed along as a filename that contains YAML or JSON, a
string that contains YAML or JSON, or as a hash of arrays of hashes. The
structure should look like:

    {
      Person => {
        addresses => 2,
      },
    }

All the `belongs_to` relationships are automatically added to the constraints.
You can add additional constraints, as needed. The most common use for this will
be to add required child rows. For example, `Person->has_many('addresses')`
would normally mean that if you create a Person, no Address rows would be
created.  But, we could specify a constraint that says "Every person must have
at least 2 addresses." Now, whenever a Person is created, two Addresses will be
added along as well, if they weren't already created through some other
specification.

## die\_on\_failure

If set to 0, this will prevent a die when creating a row. Instead, you will be
responsible for checking `$additional->{error}` yourself.

This defaults to 1.

## seed

If set, this will be the srand() seed used for this invocation.

## toposort

This is passed directly to the call to `DBIx::Class::TopoSort->toposort`.

## hooks

Most people will never need to use this. But, some schema definitions may have
reasons that prevent a clean simulating with this module. For example, there may
be application-managed sequences. To that end, you may specify the following
hooks:

- preprocess

    This receives `$name, $source, $spec` and expects nothing in return. `$spec`
    is the hashref that will be passed to `$schema->resultset($name)->create()`.
    This hook is expected to modify `$spec` as needed.

- postprocess

    This receives `$name, $source, $row` and expects nothing in return. This hook
    is expected to modify the newly-created row object as needed.

# SIM ENTRY

To control how a column's values are simulated, add a "sim" entry in the
column\_info for that column. The sim entry is a hash that can have the followingkeys:

- value / values

    This behaves just like default\_value would behave, but doesn't require setting a
    default value on the column.

        sim => {
            value => 'The value to always use',
        },

    This can be either a string, number, or an arrayref of strings or numbers. If it
    is an arrayref, then a random choice from that array will be selected.

- type

    This labels the column as having a certain type. A type is registered using
    ["set\_sim\_type"](#set_sim_type). The type acts as a name for a function that's used to generate
    the value. See ["Types"](#types) for more information.

- min / max

    If the column is numeric, then the min and max bound the random value generated.
    If the column is a string, then the min and max are the length of the random
    value generated.

- func

    This is a function that is provided the column info. Its return value is used to
    populate the column.

- null\_chance

    If the column is nullable _and_ this is set _and_ it is a number between 0 and
    1, then if `rand()` is less than that number, the column will be set to null.
    Otherwise, the standard behaviors will apply.

    If the column is **not** nullable, this setting is ignored.

(Please see ["add\_columns" in DBIx::Class::ResultSource](https://metacpan.org/pod/DBIx::Class::ResultSource#add_columns) for details on column\_info)

## Types

The handler for a sim type will receive the column info (as defined in
["add\_columns" in DBIx::Class::ResultSource](https://metacpan.org/pod/DBIx::Class::ResultSource#add_columns)). From that, the handler returns the
value that will be used for this column.

Please see [DBIx::Class::Sims::Types](https://metacpan.org/pod/DBIx::Class::Sims::Types) for the list of included sim types.

# SEQUENCE OF EVENTS

When an item is created, the following actions are taken (in this order):

- 1 The columns are fixed up.

    This is where generated values are generated. After this is done, all the values
    that will be inserted into the database are now available.

    q.v. ["SIM ENTRY"](#sim-entry) for more information.

- 1 The preprocess hook fires.

    You can modify the hashref as necessary. This includes potentially changing what
    parent and/or child rows to associate with this row.

- 1 All foreign keys are resolved.

    If it's a parent relationship, the parent row will be found or created. If
    created, all parent rows will go through the same sequence of events as
    described here.

    If it's a child relationship, creation of the child rows will be deferred
    until later.

- 1 The row is found or created.

    It might be found by unique constraint or created.

- 1 All child relationships are handled

    Because they're a child relationship, they are deferred until the time that
    model is handled in the toposorted graph. They are not created now because
    they might associate with a different parent that has not been created yet.

- 1 The postprocess hook fires.

    Note that child rows are not guaranteed to exist yet.

# TODO

## Multi-column types

In some applications, columns like "state" and "zipcode" are correlated. Values
for one must be legal for the value in the other. The Sims currently has no way
of generating correlated columns like this.

This is most useful for saying "These 6 columns should be a coherent address".

## Allow a column to reference other columns

Sometimes, a column should alter its behavior based on other columns. A fullname
column may have the firstname and lastname columns concatenated, with other
things thrown in. Or, a zipcode column should only generate a zipcode that're
legal for the state.

Currently, the best place to handle this case is a preprocess hook.

# BUGS/SUGGESTIONS

This module is hosted on Github at
[https://github.com/robkinyon/dbix-class-sims](https://github.com/robkinyon/dbix-class-sims). Pull requests are strongly
encouraged.

# DBIx::Class::Fixtures

[DBIx::Class::Fixtures](https://metacpan.org/pod/DBIx::Class::Fixtures) is another way to load data into a database. Unlike
this module, [DBIx::Class::Fixtures](https://metacpan.org/pod/DBIx::Class::Fixtures) approaches the problem by loading the same
data every time. This is complementary because some tables (such as lookup
tables of countries) want to be seeded with the same data every time. The ideal
solution would be to have a set of tables loaded with fixtures and another set
of tables loaded with sims.

# SEE ALSO

[DBIx::Class](https://metacpan.org/pod/DBIx::Class), [DBIx::Class::Fixtures](https://metacpan.org/pod/DBIx::Class::Fixtures)

# AUTHOR

Rob Kinyon <rob.kinyon@gmail.com>

# LICENSE

Copyright (c) 2013 Rob Kinyon. All Rights Reserved.
This is free software, you may use it and distribute it under the same terms
as Perl itself.
