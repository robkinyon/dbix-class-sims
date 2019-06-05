package DBIx::Class::Sims::Runner;

use 5.010_001;

use strictures 2;

use DDP;

use Data::Compare qw( Compare );
use Hash::Merge qw( merge );
use Scalar::Util qw( blessed reftype );
use String::Random qw( random_regex );

use DBIx::Class::Sims::Util ();

###### FROM HERE ######
# These are utility methods to help navigate the rel_info hash.
my $is_fk = sub { return exists $_[0]{attrs}{is_foreign_key_constraint} };
my $short_source = sub {
  (my $x = $_[0]{source}) =~ s/.*:://;
  return $x;
};

my $cond = sub {
  my $x = $_[0]{cond};
  if (reftype($x) eq 'CODE') {
    $x = $x->({
      foreign_alias => 'foreign',
      self_alias => 'self',
    });
  }
  if (reftype($x) ne 'HASH') {
    die "cond is not a HASH\n" . np($_[0]);
  }
  return $x;
};

# ribasushi says: at least make sure the cond is a hashref (not guaranteed)
my $self_fk_cols = sub { map {/^self\.(.*)/; $1} values %{$cond->($_[0])} };
my $self_fk_col  = sub { ($self_fk_cols->(@_))[0] };
my $foreign_fk_cols = sub { map {/^foreign\.(.*)/; $1} keys %{$cond->($_[0])} };
my $foreign_fk_col  = sub { ($foreign_fk_cols->(@_))[0] };
###### TO HERE ######

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->{is_fk} = {};
  foreach my $name ( $self->schema->sources ) {
    my $source = $self->schema->source($name);

    $self->{reqs}{$name} //= {};
    foreach my $rel_name ( $source->relationships ) {
      my $rel_info = $source->relationship_info($rel_name);

      if ($is_fk->($rel_info)) {
        $self->{reqs}{$name}{$rel_name} = 1;
        $self->{is_fk}{$name}{$_} = 1 for $self_fk_cols->($rel_info);
      }
    }
  }

  $self->{created}    = {};
  $self->{duplicates} = {};

  $self->{create_stack} = [];

  return;
}

sub has_item {
  my $self = shift;
  my ($name, $item) = @_;

  foreach my $comp (@{$self->{create_stack}}) {
    next unless $name eq $comp->[0];
    next unless Compare($item, $comp->[1]);
    return 1;
  }
  return;
}
sub add_item {
  my $self = shift;
  my ($name, $item) = @_;
  push @{$self->{create_stack}}, [ $name, MyCloner::clone($item) ];
}
sub remove_item {
  my $self = shift;
  my ($name, $item) = @_;
  pop @{$self->{create_stack}};
}

sub schema { shift->{schema} }
sub driver { shift->schema->storage->dbh->{Driver}{Name} }
sub datetime_parser { shift->schema->storage->datetime_parser }

