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

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->{sources} = {};
  foreach my $name ( $self->schema->sources ) {
    $self->{sources}{$name} = DBIx::Class::Sims::Source->new(
      name   => $name,
      runner => $self,
    );

    $self->{reqs}{$name} //= {};
    foreach my $r ($self->{sources}{$name}->parent_relationships) {
      $self->{reqs}{$name}{$r->name} = 1;
    }
  }

  $self->{created}    = {};
  $self->{duplicates} = {};

  $self->{create_stack} = [];

  return;
}

sub has_item {
  my $self = shift;
  my ($item) = @_;

  foreach my $comp (@{$self->{create_stack}}) {
    next unless $item->source_name eq $comp->[0];
    next unless Compare($item->spec, $comp->[1]);
    return 1;
  }
  return;
}
sub add_item {
  my $self = shift;
  my ($item) = @_;
  push @{$self->{create_stack}}, [
    $item->source_name, MyCloner::clone($item->spec),
  ];
}
sub remove_item {
  my $self = shift;
  my ($item) = @_;
  pop @{$self->{create_stack}};
}

sub schema { shift->{schema} }
sub driver { shift->schema->storage->dbh->{Driver}{Name} }
sub is_oracle { shift->driver eq 'Oracle' }
sub datetime_parser { shift->schema->storage->datetime_parser }

