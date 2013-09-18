# NAME

DBIx::Class::Sims - The addition of simulating data to DBIx::Class

# SYNOPSIS

Within your schema class:

    __PACKAGE__->load_components('Sims');

Within your resultsources, specify the sims generation rules for columns that
need specified.

    __PACKAGE__->add_columns(
      ...
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
        sim => {
          func => sub {
            return String::Random::random_string('.' x 10);
          },
        },
      },
      ...
    );

Later:

    $schema->deploy({
      add_drop_table => 1,
    });
    $schema->load_sims(
      $specification,
      ?$additional_constraints,
      ?$hooks,
    );

# PURPOSE

Generating test data for non-simplistic databases is extremely hard, especially
as the schema grows and changes. Designing scenarios should be doable by only
specifying the minimal elements actually used in the test with the test being
resilient to any changes in the schema that don't affect the elements specified.
This includes changes like adding a new parent table, new required child tables,
and new non-NULL columns to the table being tested.

# DESCRIPTION

This is a [DBIx::Class](http://search.cpan.org/perldoc?DBIx::Class) component that adds a single method (generate\_sims) to
[DBIx::Class::Schema](http://search.cpan.org/perldoc?DBIx::Class::Schema).

# METHODS

## $rv = $schema->load\_sims( $spec, ?$constraints, ?$hooks )

This method will load the rows requested in `$spec`, plus any additional rows
necessary to make those rows work. This includes any parent rows (as defined by
`belongs_to`) and per any constraints defined in `$constraints`. If need-be,
you can pass in hooks (as described below) to manipulate the data.

load\_sims does all of its work within a call to ["txn\_do" in DBIx::Class::Schema](http://search.cpan.org/perldoc?DBIx::Class::Schema#txn\_do).
If anything goes wrong, load\_sims will rethrow the error after the transaction
is rolled back.

This, of course, assumes that the tables you are working with support
transactions. (I'm looking at you, MyISAM!) If they do not, that is on you.

### Return value

This will return a hash of arrays of hashes. This will match the `$spec`,
except that where the `$spec` has a requested set of things to make, the return
will have the primary columns.

Examples:

If you have a table foo with "id" as the primary column and you requested:

    {
      Foo => [
        { name => 'bar' },
      ],
    }

You will receive back (assuming the next id value is 1):

    {
      Foo => [
        { id => 1 },
      ],
    }

If you have a table foo with "name" and "type" as the primary columns and you
requested:

    {
      Foo => [
        { children => [ {} ] },
      ],
    }

You will receive back (assuming the next type value is 'blah'):

    {
      Foo => [
        { name => 'bar', type => 'blah' },
      ],
    }

# SPECIFICATION

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

If a column is a belongs\_to relationship name, then the row associated with that
relationship specifier will be used. This is how you would specify a specific
parent-child relationship. (Otherwise, a random choice will be made as to which
parent to use, creating one as necessary if possible.) The dots will be followed
as far as necessary.

Columns that have not been specified will be populated in one of two ways. The
first is if the database has a default value for it. Otherwise, you can specify
the `sim` key in the column\_info for that column. This is a new key that is not
used by any other component.

(Please see ["add\_columns" in DBIx::Class::ResultSource](http://search.cpan.org/perldoc?DBIx::Class::ResultSource#add\_columns) for more info.) 

__NOTE__: The keys of the outermost hash are resultsource names. The keys within
the row-specific hashes are either columns or relationships. Not resultsources.

# CONSTRAINTS

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

# HOOKS

Most people will never need to use this. But, some schema definitions may have
reasons that prevent a clean simulating with this module. For example, there may
be application-managed sequences. To that end, you may specify the following
hooks:

- preprocess

    This receives `$name, $source, $spec` and expects nothing in return. `$spec`
    is the hashref that will be passed to `<$schema-`resultset($name)->create()>>.
    This hook is expected to modify `$spec` as needed.

- postprocess

    This receives `$name, $source, $row` and expects nothing in return. This hook
    is expected to modify the newly-created row object as needed.

# DBIx::Class::Fixtures

[DBIx::Class::Fixtures](http://search.cpan.org/perldoc?DBIx::Class::Fixtures) is another way to load data into a database. Unlike
this module, [DBIx::Class::Fixtures](http://search.cpan.org/perldoc?DBIx::Class::Fixtures) approaches the problem by loading the same
data every time. This is complementary because some tables (such as lookup
tables of countries) want to be seeded with the same data every time. The ideal
solution would be to have a set of tables loaded with fixtures and another set
of tables loaded with sims.

# SEE ALSO

[DBIx::Class](http://search.cpan.org/perldoc?DBIx::Class), [DBIx::Class::Fixtures](http://search.cpan.org/perldoc?DBIx::Class::Fixtures)

# AUTHOR

- Rob Kinyon <rob.kinyon@gmail.com>

# LICENSE

Copyright (c) 2013 Rob Kinyon. All Rights Reserved.
This is free software, you may use it and distribute it under the same terms
as Perl itself.