sub set_allow_pk_to {
  my ($target, $source) = @_;
  if (ref $source) {
    ($target->{__META__} //= {})->{allow_pk_set_value}
      = ($source->{__META__} // {})->{allow_pk_set_value};
  } else {
    ($target->{__META__} //= {})->{allow_pk_set_value} = $source;
  }
}

sub create_search {
  my $self = shift;
  my ($rs, $name, $cond) = @_;

  my $source = $self->schema->source($name);
  my %cols = map { $_ => 1 } $source->columns;
  my $search = {
    (map {
      'me.' . $_ => $cond->{$_}
    } grep {
      # Make sure this column exists and is an actual value. Assumption is that
      # a non-reference is a value and a reference is a sims-spec.
      exists $cols{$_} && !reftype($cond->{$_})
    } keys %$cond)
  };
  $rs = $rs->search($search);

  foreach my $rel_name ($source->relationships) {
    next unless exists $cond->{$rel_name};
    next unless (reftype($cond->{$rel_name}) // '') eq 'HASH';

    my %search = map {
      ;"$rel_name.$_" => $cond->{$rel_name}{$_}
    } grep {
      # Nested relationships are "automagically handled."
      !ref $cond->{$rel_name}{$_}
    } keys %{$cond->{$rel_name}};

    $rs = $rs->search(\%search, { join => $rel_name });
  }

  return $rs;
}

sub find_child_dependencies {
  my $self = shift;
  my ($name, $item) = @_;

  my (%child_deps);
  my $source = $self->schema->source($name);
  RELATIONSHIP:
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    unless ( $is_fk->($rel_info) ) {
      if ($item->{$rel_name}) {
        $child_deps{$rel_name} = delete $item->{$rel_name};
      }
    }
  }

  return \%child_deps;
}

sub fix_fk_dependencies {
  my $self = shift;
  my ($name, $item) = @_;

  # 1. If we have something, then:
  #   a. If it's a scalar, then, COND = { $fk => scalar }
  #   b. Look up the row by COND
  #   c. If the row is not there and the FK is nullable, defer til later.
  #      This let's us deal with self-referential FKs
  #   d. If the row is not there and it is NOT nullable, then $create_item
  # 2. If we don't have something and the column is non-nullable, then:
  #   a. If rows exists, pick a random one.
  #   b. If rows don't exist, $create_item->($fksrc, {})
  my (%deferred_fks);
  my $source = $self->schema->source($name);
  RELATIONSHIP:
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    unless ( $is_fk->($rel_info) ) {
      next RELATIONSHIP;
    }

    next RELATIONSHIP unless $self->{reqs}{$name}{$rel_name};

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);

    my $fk_name = $short_source->($rel_info);
    my $rs = $self->schema->resultset($fk_name);

    if (!$self->{allow_relationship_column_names}) {
      if ($col ne $rel_name && exists $item->{$col}) {
        die "Cannot use column $col - use relationship $rel_name";
      }
    }

    my $cond;
    my $proto = delete($item->{$rel_name}) // delete($item->{$col});
    if ($proto) {
      # Assume anything blessed is blessed into DBIC.
      if (blessed($proto)) {
        $cond = { $fkcol => $proto->$fkcol };
      }
      # Assume any hashref is a Sims specification
      elsif (ref($proto) eq 'HASH') {
        $cond = $proto
      }
      # Assume any unblessed scalar is a column value.
      elsif (!ref($proto)) {
        $cond = { $fkcol => $proto };
      }
      # Use a referenced row
      elsif (ref($proto) eq 'SCALAR') {
        $cond = {
          $fkcol => $self->convert_backreference(
            $name, $rel_name, $$proto, $fkcol,
          ),
        };
      }
      else {
        die "Unsure what to do about $name->$rel_name():" . np($proto);
      }
    }

    # If the child's column is within a UK, add a check to the $rs that ensures
    # we cannot pick a parent that's already being used.
    my @constraints = $self->unique_constraints_containing($name, $col);
    if (@constraints) {
      # First, find the inverse relationship. If it doesn't exist or if there
      # is more than one, then die.
      my @inverse = $self->find_inverse_relationships(
        $name, $rel_name, $fk_name, $fkcol,
      );
      if (@inverse == 0) {
        die "Cannot find an inverse relationship for ${name}->${rel_name}\n";
      }
      elsif (@inverse > 1) {
        die "Too many inverse relationships for ${name}->${rel_name} ($fk_name / $fkcol)\n" . np(@inverse);
      }

      # We cannot add this relationship to the $cond because that would result
      # in an infinite loop. So, restrict the $rs here.
      $rs = $rs->search(
        { join('.', $inverse[0]{rel}, $inverse[0]{col}) => undef },
        { join => $inverse[0]{rel} },
      );
    }

    my $col_info = $source->column_info($col);
    if ( $cond ) {
      $rs = $self->create_search($rs, $fk_name, $cond);
    }
    elsif ( $col_info->{is_nullable} ) {
      next RELATIONSHIP;
    }
    else {
      $cond = {};
    }

    my $meta = delete $cond->{__META__} // {};

    warn "Looking for $name->$rel_name(".np($cond).")\n" if $ENV{SIMS_DEBUG};

    my $parent;
    unless ($meta->{create}) {
      $parent = $rs->search(undef, { rows => 1 })->single;

      # This occurs when a FK condition was specified, but the column is
      # nullable. We want to defer these because self-referential values need
      # to be set after creation.
      if (!$parent && $col_info->{is_nullable}) {
        $item->{$col} = undef;
        set_allow_pk_to($cond, $item);
        $deferred_fks{$rel_name} = $cond;
        next RELATIONSHIP;
      }
    }
    unless ($parent) {
      my $fk_item = MyCloner::clone($cond);
      set_allow_pk_to($fk_item, $item);
      $parent = $self->create_item($fk_name, $fk_item);
    }
    $item->{$col} = $parent->get_column($fkcol);
  }

  return \%deferred_fks;
}

{
  my %pending;
  my %added_by;
  sub are_columns_equal {
    my $self = shift;
    my ($src, $row, $compare) = @_;
    foreach my $col ($self->schema->source($src)->columns) {
      next if $self->{is_fk}{$src}{$col};

      next unless exists $row->{$col};
      return unless exists $compare->{$col};
      return if $compare->{$col} ne $row->{$col};
    }
    return 1;
  };

  sub add_child {
    my $self = shift;
    my ($src, $fkcol, $row, $adder) = @_;
    # If $row has the same keys (other than parent columns) as another row
    # added by a different parent table, then set the foreign key for this
    # parent in the existing row.
    foreach my $compare (@{$self->{spec}{$src}}) {
      next if exists $added_by{$adder} && exists $added_by{$adder}{$compare};
      if ($self->are_columns_equal($src, $row, $compare)) {
        $compare->{$fkcol} = $row->{$fkcol};
        return;
      }
    }

    push @{$self->{spec}{$src}}, $row;
    $added_by{$adder} //= {};
    $added_by{$adder}{$row} = !!1;
    $pending{$src} = 1;
  }

  sub has_pending { keys %pending != 0; }
  sub delete_pending { delete $pending{$_[1]}; }
  sub clear_pending { %pending = (); }
}

sub find_inverse_relationships {
  my $self = shift;
  my ($parent, $rel_to_child, $child, $fkcol) = @_;

  my $fksource = $self->schema->source($child);

  my @inverses;
  foreach my $rel_name ( $fksource->relationships ) {
    my $rel_info = $fksource->relationship_info($rel_name);

    # Skip relationships that aren't back towards the table we're coming from.
    next unless $short_source->($rel_info) eq $parent;

    # Assumption: We don't need to verify the $fkcol because there shouldn't be
    # multiple relationships on different columns between the same tables. This
    # is likely to be violated, but only by badly-designed schemas.

    push @inverses, {
      rel => $rel_name,
      col => $foreign_fk_col->($rel_info),
    };
  }

  return @inverses;
}

sub unique_constraints_containing {
  my $self = shift;
  my ($name, $column) = @_;

  my $source = $self->schema->source($name);
  my @uniques = map {
    [ $source->unique_constraint_columns($_) ]
  } $source->unique_constraint_names();

  # Only return true if the unique constraint is solely built from the column.
  # When we handle multi-column relationships, then we will need to handle the
  # situation where the relationship's columns are the UK.
  #
  # The situation where the UK has multiple columns, one of which is the the FK,
  # is potentially undecideable.
  return grep {
    my $coldef = $_;
    ! grep { $column ne $_ } @$coldef
  } @uniques;
}

sub find_by_unique_constraints {
  my $self = shift;
  my ($name, $item) = @_;

  my $source = $self->schema->source($name);
  my @uniques = map {
    [ $source->unique_constraint_columns($_) ]
  } $source->unique_constraint_names();

  my $rs = $self->schema->resultset($name);
  my $searched = {};
  foreach my $unique (@uniques) {
    # If there are specified values for all the columns in a specific unqiue constraint ...
    next if grep { ! exists $item->{$_} } @$unique;

    # ... then add that to the list of potential values to search.
    my %criteria;
    foreach my $colname (@{$unique}) {
      my $value = $item->{$colname};
      if (ref($value) eq 'SCALAR') {
        $value = $self->convert_backreference(
          $name, $colname, $$value,
        );
      }
      my $classname = blessed($value);
      if ( $classname && $classname->isa('DateTime') ) {
        $value = $self->datetime_parser->format_datetime($value);
      }

      $criteria{$colname} = $value;
    }

    $rs = $rs->search(\%criteria);
    $searched = merge($searched, \%criteria);
  }

  return unless keys %$searched;
  my $row = $rs->search(undef, { rows => 1 })->first;
  if ($row) {
    push @{$self->{duplicates}{$name}}, {
      criteria => $searched,
      found    => { $row->get_columns },
    };
    return $row;
  }
  return;
}

sub convert_backreference {
  my $self = shift;
  my ($name, $attr, $proto, $default_method) = @_;

  my ($table, $idx, $methods) = ($proto =~ /(.+)\[(\d+)\](?:\.(.+))?$/);
  unless ($table && defined $idx) {
    die "Unsure what to do about $name->$attr => $proto\n";
  }
  unless (exists $self->{rows}{$table}) {
    die "No rows in $table to reference\n";
  }
  unless (exists $self->{rows}{$table}[$idx]) {
    die "Not enough ($idx) rows in $table to reference\n";
  }

  if ($methods) {
    my @chain = split '\.', $methods;
    my $obj = $self->{rows}{$table}[$idx];
    $obj = $obj->$_ for @chain;
    return $obj;
  }
  elsif ($default_method) {
    return $self->{rows}{$table}[$idx]->$default_method;
  }
  else {
    die "No method to call at $name->$attr => $proto\n";
  }
}

sub fix_values {
  my $self = shift;
  my ($name, $item) = @_;

  while (my ($attr, $value) = each %{$item}) {
    # Decode a backreference
    if (ref($value) eq 'SCALAR') {
      $item->{$attr} = $self->convert_backreference(
        $name, $attr, $$value,
      );
    }
  }
}

sub fix_child_dependencies {
  my $self = shift;
  my ($name, $row, $child_deps) = @_;

  # 1. If we have something, then:
  #   a. If it's not an array, then make it an array
  # 2. If we don't have something,
  #   a. Make an array with an empty item
  #   XXX This is more than one item would be supported
  # In all cases, make sure to add { $fkcol => $row->get_column($col) } to the
  # child's $item
  my $source = $self->schema->source($name);
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    next if $is_fk->($rel_info);
    next unless $child_deps->{$rel_name} // $self->{reqs}{$name}{$rel_name};

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);

    my $fk_name = $short_source->($rel_info);

    my @children;
    if ($child_deps->{$rel_name}) {
      my $n = DBIx::Class::Sims::Util->normalize_aoh($child_deps->{$rel_name});
      unless ($n) {
        die "Don't know what to do with $name\->{$rel_name}\n\t".np($row);
      }
      @children = @{$n};
    }
    else {
      @children = ( ({}) x $self->{reqs}{$name}{$rel_name} );
    }

    # Need to ensure that $child_deps >= $self->{reqs}

    foreach my $child (@children) {
      set_allow_pk_to($child, 1);
      $child->{$fkcol} = $row->get_column($col);
      $self->add_child($fk_name, $fkcol, $child, $name);
    }
  }
}

