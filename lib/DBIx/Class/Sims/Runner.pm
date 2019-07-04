package DBIx::Class::Sims::Runner;

use 5.010_001;

use strictures 2;

use DDP;

use Data::Compare qw( Compare );
use Hash::Merge qw( merge );
use Scalar::Util qw( blessed reftype );
use String::Random qw( random_regex );

use DBIx::Class::Sims::Item;
use DBIx::Class::Sims::Source;
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

  $self->{sources} = {};

  $self->{is_fk} = {};
  foreach my $name ( $self->schema->sources ) {
    my $source = $self->{source}{$name} = DBIx::Class::Sims::Source->new(
      name   => $name,
      runner => $self,
    );

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
  my ($source, $item) = @_;

  foreach my $comp (@{$self->{create_stack}}) {
    next unless $source->name eq $comp->[0];
    next unless Compare($item->spec, $comp->[1]);
    return 1;
  }
  return;
}
sub add_item {
  my $self = shift;
  my ($source, $item) = @_;
  push @{$self->{create_stack}}, [ $source->name, MyCloner::clone($item->spec) ];
}
sub remove_item {
  my $self = shift;
  my ($source, $item) = @_;
  pop @{$self->{create_stack}};
}

sub schema { shift->{schema} }
sub driver { shift->schema->storage->dbh->{Driver}{Name} }
sub is_oracle { shift->driver eq 'Oracle' }
sub datetime_parser { shift->schema->storage->datetime_parser }