# FIXME: This method is a mess. It needs to be completely rethought and,
# possibly, broken out into different versions.
sub create_search {
  my $self = shift;
  my ($rs, $name, $cond) = @_;

  # Handle the FKs, particularly the FKs of the FKs. Tests for this line:
  # * t/grandchild.t "Find grandparent by DBIC row"
  #
  # XXX: Do we need to receive the deferred_fks() here? What should we do with
  # them if we do? Why can we ignore them if we don't?
  #
  # This is commented out because of explanation below.
  #$self->fix_fk_dependencies($cond);

  # FIXME: This needs to handle ::Item properly, but not everything passed here
  # is an ::Item (yet). (Maybe never?)
  $cond = $cond->spec if blessed($cond);

  my $source = $self->{sources}{$name};
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
  #
  # FIXME: Using this for-loop times out the tests in t/self_refential.t
  #foreach my $rel_name (keys %{$source->relationships}) {
  # So, we use this one instead. This breaks encapsulation.
  foreach my $rel_name ($source->source->relationships) {
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
  my ($item) = @_;

  my (%child_deps);
  foreach my $r ( $item->source->child_relationships ) {
    if ($item->spec->{$r->name}) {
      $child_deps{$r->name} = delete $item->spec->{$r->name};
    }
  }

  return \%child_deps;
}

sub fix_fk_dependencies {
  my $self = shift;
  my ($item) = @_;

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
  foreach my $r ( $item->source->parent_relationships ) {
    next RELATIONSHIP unless $self->{reqs}{$item->source_name}{$r->name};

    my $col = $r->self_fk_col;
    my $fkcol = $r->foreign_fk_col;

    my $fk_name = $r->short_fk_source;
    my $rs = $self->schema->resultset($fk_name);

    if (!$self->{allow_relationship_column_names}) {
      if ($col ne $r->name && exists $item->spec->{$col}) {
        die "Cannot use column $col - use relationship @{[$r->name]}";
      }
    }

    my $cond;
    my $proto = delete($item->spec->{$r->name}) // delete($item->spec->{$col});
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
            $item->source, $r->name, $$proto, $fkcol,
          ),
        };
      }
      else {
        die "Unsure what to do about @{[$item->source_name]}\->@{[$r->name]}():" . np($proto);
      }
    }

    # If the child's column is within a UK, add a check to the $rs that ensures
    # we cannot pick a parent that's already being used.
    my @constraints = $item->source->unique_constraints_containing($col);
    if (@constraints) {
      # First, find the inverse relationship. If it doesn't exist or if there
      # is more than one, then die.
      my @inverse = $item->source->find_inverse_relationships(
        $self->{sources}{$fk_name}, $fkcol,
      );
      if (@inverse == 0) {
        die "Cannot find an inverse relationship for @{[$item->source_name]}\->@{[$r->name]}\n";
      }
      elsif (@inverse > 1) {
        die "Too many inverse relationships for @{[$item->source_name]}\->@{[$r->name]} ($fk_name / $fkcol)\n" . np(@inverse);
      }

      # We cannot add this relationship to the $cond because that would result
      # in an infinite loop. So, restrict the $rs here.
      $rs = $rs->search(
        { join('.', $inverse[0]{rel}, $inverse[0]{col}) => undef },
        { join => $inverse[0]{rel} },
      );
    }

    my $col_info = $item->source->column_info($col);
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

    warn "Looking for @{[$item->source_name]}->@{[$r->name]}(".np($cond).")\n" if $ENV{SIMS_DEBUG};

    my $parent;
    unless ($meta->{create}) {
      $parent = $rs->search(undef, { rows => 1 })->single;

      # This occurs when a FK condition was specified, but the column is
      # nullable. We want to defer these because self-referential values need
      # to be set after creation.
      if (!$parent && $col_info->{is_nullable}) {
        $cond = DBIx::Class::Sims::Item->new(
          source => $self->{sources}{$fk_name},
          spec   => $cond,
        );
        $cond->set_allow_pk_to($item);

        $item->spec->{$col} = undef;
        $deferred_fks{$r->name} = $cond;
        next RELATIONSHIP;
      }
    }
    unless ($parent) {
      my $fk_item = DBIx::Class::Sims::Item->new(
        source => $self->{sources}{$fk_name},
        spec   => MyCloner::clone($cond),
      );
      $fk_item->set_allow_pk_to($item);

      $parent = $self->create_item($fk_item);
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
      next if $self->{sources}{$src}->column_in_fk($col);

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

sub find_by_unique_constraints {
  my $self = shift;
  my ($item) = @_;

  my @uniques = map {
    [ $item->source->unique_constraint_columns($_) ]
  } $item->source->unique_constraint_names();

  my $rs = $self->schema->resultset($item->source_name);
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
          $item->source, $colname, $$value,
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
    push @{$self->{duplicates}{$item->source_name}}, {
      criteria => $searched,
      found    => { $row->get_columns },
    };
    $item->row($row);
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
  my ($item) = @_;

  while (my ($attr, $value) = each %{$item->spec}) {
    # Decode a backreference
    if (ref($value) eq 'SCALAR') {
      $item->spec->{$attr} = $self->convert_backreference(
        $item->source, $attr, $$value,
      );
    }
  }
}

sub fix_child_dependencies {
  my $self = shift;
  my ($item, $child_deps) = @_;

  # 1. If we have something, then:
  #   a. If it's not an array, then make it an array
  # 2. If we don't have something,
  #   a. Make an array with an empty item
  #   XXX This is more than one item would be supported
  # In all cases, make sure to add { $fkcol => $row->get_column($col) } to the
  # child's $item
  foreach my $r ( $item->source->child_relationships ) {
    next unless $child_deps->{$r->name} // $self->{reqs}{$item->source_name}{$r->name};

    my $col = $r->self_fk_col;
    my $fkcol = $r->foreign_fk_col;

    my $fk_name = $r->short_fk_source;

    my @children;
    if ($child_deps->{$r->name}) {
      my $n = DBIx::Class::Sims::Util->normalize_aoh($child_deps->{$r->name});
      unless ($n) {
        die "Don't know what to do with @{[$item->source_name]}\->@{[$r->name]}\n\t".np($item->row);
      }
      @children = @{$n};
    }
    else {
      @children = ( ({}) x $self->{reqs}{$item->source_name}{$r->name} );
    }

    # Need to ensure that $child_deps >= $self->{reqs}

    foreach my $child (@children) {
      # FIXME $child is a hashref, not a ::Item. add_child() needs to be able to
      # handle ::Item's, which requires ::Item's to be Comparable
      ($child->{__META__} //= {})->{allow_pk_set_value} = 1;

      $child->{$fkcol} = $item->row->get_column($col);
      $self->add_child($fk_name, $fkcol, $child, $item->source_name);
    }
  }
}

sub fix_deferred_fks {
  my $self = shift;
  my ($item, $deferred_fks) = @_;

  while (my ($rel_name, $cond) = each %$deferred_fks) {
    my $r = $item->source->relationship_by_name($rel_name);

    my $fk_name = $r->short_fk_source;

    my $cond = $deferred_fks->{$rel_name};

    my $rs = $self->schema->resultset($fk_name);
    $rs = $self->create_search($rs, $fk_name, $cond);

    my $parent = $rs->search(undef, { rows => 1 })->first;
    unless ($parent) {
      $parent = $self->create_item($cond);
    }

    my $col = $r->self_fk_col;
    my $fkcol = $r->foreign_fk_col;
    $item->row->$col($parent->get_column($fkcol));
  }
  $item->row->update if $item->row->get_dirty_columns;
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
  my ($item) = @_;

  my %is = (
    in_pk => sub {
      my $n = shift;
      grep {
        $_ eq $n
      } $item->source->primary_columns;
    },
    in_uk => sub {
      my $n = shift;
      grep {
        $_ eq $n
      } map {
        $item->source->unique_constraint_columns($_)
      } $item->source->unique_constraint_names;
    },
  );
  foreach my $type (keys %types) {
    $is{$type} = sub {
      my $t = shift;
      return exists $types{$type}{$t};
    };
  }

  foreach my $col_name ( $item->source->columns ) {
    my $sim_spec;
    if ( exists $item->spec->{$col_name} ) {
      if (
           $is{in_pk}->($col_name)
        && !$item->allow_pk_set_value
        && !$item->source->column_info($col_name)->{is_nullable}
        && $item->source->column_info($col_name)->{is_auto_increment}
      ) {
        my $msg = sprintf(
          "Primary-key autoincrement non-null columns should not be hardcoded in tests (%s.%s = %s)",
          $item->source_name, $col_name, $item->spec->{$col_name},
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
        !$item->source->column_info($col_name)->{_inflate_info}
      ) {
        $sim_spec = delete $item->spec->{$col_name};
      }
      # Pass the value along to DBIC - we don't know how to deal with it.
      else {
        next;
      }
    }

    my $info = $item->source->column_info($col_name);

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
      !$item->source->column_in_fk($col_name)
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
        die "ERROR: @{[$item->source_name]}\.$col_name is not nullable, but I don't know how to handle $info->{data_type}\n";
      }
    }
  }

  # Oracle does not allow the "INSERT INTO x DEFAULT VALUES" syntax that DBIC
  # wants to use. Therefore, find a PK column and set it to NULL. If there
  # isn't one, complain loudly.
  if ($self->is_oracle && keys(%{$item->spec}) == 0) {
    my @pk_columns = grep {
      $is{in_pk}->($_)
    } $item->source->columns;

    die "Must specify something about some column or have a PK in Oracle"
      unless @pk_columns;

    # This will work even if there are multiple columns in the PK.
    $item->spec->{$pk_columns[0]} = undef;
  }
}

sub create_item {
  my $self = shift;
  my ($item) = @_;

  # If, in the current stack of in-flight items, we've attempted to make this
  # exact item, die because we've obviously entered an infinite loop.
  if ($self->has_item($item)) {
    die "ERROR: @{[$item->source_name]} (".np($item->spec).") was seen more than once\n";
  }
  $self->add_item($item);

  my $before_fix = np($item->spec);
  $self->fix_columns($item);
  my $after_fix = np($item->spec);

  # Don't keep going if we already satisfy all UKs
  $self->find_by_unique_constraints($item);
  if ($item->row && $ENV{SIMS_DEBUG}) {
    warn "Found duplicate in @{[$item->source_name]}:\n"
      . "\tbefore fix_columns (".np($before_fix).")\n"
      . "\tafter fix_columns (".np($after_fix).")\n";
  }

  $self->{hooks}{preprocess}->($item->source_name, $item->source->source, $item->spec);

  my ($child_deps) = $self->find_child_dependencies($item);
  unless ($item->row) {
    my ($deferred_fks) = $self->fix_fk_dependencies($item);
    $self->fix_values($item);

    warn "Ensuring @{[$item->source_name]} (".np($item->spec).")\n" if $ENV{SIMS_DEBUG};
    $self->find_by_unique_constraints($item);
    unless ($item->row) {
      warn "Creating @{[$item->source_name]} (".np($item->spec).")\n" if $ENV{SIMS_DEBUG};
      my $row = eval {
        my $to_create = MyCloner::clone($item->spec);
        delete $to_create->{__META__};
        $self->schema->resultset($item->source_name)->create($to_create);
      }; if ($@) {
        my $e = $@;
        warn "ERROR Creating @{[$item->source_name]} (".np($item->spec).")\n";
        die $e;
      }
      $item->row($row);
      # This tracks everything that was created, not just what was requested.
      $self->{created}{$item->source_name}++;
    }

    $self->fix_deferred_fks($item, $deferred_fks);
  }

  $self->fix_child_dependencies($item, $child_deps);

  $self->{hooks}{postprocess}->($item->source_name, $item->source->source, $item->row);

  $self->remove_item($item);

  return $item->row;
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

        while ( my $proto = shift @{$self->{spec}{$name}} ) {
          my $item = DBIx::Class::Sims::Item->new(
            source => $self->{sources}{$name},
            spec   => $proto,
          );

          if ($self->{allow_pk_set_value}) {
            $item->set_allow_pk_to(1);
          }

          my $row = do {
            no strict 'refs';

            # DateTime objects print too big in SIMS_DEBUG mode, so provide a
            # good way for DDP to print them nicely.
            local *{'DateTime::_data_printer'} = sub { shift->iso8601 }
              unless DateTime->can('_data_printer');

            $self->create_item($item);
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