sub fix_deferred_fks {
  my ($self, $name, $row, $deferred_fks) = @_;

  my $source = $self->schema->source($name);
  while (my ($rel_name, $cond) = each %$deferred_fks) {
    my $cond = $deferred_fks->{$rel_name};

    my $rel_info = $source->relationship_info($rel_name);

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);
    my $fk_name = $short_source->($rel_info);

    my $rs = $self->schema->resultset($fk_name);
    $rs = $self->create_search($rs, $fk_name, $cond);

    my $parent = $rs->search(undef, { rows => 1 })->first;
    $parent = $self->create_item($fk_name, $cond) unless $parent;

    $row->$col($parent->get_column($fkcol));
  }
  $row->update if $row->get_dirty_columns;
}

my %types = (
  numeric => {( map { $_ => 1 } qw(
    tinyint smallint mediumint bigint
    int integer int1 int2 int3 int4 int8 middleint
    bool boolean
  ))},
  decimal => {( map { $_ => 1 } qw(
    float float4 float8
    real
    double
    decimal dec
    numeric
    fixed
  ))},
  string => {( map { $_ => 1 } qw(
    char varchar varchar2
    binary varbinary
    text tinytext mediumtext longtext long
    blob tinyblob mediumblob longblob
  ))},
  # These will be unhandled
  #datetime => [qw(
  #  date
  #  datetime
  #  timestamp
  #  year
  #)],
  #unknown => [qw(
  #  enum set bit json
  #  geometry point linestring polygon
  #  multipoint multilinestring multipolygon geometrycollection
  #)],
);

