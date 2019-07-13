package DBIx::Class::Sims::Runner;

use 5.010_001;

use strictures 2;

use DDP;

use Data::Compare qw( Compare );
use Hash::Merge qw( merge );
use Scalar::Util qw( blessed );
use String::Random qw( random_regex );

use DBIx::Class::Sims::Item;
use DBIx::Class::Sims::Source;
use DBIx::Class::Sims::Util qw( reftype );

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
      constraints => $self->{constraints}{$name},
    );
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

{
  my %added_by;
  sub add_child {
    my $self = shift;
    my ($source, $fkcol, $child, $adder) = @_;
    # If $child has the same keys (other than parent columns) as another row
    # added by a different parent table, then set the foreign key for this
    # parent in the existing row.
    foreach my $compare (@{$self->{spec}{$source->name}}) {
      next if exists $added_by{$adder} && exists $added_by{$adder}{$compare};
      if ($self->are_columns_equal($source, $child, $compare)) {
        $compare->{$fkcol} = $child->{$fkcol};
        return;
      }
    }

    push @{$self->{spec}{$source->name}}, $child;
    $added_by{$adder} //= {};
    $added_by{$adder}{$child} = !!1;
    $self->add_pending($source->name);
  }
}

{
  # The "pending" structure exists because of t/parent_child_parent.t - q.v. the
  # comments on the toposort->add_dependencies element.
  my %pending;
  sub add_pending { $pending{$_[1]} = undef; }
  sub has_pending { keys %pending != 0; }
  sub delete_pending { delete $pending{$_[1]}; }
  sub clear_pending { %pending = (); }
}

# FIXME: This method is a mess. It needs to be completely rethought and,
# possibly, broken out into different versions.
sub create_search {
  my $self = shift;
  my ($rs, $source, $cond) = @_;

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

  my %cols = map { $_->name => 1 } $source->columns;
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
  #foreach my $rel_name (keys %{$source->relationships})
  # So, we use this one instead. This breaks encapsulation.
  foreach my $rel_name ($source->source->relationships) {
    next unless exists $cond->{$rel_name};
    next unless reftype($cond->{$rel_name}) eq 'HASH';

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
    my $col = $r->self_fk_col;

    if (!$self->{allow_relationship_column_names}) {
      if ($col ne $r->name && exists $item->spec->{$col}) {
        die "Cannot use column $col - use relationship @{[$r->name]}";
      }
    }

    my $cond;
    my $fkcol = $r->foreign_fk_col;
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
            $self->backref_name($item, $r->name), $$proto, $fkcol,
          ),
        };
      }
      else {
        die "Unsure what to do about @{[$r->full_name]}():" . np($proto);
      }
    }

    my $fk_source = $r->target;
    my $rs = $fk_source->resultset;

    # If the child's column is within a UK, add a check to the $rs that ensures
    # we cannot pick a parent that's already being used.
    my @constraints = $item->source->unique_constraints_containing($col);
    if (@constraints) {
      # First, find the inverse relationship. If it doesn't exist or if there
      # is more than one, then die.
      my @inverse = $item->source->find_inverse_relationships(
        $fk_source, $fkcol,
      );
      if (@inverse == 0) {
        die "Cannot find an inverse relationship for @{[$r->full_name]}\n";
      }
      elsif (@inverse > 1) {
        die "Too many inverse relationships for @{[$r->full_name]} (@{[$fk_source->name]} / $fkcol)\n" . np(@inverse);
      }

      # We cannot add this relationship to the $cond because that would result
      # in an infinite loop. So, restrict the $rs here.
      $rs = $rs->search(
        { join('.', $inverse[0]{rel}, $inverse[0]{col}) => undef },
        { join => $inverse[0]{rel} },
      );
    }

    my $c = $item->source->column($col);
    if ( $cond ) {
      $rs = $self->create_search($rs, $fk_source, $cond);
    }
    elsif ( $c->is_nullable ) {
      next RELATIONSHIP;
    }
    else {
      $cond = {};
    }

    my $meta = delete $cond->{__META__} // {};

    warn "Looking for @{[$r->full_name]}(".np($cond).")\n" if $ENV{SIMS_DEBUG};

    my $parent;
    unless ($meta->{create}) {
      $parent = $rs->search(undef, { rows => 1 })->single;

      # This occurs when a FK condition was specified, but the column is
      # nullable. We want to defer these because self-referential values need
      # to be set after creation.
      if (!$parent && $c->is_nullable) {
        $cond = DBIx::Class::Sims::Item->new(
          runner => $self,
          source => $fk_source,
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
        runner => $self,
        source => $fk_source,
        spec   => MyCloner::clone($cond),
      );
      $fk_item->set_allow_pk_to($item);

      $parent = $self->create_item($fk_item);
    }
    $item->spec->{$col} = $parent->get_column($fkcol);
  }

  return \%deferred_fks;
}

sub are_columns_equal {
  my $self = shift;
  my ($source, $row, $compare) = @_;
  foreach my $c ($source->columns) {
    next if $c->is_in_fk;
    my $col = $c->name;

    next if !exists($row->{$col}) && !exists($compare->{$col});
    return unless exists($row->{$col}) && exists($compare->{$col});
    return if $compare->{$col} ne $row->{$col};
  }
  return 1;
}

