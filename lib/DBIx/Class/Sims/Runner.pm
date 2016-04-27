package DBIx::Class::Sims::Runner;

use 5.010_002;

use strictures 2;

use DDP;

use Scalar::Util qw( blessed reftype );
use String::Random qw( random_regex );

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

  return;
}

sub schema { shift->{schema} }

sub fix_fk_dependencies {
  my $self = shift;
  my ($name, $item) = @_;

  # 1. If we have something, then:
  #   a. If it's a scalar, then, COND = { $fk => scalar }
  #   b. Look up the row by COND
  #   c. If the row is not there, then $create_item->($fksrc, COND)
  # 2. If we don't have something and the column is non-nullable, then:
  #   a. If rows exists, pick a random one.
  #   b. If rows don't exist, $create_item->($fksrc, {})
  my %child_deps;
  my $source = $self->schema->source($name);
  foreach my $rel_name ( $source->relationships ) {
    my $rel_info = $source->relationship_info($rel_name);
    unless ( $is_fk->($rel_info) ) {
      if ($item->{$rel_name}) {
        $child_deps{$rel_name} = delete $item->{$rel_name};
      }
      next;
    }

    next unless $self->{reqs}{$name}{$rel_name};

    my $col = $self_fk_col->($rel_info);
    my $fkcol = $foreign_fk_col->($rel_info);

    my $fk_src = $short_source->($rel_info);
    my $rs = $self->schema->resultset($fk_src);

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
      else {
        die "Unsure what to do about $name->$rel_name():" . p($proto);
      }
    }

    my $col_info = $source->column_info($col);
    if ( $cond ) {
      my %fkcols = map { $_ => 1 } $self->schema->source($fk_src)->columns;
      my $search = {
        (map {
          $_ => $cond->{$_}
        } grep {
          exists $fkcols{$_}
        } keys %$cond)
      };
      $rs = $rs->search($search);
    }
    elsif ( $col_info->{is_nullable} ) {
      next;
    }
    else {
      $cond = {};
    }

    my $meta = delete $cond->{__META__} // {};

    #warn "Looking for $name->$rel_name(".p($cond).")\n";

    my $parent;
    unless ($meta->{create}) {
      $parent = $rs->search(undef, { rows => 1 })->first;
    }
    unless ($parent) {
      $parent = $self->create_item($fk_src, $cond);
    }
    $item->{$col} = $parent->get_column($fkcol);
  }

  return \%child_deps;
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
sub find_by_unique_constraints {
  my $self = shift;
  my ($name, $item) = @_;

  my $source = $self->schema->source($name);
  my @uniques = map {
    [ $source->unique_constraint_columns($_) ]
  } $source->unique_constraint_names();

  my $rs = $self->schema->resultset($name);
  my $searched = 0;
  foreach my $unique (@uniques) {
    # If there are specified values for all the columns in a specific unqiue constraint ...
    next if grep { ! exists $item->{$_} } @$unique;

    # ... then add that to the list of potential values to search.
    $rs = $rs->search({
      ( map { $_ => $item->{$_} } @{$unique})
    });
    $searched = 1;
  }

  return unless $searched;
  return $rs->first;
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

    my $fk_src = $short_source->($rel_info);

    # Need to ensure that $child_deps >= $self->{reqs}

    my @children = @{$child_deps->{$rel_name} // []};
    @children = ( ({}) x $self->{reqs}{$name}{$rel_name} ) unless @children;
    foreach my $child (@children) {
      $child->{$fkcol} = $row->get_column($col);
      $self->add_child($fk_src, $fkcol, $child, $name);
    }
  }
}

sub fix_columns {
  my $self = shift;
  my ($name, $item) = @_;

  my $source = $self->schema->source($name);
  foreach my $col_name ( $source->columns ) {
    my $sim_spec;
    if ( exists $item->{$col_name} ) {
      if ((reftype($item->{$col_name}) // '') eq 'REF' &&
        reftype(${$item->{$col_name}}) eq 'HASH' ) {
        $sim_spec = ${ delete $item->{$col_name} };
      }
      # Pass the value along to DBIC - we don't know how to deal with it.
      else {
        next;
      }
    }

    my $info = $source->column_info($col_name);

    $sim_spec //= $info->{sim};
    if ( ref($sim_spec // '') eq 'HASH' ) {
      if ( exists $sim_spec->{null_chance} && !$info->{nullable} ) {
        # Add check for not a number
        if ( rand() < $sim_spec->{null_chance} ) {
          $item->{$col_name} = undef;
          next;
        }
      }

      if ( ref($sim_spec->{func} // '') eq 'CODE' ) {
        $item->{$col_name} = $sim_spec->{func}->($info);
      }
      elsif ( exists $sim_spec->{value} ) {
        $item->{$col_name} = $sim_spec->{value};
      }
      elsif ( $sim_spec->{type} ) {
        my $meth = $self->{parent}->sim_type($sim_spec->{type});
        if ( $meth ) {
          $item->{$col_name} = $meth->($info);
        }
        else {
          warn "Type '$sim_spec->{type}' is not loaded";
        }
      }
      else {
        if ( $info->{data_type} eq 'int' ) {
          my $min = $sim_spec->{min} // 0;
          my $max = $sim_spec->{max} // 100;
          $item->{$col_name} = int(rand($max-$min))+$min;
        }
        elsif ( $info->{data_type} eq 'varchar' ) {
          my $min = $sim_spec->{min} // 1;
          my $max = $sim_spec->{max} // $info->{data_length} // 255;
          $item->{$col_name} = random_regex(
            '\w' . "{$min,$max}"
          );
        }
      }
    }
  }
}

sub create_item {
  my $self = shift;

  my ($name, $item) = @_;

  #warn "Starting with $name (".p($item).")\n";
  $self->fix_columns($name, $item);

  my $source = $self->schema->source($name);
  $self->{hooks}{preprocess}->($name, $source, $item);

  my $child_deps = $self->fix_fk_dependencies($name, $item);

  #warn "Creating $name (".p($item).")\n";
  my $row = eval {
    $self->find_by_unique_constraints($name, $item)
      // $self->schema->resultset($name)->create($item);
  }; if ($@) {
    warn "ERROR Creating $name (".p($item).")\n";
    die $@;
  }

  $self->fix_child_dependencies($name, $row, $child_deps);

  $self->{hooks}{postprocess}->($name, $source, $row);

  return $row;
}

sub run {
  my $self = shift;

  return $self->schema->txn_do(sub {
    my %rows;
    while (1) {
      foreach my $name ( @{$self->{toposort}} ) {
        next unless $self->{spec}{$name};

        while ( my $item = shift @{$self->{spec}{$name}} ) {
          my $x = $self->create_item($name, $item);
          push @{$rows{$name} //= []}, $x if $self->{initial_spec}{$name}{$item};
        }

        $self->delete_pending($name);
      }

      last unless $self->has_pending();
      $self->clear_pending();
    }

    return \%rows;
  });
}

1;
__END__