sub fix_columns {
  my $self = shift;
  my ($name, $item) = @_;

  my $source = $self->schema->source($name);

  my %is = (
    in_pk => sub {
      my $n = shift;
      grep {
        $_ eq $n
      } $source->primary_columns;
    },
    in_uk => sub {
      my $n = shift;
      grep {
        $_ eq $n
      } map {
        $source->unique_constraint_columns($_)
      } $source->unique_constraint_names;
    },
  );
  foreach my $type (keys %types) {
    $is{$type} = sub {
      my $t = shift;
      return exists $types{$type}{$t};
    };
  }

  foreach my $col_name ( $source->columns ) {
    my $sim_spec;
    if ( exists $item->{$col_name} ) {
      if (
           $is{in_pk}->($col_name)
        && !($item->{__META__}//{})->{allow_pk_set_value}
        && !$source->column_info($col_name)->{is_nullable}
        && $source->column_info($col_name)->{is_auto_increment}
      ) {
        my $msg = sprintf(
          "Primary-key autoincrement non-null columns should not be hardcoded in tests (%s.%s = %s)",
          $name, $col_name, $item->{$col_name},
        );
        warn $msg;
      }

      # This is the original way of specifying an override with a HASHREFREF.
      # Reflection has realized it was an unnecessary distinction to a parent
      # specification. Either it's a relationship hashref or a simspec hashref.
      # We can never have both. It will be deprecated.
      if ((reftype($item->{$col_name}) // '') eq 'REF' &&
        (reftype(${$item->{$col_name}}) // '') eq 'HASH' ) {
        warn "DEPRECATED: Use a regular HASHREF for overriding simspec. HASHREFREF will be removed in a future release.";
        $sim_spec = ${ delete $item->{$col_name} };
      }
      elsif (
        (reftype($item->{$col_name}) // '') eq 'HASH' &&
        # Assume a blessed hash is a DBIC object
        !blessed($item->{$col_name}) &&
        # Do not assume we understand something to be inflated/deflated
        !$source->column_info($col_name)->{_inflate_info}
      ) {
        $sim_spec = delete $item->{$col_name};
      }
      # Pass the value along to DBIC - we don't know how to deal with it.
      else {
        next;
      }
    }

    my $info = $source->column_info($col_name);

    $sim_spec //= $info->{sim};
    if ( ref($sim_spec // '') eq 'HASH' ) {
      if ( exists $sim_spec->{null_chance} && $info->{is_nullable} ) {
        # Add check for not a number
        if ( rand() < $sim_spec->{null_chance} ) {
          $item->{$col_name} = undef;
          next;
        }
      }

      if (exists $sim_spec->{values}) {
        $sim_spec->{value} = delete $sim_spec->{values};
      }

      if ( ref($sim_spec->{func} // '') eq 'CODE' ) {
        $item->{$col_name} = $sim_spec->{func}->($info);
      }
      elsif ( exists $sim_spec->{value} ) {
        if (ref($sim_spec->{value} // '') eq 'ARRAY') {
          my @v = @{$sim_spec->{value}};
          $item->{$col_name} = $v[rand @v];
        }
        else {
          $item->{$col_name} = $sim_spec->{value};
        }
      }
      elsif ( $sim_spec->{type} ) {
        my $meth = $self->{parent}->sim_type($sim_spec->{type});
        if ( $meth ) {
          $item->{$col_name} = $meth->($info, $sim_spec, $self);
        }
        else {
          warn "Type '$sim_spec->{type}' is not loaded";
        }
      }
      else {
        if ( $is{numeric}->($info->{data_type})) {
          my $min = $sim_spec->{min} // 0;
          my $max = $sim_spec->{max} // 100;
          $item->{$col_name} = int(rand($max-$min))+$min;
        }
        elsif ( $is{decimal}->($info->{data_type})) {
          my $min = $sim_spec->{min} // 0;
          my $max = $sim_spec->{max} // 100;
          $item->{$col_name} = rand($max-$min)+$min;
        }
        elsif ( $is{string}->($info->{data_type})) {
          my $min = $sim_spec->{min} // 1;
          my $max = $sim_spec->{max} // $info->{data_length} // $info->{size} // $min;
          $item->{$col_name} = random_regex(
            '\w' . "{$min,$max}"
          );
        }
      }
    }
    # If it's not nullable, doesn't have a default value and isn't part of a
    # primary key (could be auto-increment) or part of a unique key or part of a
    # foreign key, then generate a value for it.
    elsif (
      !$info->{is_nullable} &&
      !exists $info->{default_value} &&
      !$is{in_pk}->($col_name) &&
      !$is{in_uk}->($col_name) &&
      !$self->{is_fk}{$name}{$col_name}
    ) {
      if ( $is{numeric}->($info->{data_type})) {
        my $min = 0;
        my $max = 100;
        $item->{$col_name} = int(rand($max-$min))+$min;
      }
      elsif ( $is{decimal}->($info->{data_type})) {
        my $min = 0;
        my $max = 100;
        $item->{$col_name} = rand($max-$min)+$min;
      }
      elsif ( $is{string}->($info->{data_type})) {
        my $min = 1;
        my $max = $info->{data_length} // $info->{size} // $min;
        $item->{$col_name} = random_regex(
          '\w' . "{$min,$max}"
        );
      }
      else {
        die "ERROR: $name\.$col_name is not nullable, but I don't know how to handle $info->{data_type}\n";
      }
    }
  }

  # Oracle does not allow the "INSERT INTO x DEFAULT VALUES" syntax that DBIC
  # wants to use. Therefore, find a PK column and set it to NULL. If there
  # isn't one, complain loudly.
  if ($self->driver eq 'Oracle' && keys(%$item) == 0) {
    my @pk_columns = grep {
      $is{in_pk}->($_)
    } $source->columns;

    die "Must specify something about some column or have a PK in Oracle"
      unless @pk_columns;

    # This will work even if there are multiple columns in the PK.
    $item->{$pk_columns[0]} = undef;
  }
}

sub create_item {
  my $self = shift;
  my ($name, $item) = @_;

  # If, in the current stack of in-flight items, we've attempted to make this
  # exact item, die because we've obviously entered an infinite loop.
  if ($self->has_item($name, $item)) {
    die "ERROR: $name (".np($item).") was seen more than once\n";
  }
  $self->add_item($name, $item);

  $self->fix_columns($name, $item);

  # Don't keep going if we have already satisfy all UKs
  my $row = $self->find_by_unique_constraints($name, $item);

  my $source = $self->schema->source($name);
  $self->{hooks}{preprocess}->($name, $source, $item);

  my ($child_deps) = $self->find_child_dependencies($name, $item);
  unless ($row) {
    my ($deferred_fks) = $self->fix_fk_dependencies($name, $item);
    $self->fix_values($name, $item);

    warn "Ensuring $name (".np($item).")\n" if $ENV{SIMS_DEBUG};
    $row = $self->find_by_unique_constraints($name, $item);
    unless ($row) {
      warn "Creating $name (".np($item).")\n" if $ENV{SIMS_DEBUG};
      $row = eval {
        my $to_create = MyCloner::clone($item);
        delete $to_create->{__META__};
        $self->schema->resultset($name)->create($to_create);
      }; if ($@) {
        my $e = $@;
        warn "ERROR Creating $name (".np($item).")\n";
        die $e;
      }
      # This tracks everything that was created, not just what was requested.
      $self->{created}{$name}++;
    }

    $self->fix_deferred_fks($name, $row, $deferred_fks);
  }

  $self->fix_child_dependencies($name, $row, $child_deps);

  $self->{hooks}{postprocess}->($name, $source, $row);

  $self->remove_item($name, $item);

  return $row;
}

sub run {
  my $self = shift;

  return $self->schema->txn_do(sub {
    $self->{rows} = {};
    my %still_to_use = map { $_ => 1 } keys %{$self->{spec}};
    while (1) {
      foreach my $name ( @{$self->{toposort}} ) {
        next unless $self->{spec}{$name};
        delete $still_to_use{$name};

        while ( my $item = shift @{$self->{spec}{$name}} ) {
          if ($self->{allow_pk_set_value}) {
            set_allow_pk_to($item, 1);
          }
          my $row = $self->create_item($name, $item);

          if ($self->{initial_spec}{$name}{$item}) {
            push @{$self->{rows}{$name} //= []}, $row;
          }
        }

        $self->delete_pending($name);
      }

      last unless $self->has_pending();
      $self->clear_pending();
    }

    # Things were passed in, but don't exist in the schema.
    if (!$self->{ignore_unknown_tables} && %still_to_use) {
      my $msg = "The following names are in the spec, but not the schema:\n";
      $msg .= join ',', sort keys %still_to_use;
      $msg .= "\n";
      die $msg;
    }

    return $self->{rows};
  });
}

1;
__END__