sub find_by_unique_constraints {
  my $self = shift;
  my ($item) = @_;

  my $rs = $item->source->resultset;
  my $searched = {};
  foreach my $unique ($item->source->unique_columns) {
    # If there are specified values for all the columns in a specific unqiue constraint ...
    next if grep { ! exists $item->spec->{$_} } @$unique;

    # ... then add that to the list of potential values to search.
    my %criteria;
    foreach my $colname (@{$unique}) {
      my $value = $item->spec->{$colname};
      if (ref($value) eq 'SCALAR') {
        $value = $self->convert_backreference(
          $self->backref_name($item, $colname), $$value,
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

sub backref_name {
  my $self = shift;
  my ($item, $colname) = @_;
  return $item->source->name . '->' . $colname;
}

sub convert_backreference {
  my $self = shift;
  my ($backref_name, $proto, $default_method) = @_;

  my ($table, $idx, $methods) = ($proto =~ /(.+)\[(\d+)\](?:\.(.+))?$/);
  unless ($table && defined $idx) {
    die "Unsure what to do about $backref_name => $proto\n";
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
    die "No method to call at $backref_name => $proto\n";
  }
}

sub fix_values {
  my $self = shift;
  my ($item) = @_;

  while (my ($attr, $value) = each %{$item->spec}) {
    # Decode a backreference
    if (ref($value) eq 'SCALAR') {
      $item->spec->{$attr} = $self->convert_backreference(
        $self->backref_name($item, $attr), $$value,
      );
    }
  }
}

sub fix_deferred_fks {
  my $self = shift;
  my ($item, $deferred_fks) = @_;

  while (my ($rel_name, $cond) = each %$deferred_fks) {
    my $r = $item->source->relationship($rel_name);

    my $cond = $deferred_fks->{$rel_name};

    my $fk_source = $r->target;
    my $rs = $fk_source->resultset;
    $rs = $self->create_search($rs, $fk_source, $cond);

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

sub fix_columns {
  my $self = shift;
  my ($item) = @_;

  foreach my $c ( $item->source->columns ) {
    my $col_name = $c->name;

    my $sim_spec;
    if ( exists $item->spec->{$col_name} ) {
      if (
        $c->is_in_pk && $c->is_auto_increment &&
        !$item->allow_pk_set_value
      ) {
        warn sprintf(
          "Primary-key autoincrement columns should not be hardcoded in tests (%s.%s = %s)",
          $item->source_name, $col_name, $item->spec->{$col_name},
        );
      }

      # This is the original way of specifying an override with a HASHREFREF.
      # Reflection has realized it was an unnecessary distinction to a parent
      # specification. Either it's a relationship hashref or a simspec hashref.
      # We can never have both. It will be deprecated.
      if (
        reftype($item->spec->{$col_name}) eq 'REF' &&
        reftype(${$item->spec->{$col_name}}) eq 'HASH'
      ) {
        warn "DEPRECATED: Use a regular HASHREF for overriding simspec. HASHREFREF will be removed in a future release.";
        $sim_spec = ${ delete $item->spec->{$col_name} };
      }
      elsif (
        reftype($item->spec->{$col_name}) eq 'HASH' &&
        # Assume a blessed hash is a DBIC object
        !blessed($item->spec->{$col_name}) &&
        # Do not assume we understand something to be inflated/deflated
        !$c->is_inflated
      ) {
        $sim_spec = delete $item->spec->{$col_name};
      }
      # Pass the value along to DBIC - we don't know how to deal with it.
      else {
        next;
      }
    }

    $sim_spec //= $c->sim_spec;
    if ( ref($sim_spec // '') eq 'HASH' ) {
      if ( exists $sim_spec->{null_chance} && $c->is_nullable ) {
        # Add check for not a number
        if ( rand() < $sim_spec->{null_chance} ) {
          $item->spec->{$col_name} = undef;
          next;
        }
      }

      if ( ref($sim_spec->{func} // '') eq 'CODE' ) {
        $item->spec->{$col_name} = $sim_spec->{func}->($c->info);
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
          $item->spec->{$col_name} = $meth->($c->info, $sim_spec, $self);
        }
        else {
          warn "Type '$sim_spec->{type}' is not loaded";
        }
      }
      else {
        $item->spec->{$col_name} = $c->generate_value(die_on_unknown => 0);
      }
    }
    # If it's not nullable, doesn't have a default value and isn't part of a
    # primary key (could be auto-increment) or part of a unique key or part of a
    # foreign key, then generate a value for it.
    elsif (
      !$c->is_nullable &&
      !$c->has_default_value &&
      !$c->is_in_pk &&
      !$c->is_in_uk &&
      !$c->is_in_fk
    ) {
      $item->spec->{$col_name} = $c->generate_value(die_on_unknown => 1);
    }
  }

  # Oracle does not allow the "INSERT INTO x DEFAULT VALUES" syntax that DBIC
  # wants to use. Therefore, find a PK column and set it to NULL. If there
  # isn't one, complain loudly.
  if ($self->is_oracle && keys(%{$item->spec}) == 0) {
    my @pk_columns = grep {
      $_->is_in_pk
    } $item->source->columns;

    die "Must specify something about some column or have a PK in Oracle"
      unless @pk_columns;

    # This will work even if there are multiple columns in the PK.
    $item->spec->{$pk_columns[0]->name} = undef;
  }
}

sub Xcreate_item {
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

  $item->quarantine_children;
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
        $item->source->resultset->create($to_create);
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
  $item->build_children;

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
            runner => $self,
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

            $item->create;
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