sub set_allow_pk_to {
  my ($target, $source) = @_;
  if (ref $source) {
    if (blessed($target)) {
      ($target->spec->{__META__} //= {})->{allow_pk_set_value}
        = ($source->spec->{__META__} // {})->{allow_pk_set_value};
    }
    else {
      ($target->{__META__} //= {})->{allow_pk_set_value}
        = ($source->spec->{__META__} // {})->{allow_pk_set_value};
    }
  } else {
    if (blessed($target)) {
      ($target->spec->{__META__} //= {})->{allow_pk_set_value} = $source;
    }
    else {
      ($target->{__META__} //= {})->{allow_pk_set_value} = $source;
    }
  }
}

sub create_search {
  my $self = shift;
  my ($rs, $name, $cond) = @_;

  $cond = $cond->spec if blessed($cond);

  # Handle the FKs, particularly the FKs of the FKs. Tests for this line:
  # * t/grandchild.t "Find grandparent by DBIC row"
  #
  # XXX: Do we need to receive the deferred_fks() here? What should we do with
  # them if we do? Why can we ignore them if we don't?
  #
  # This is commented out because of explanation below.
  #$self->fix_fk_dependencies($name, $cond);

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

  # This for-loop shouldn't exist. Instead, we should be able to use
  # fix_fk_dependencies() above. However, that breaks in mysterious ways.
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
  my ($source, $item) = @_;

  my (%child_deps);
  RELATIONSHIP:
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    unless ( $is_fk->($rel_info) ) {
      if ($item->spec->{$rel_name}) {
        $child_deps{$rel_name} = delete $item->spec->{$rel_name};
      }
    }
  }

  return \%child_deps;
}

sub fix_fk_dependencies {
  my $self = shift;
  my ($source, $item) = @_;

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
  RELATIONSHIP:
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    unless ( $is_fk->($rel_info) ) {
      next RELATIONSHIP;
    }

    next RELATIONSHIP unless $self->{reqs}{$source->name}{$rel_name};

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);

    my $fk_name = $short_source->($rel_info);
    my $rs = $self->schema->resultset($fk_name);

    if (!$self->{allow_relationship_column_names}) {
      if ($col ne $rel_name && exists $item->spec->{$col}) {
        die "Cannot use column $col - use relationship $rel_name";
      }
    }

    my $cond;
    my $proto = delete($item->spec->{$rel_name}) // delete($item->spec->{$col});
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
            $source, $rel_name, $$proto, $fkcol,
          ),
        };
      }
      else {
        die "Unsure what to do about @{[$source->name]}->$rel_name():" . np($proto);
      }
    }

    # If the child's column is within a UK, add a check to the $rs that ensures
    # we cannot pick a parent that's already being used.
    my @constraints = $self->unique_constraints_containing($source, $col);
    if (@constraints) {
      # First, find the inverse relationship. If it doesn't exist or if there
      # is more than one, then die.
      my @inverse = $self->find_inverse_relationships(
        $source->name, $rel_name, $fk_name, $fkcol,
      );
      if (@inverse == 0) {
        die "Cannot find an inverse relationship for @{[$source->name]}->${rel_name}\n";
      }
      elsif (@inverse > 1) {
        die "Too many inverse relationships for @{[$source->name]}->${rel_name} ($fk_name / $fkcol)\n" . np(@inverse);
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

    warn "Looking for @{[$source->name]}->$rel_name(".np($cond).")\n" if $ENV{SIMS_DEBUG};

    my $parent;
    unless ($meta->{create}) {
      $parent = $rs->search(undef, { rows => 1 })->single;

      # This occurs when a FK condition was specified, but the column is
      # nullable. We want to defer these because self-referential values need
      # to be set after creation.
      if (!$parent && $col_info->{is_nullable}) {
        $cond = DBIx::Class::Sims::Item->new(
          spec => $cond,
        );
        $item->spec->{$col} = undef;
        set_allow_pk_to($cond, $item);
        $deferred_fks{$rel_name} = $cond;
        next RELATIONSHIP;
      }
    }
    unless ($parent) {
      my $fk_item = DBIx::Class::Sims::Item->new(
        spec => MyCloner::clone($cond),
      );
      set_allow_pk_to($fk_item, $item);
      my $fk_source = DBIx::Class::Sims::Source->new(
        name   => $fk_name,
        runner => $self,
      );
      $parent = $self->create_item($fk_source, $fk_item);
    }
    $item->spec->{$col} = $parent->get_column($fkcol);
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
  my ($source, $column) = @_;

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
    my $col_def = $_;
    ! grep { $column ne $_ } @$col_def
  } @uniques;
}

sub find_by_unique_constraints {
  my $self = shift;
  my ($source, $item) = @_;

  my @uniques = map {
    [ $source->unique_constraint_columns($_) ]
  } $source->unique_constraint_names();

  my $rs = $self->schema->resultset($source->name);
  my $searched = {};
  foreach my $unique (@uniques) {
    # If there are specified values for all the columns in a specific unqiue constraint ...
    next if grep { ! exists $item->spec->{$_} } @$unique;

    # ... then add that to the list of potential values to search.
    my %criteria;
    foreach my $colname (@{$unique}) {
      my $value = $item->spec->{$colname};
      if (ref($value) eq 'SCALAR') {
        $value = $self->convert_backreference(
          $source, $colname, $$value,
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
    push @{$self->{duplicates}{$source->name}}, {
      criteria => $searched,
      found    => { $row->get_columns },
    };
    return $row;
  }
  return;
}

sub convert_backreference {
  my $self = shift;
  my ($source, $attr, $proto, $default_method) = @_;

  my ($table, $idx, $methods) = ($proto =~ /(.+)\[(\d+)\](?:\.(.+))?$/);
  unless ($table && defined $idx) {
    die "Unsure what to do about @{[$source->name]}->$attr => $proto\n";
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
    die "No method to call at @{[$source->name]}->$attr => $proto\n";
  }
}

sub fix_values {
  my $self = shift;
  my ($source, $item) = @_;

  while (my ($attr, $value) = each %{$item->spec}) {
    # Decode a backreference
    if (ref($value) eq 'SCALAR') {
      $item->spec->{$attr} = $self->convert_backreference(
        $source, $attr, $$value,
      );
    }
  }
}

sub fix_child_dependencies {
  my $self = shift;
  my ($source, $row, $child_deps) = @_;

  # 1. If we have something, then:
  #   a. If it's not an array, then make it an array
  # 2. If we don't have something,
  #   a. Make an array with an empty item
  #   XXX This is more than one item would be supported
  # In all cases, make sure to add { $fkcol => $row->get_column($col) } to the
  # child's $item
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    next if $is_fk->($rel_info);
    next unless $child_deps->{$rel_name} // $self->{reqs}{$source->name}{$rel_name};

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);

    my $fk_name = $short_source->($rel_info);

    my @children;
    if ($child_deps->{$rel_name}) {
      my $n = DBIx::Class::Sims::Util->normalize_aoh($child_deps->{$rel_name});
      unless ($n) {
        die "Don't know what to do with @{[$source->name]}\->{$rel_name}\n\t".np($row);
      }
      @children = @{$n};
    }
    else {
      @children = ( ({}) x $self->{reqs}{$source->name}{$rel_name} );
    }

    # Need to ensure that $child_deps >= $self->{reqs}

    foreach my $child (@children) {
      set_allow_pk_to($child, 1);
      $child->{$fkcol} = $row->get_column($col);
      $self->add_child($fk_name, $fkcol, $child, $source->name);
    }
  }
}

sub fix_deferred_fks {
  my $self = shift;
  my ($source, $row, $deferred_fks) = @_;

  while (my ($rel_name, $cond) = each %$deferred_fks) {
    my $cond = $deferred_fks->{$rel_name};

    my $rel_info = $source->relationship_info($rel_name);

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);
    my $fk_name = $short_source->($rel_info);

    my $rs = $self->schema->resultset($fk_name);
    $rs = $self->create_search($rs, $fk_name, $cond);

    my $parent = $rs->search(undef, { rows => 1 })->first;
    unless ($parent) {
      my $fk_source = DBIx::Class::Sims::Source->new(
        name   => $fk_name,
        runner => $self,
      );
      $parent = $self->create_item($fk_source, $cond);
    }

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
  my ($source, $item) = @_;

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
    if ( exists $item->spec->{$col_name} ) {
      if (
           $is{in_pk}->($col_name)
        && !($item->spec->{__META__}//{})->{allow_pk_set_value}
        && !$source->column_info($col_name)->{is_nullable}
        && $source->column_info($col_name)->{is_auto_increment}
      ) {
        my $msg = sprintf(
          "Primary-key autoincrement non-null columns should not be hardcoded in tests (%s.%s = %s)",
          $source->name, $col_name, $item->spec->{$col_name},
        );
        warn $msg;
      }

      # This is the original way of specifying an override with a HASHREFREF.
      # Reflection has realized it was an unnecessary distinction to a parent
      # specification. Either it's a relationship hashref or a simspec hashref.
      # We can never have both. It will be deprecated.
      if ((reftype($item->spec->{$col_name}) // '') eq 'REF' &&
        (reftype(${$item->spec->{$col_name}}) // '') eq 'HASH' ) {
        warn "DEPRECATED: Use a regular HASHREF for overriding simspec. HASHREFREF will be removed in a future release.";
        $sim_spec = ${ delete $item->spec->{$col_name} };
      }
      elsif (
        (reftype($item->spec->{$col_name}) // '') eq 'HASH' &&
        # Assume a blessed hash is a DBIC object
        !blessed($item->spec->{$col_name}) &&
        # Do not assume we understand something to be inflated/deflated
        !$source->column_info($col_name)->{_inflate_info}
      ) {
        $sim_spec = delete $item->spec->{$col_name};
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
          $item->spec->{$col_name} = undef;
          next;
        }
      }

      if (exists $sim_spec->{values}) {
        $sim_spec->{value} = delete $sim_spec->{values};
      }

      if ( ref($sim_spec->{func} // '') eq 'CODE' ) {
        $item->spec->{$col_name} = $sim_spec->{func}->($info);
      }
      elsif ( exists $sim_spec->{value} ) {
        if (ref($sim_spec->{value} // '') eq 'ARRAY') {
          my @v = @{$sim_spec->{value}};
          $item->spec->{$col_name} = $v[rand @v];
        }
        else {
          $item->spec->{$col_name} = $sim_spec->{value};
        }
      }
      elsif ( $sim_spec->{type} ) {
        my $meth = $self->{parent}->sim_type($sim_spec->{type});
        if ( $meth ) {
          $item->spec->{$col_name} = $meth->($info, $sim_spec, $self);
        }
        else {
          warn "Type '$sim_spec->{type}' is not loaded";
        }
      }
      else {
        if ( $is{numeric}->($info->{data_type})) {
          my $min = $sim_spec->{min} // 0;
          my $max = $sim_spec->{max} // 100;
          $item->spec->{$col_name} = int(rand($max-$min))+$min;
        }
        elsif ( $is{decimal}->($info->{data_type})) {
          my $min = $sim_spec->{min} // 0;
          my $max = $sim_spec->{max} // 100;
          $item->spec->{$col_name} = rand($max-$min)+$min;
        }
        elsif ( $is{string}->($info->{data_type})) {
          my $min = $sim_spec->{min} // 1;
          my $max = $sim_spec->{max} // $info->{data_length} // $info->{size} // $min;
          $item->spec->{$col_name} = random_regex(
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
      !$self->{is_fk}{$source->name}{$col_name}
    ) {
      if ( $is{numeric}->($info->{data_type})) {
        my $min = 0;
        my $max = 100;
        $item->spec->{$col_name} = int(rand($max-$min))+$min;
      }
      elsif ( $is{decimal}->($info->{data_type})) {
        my $min = 0;
        my $max = 100;
        $item->spec->{$col_name} = rand($max-$min)+$min;
      }
      elsif ( $is{string}->($info->{data_type})) {
        my $min = 1;
        my $max = $info->{data_length} // $info->{size} // $min;
        $item->spec->{$col_name} = random_regex(
          '\w' . "{$min,$max}"
        );
      }
      else {
        die "ERROR: @{[$source->name]}\.$col_name is not nullable, but I don't know how to handle $info->{data_type}\n";
      }
    }
  }

  # Oracle does not allow the "INSERT INTO x DEFAULT VALUES" syntax that DBIC
  # wants to use. Therefore, find a PK column and set it to NULL. If there
  # isn't one, complain loudly.
  if ($self->is_oracle && keys(%{$item->spec}) == 0) {
    my @pk_columns = grep {
      $is{in_pk}->($_)
    } $source->columns;

    die "Must specify something about some column or have a PK in Oracle"
      unless @pk_columns;

    # This will work even if there are multiple columns in the PK.
    $item->spec->{$pk_columns[0]} = undef;
  }
}

sub create_item {
  my $self = shift;
  my ($source, $item) = @_;

  # If, in the current stack of in-flight items, we've attempted to make this
  # exact item, die because we've obviously entered an infinite loop.
  if ($self->has_item($source, $item)) {
    die "ERROR: @{[$source->name]} (".np($item->spec).") was seen more than once\n";
  }
  $self->add_item($source, $item);

  my $before_fix = np($item->spec);
  $self->fix_columns($source, $item);
  my $after_fix = np($item->spec);

  # Don't keep going if we have already satisfy all UKs
  my $row = $self->find_by_unique_constraints($source, $item);
  if ($row && $ENV{SIMS_DEBUG}) {
    warn "Found duplicate in @{[$source->name]}:\n"
      . "\tbefore fix_columns (".np($before_fix).")\n"
      . "\tafter fix_columns (".np($after_fix).")\n";
  }

  $self->{hooks}{preprocess}->($source->name, $source->source, $item->spec);

  my ($child_deps) = $self->find_child_dependencies($source, $item);
  unless ($row) {
    my ($deferred_fks) = $self->fix_fk_dependencies($source, $item);
    $self->fix_values($source, $item);

    warn "Ensuring @{[$source->name]} (".np($item->spec).")\n" if $ENV{SIMS_DEBUG};
    $row = $self->find_by_unique_constraints($source, $item);
    unless ($row) {
      warn "Creating @{[$source->name]} (".np($item->spec).")\n" if $ENV{SIMS_DEBUG};
      $row = eval {
        my $to_create = MyCloner::clone($item->spec);
        delete $to_create->{__META__};
        $self->schema->resultset($source->name)->create($to_create);
      }; if ($@) {
        my $e = $@;
        warn "ERROR Creating @{[$source->name]} (".np($item->spec).")\n";
        die $e;
      }
      # This tracks everything that was created, not just what was requested.
      $self->{created}{$source->name}++;
    }

    $self->fix_deferred_fks($source, $row, $deferred_fks);
  }

  $self->fix_child_dependencies($source, $row, $child_deps);

  $self->{hooks}{postprocess}->($source->name, $source->source, $row);

  $self->remove_item($source, $item);

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

        my $source = DBIx::Class::Sims::Source->new(
          name   => $name,
          runner => $self,
        );

        while ( my $proto = shift @{$self->{spec}{$name}} ) {
          my $item = DBIx::Class::Sims::Item->new(
            source => $source,
            spec   => $proto,
          );

          if ($self->{allow_pk_set_value}) {
            set_allow_pk_to($item->spec, 1);
          }

          my $row = do {
            no strict;

            # DateTime objects print too big in SIMS_DEBUG mode, so provide a
            # good way for DDP to print them nicely.
            local *{'DateTime::_data_printer'} = sub { shift->iso8601 }
              unless DateTime->can('_data_printer');

            $self->create_item($source, $item);
          };

          if ($self->{initial_spec}{$name}{$item->spec}) {
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
