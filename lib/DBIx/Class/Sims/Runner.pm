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

sub parent { shift->{parent} }
sub schema { shift->{schema} }
sub driver { shift->schema->storage->dbh->{Driver}{Name} }
sub is_oracle { shift->driver eq 'Oracle' }
sub datetime_parser { shift->schema->storage->datetime_parser }

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

sub run {
  my $self = shift;

  return $self->schema->txn_do(sub {
    # DateTime objects print too big in SIMS_DEBUG mode, so provide a
    # good way for DDP to print them nicely.
    no strict 'refs';
    local *{'DateTime::_data_printer'} = sub { shift->iso8601 }
      unless DateTime->can('_data_printer');

    $self->{rows} = {};
    my %still_to_use = map { $_ => 1 } keys %{$self->{spec}};
    while (1) {
      foreach my $name ( @{$self->{toposort}} ) {
        next unless $self->{spec}{$name};
        delete $still_to_use{$name};

        while ( my $proto = shift @{$self->{spec}{$name}} ) {
          $proto->{__META__} //= {};
          $proto->{__META__}{create} = 1;

          my $item = DBIx::Class::Sims::Item->new(
            runner => $self,
            source => $self->{sources}{$name},
            spec   => $proto,
          );

          if ($self->{allow_pk_set_value}) {
            $item->set_allow_pk_to(1);
          }

          my $row = $item->create;

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
