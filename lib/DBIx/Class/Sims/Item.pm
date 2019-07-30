# This class exists to represent a row requested (and subsequently created) by
# the Sims. It will have a link back to a Sims::Source which will have the link
# back to the $schema object.

package DBIx::Class::Sims::Item;

use 5.010_001;

use strictures 2;

use DDP;

use List::PowerSet qw(powerset);
use Scalar::Util qw( blessed );

use DBIx::Class::Sims::Util qw( normalize_aoh reftype compare_values );

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->{original_spec} = MyCloner::clone($self->spec);

  # Lots of code assumes __META__ exists.
  # TODO: Should we check for _META__ or __META_ or __MTA__ etc?
  $self->{meta} = $self->spec->{__META__} // {};

  $self->{create} = {};

  $self->{still_to_use} = { map { $_ => 1 } keys %{$self->spec} };
  delete $self->{still_to_use}{__META__};

  # Should we quarantine_children() immediately?

  return;
}

sub runner { $_[0]{runner} }
sub source { $_[0]{source} }
sub spec   { $_[0]{spec}   }
sub meta   { $_[0]{meta} }

sub source_name { shift->source->name }

sub allow_pk_set_value { shift->meta->{allow_pk_set_value} }
sub set_allow_pk_to {
  my $self = shift;
  my ($proto) = @_;

  $self->meta->{allow_pk_set_value} = blessed($proto)
    ? $proto->meta->{allow_pk_set_value}
    : $proto;

  return;
}

sub row {
  my $self = shift;
  $self->{row} = shift if @_;
  return $self->{row};
}

################################################################################
#
# These are the helper methods
#
################################################################################

sub build_searcher_for_constraints {
  my $self = shift;
  my (@constraints) = @_;

  my $to_find = {};
  my $matched_all_columns = 1;
  foreach my $c ( map { @$_ } @constraints ) {
    unless (exists $self->spec->{$c->name}) {
      $matched_all_columns = 0;
      last;
    }
    $to_find->{$c->name} = $self->spec->{$c->name};
  }

  return $to_find if keys(%$to_find) && $matched_all_columns;
  return;
}

sub find_unique_match {
  my $self = shift;

  my @uniques = $self->source->uniques;

  my $rs = $self->source->resultset;

  if ( my $to_find = $self->build_searcher_for_constraints(@uniques) ) {
    my $row = $rs->search($to_find, { rows => 1 })->first;
    if ($row) {
      push @{$self->runner->{duplicates}{$self->source_name}}, {
        criteria => $to_find,
        found    => { $row->get_columns },
      };
      $self->row($row);
      return;
    }
  }

  # Search through all the possible iterations of unique keys.
  #  * Don't populate $self->{create}
  #  * If found with all keys, great.
  #  * Otherwise, keep track of what we find for each combination (if at all)
  #    * If we have multiple finds, die.
  # TODO: Use List::Powerset->powerset_lazy() instead of powerset()
  my @rows_found;
  foreach my $bundle (@{powerset(@uniques)}) {
    # Skip the all (already handled) and the empty (unneeded).
    next if @$bundle == 0 || @$bundle == @uniques;

    my $finder = $self->build_searcher_for_constraints(@$bundle)
      or next;

    my $row = $rs->search($finder, { rows => 1 })->first;
    if ($row) {
      push @rows_found, [ $finder, $row ];
    }
  }

  if (@rows_found > 1) {
    die "Rows found by multiple unique constraints";
  }

  if (@rows_found == 1) {
    my ($bundle, $row) = @{$rows_found[0]};
    push @{$self->runner->{duplicates}{$self->source_name}}, {
      criteria => $bundle,
      found    => { $row->get_columns },
    };
    $self->row($row);
    return;
  }

  return;
}

################################################################################
#
# These are the expected interface methods
#
################################################################################

sub create {
  my $self = shift;

  $self->find_unique_match;
  if ($self->row) {
    my @failed;
    foreach my $c ( $self->source->columns ) {
      my $col_name = $c->name;

      next unless exists $self->{spec}{$col_name};

      my $row_value = $self->row->get_column($col_name);
      my $spec_value = $self->{spec}{$col_name};
      unless (compare_values($row_value, $spec_value)) {
        push @failed, "\t$col_name: row(@{[$row_value//'[undef]']}) spec(@{[$spec_value//'[undef]']})\n";
      }
    }
    if (@failed) {
      die "ERROR Retrieving unique @{[$self->source_name]} (".np($self->spec).")\n" . join('', sort @failed);
    }
  }

  $self->runner->{hooks}{preprocess}->(
    $self->source_name, $self->source->source, $self->spec,
  );

  $self->quarantine_children;
  unless ($self->row) {
    $self->populate_parents;
    $self->populate_columns;

    # Things were passed in, but don't exist in the table.
    if (!$self->runner->{ignore_unknown_columns} && %{$self->{still_to_use}}) {
      my $msg = "The following names are in the spec, but not the table @{[$self->source_name]}\n";
      $msg .= join ',', sort keys %{$self->{still_to_use}};
      $msg .= "\n";
      die $msg;
    }

    $self->oracle_ensure_populated_pk;

    #warn np($self->{create});
    #warn "Creating @{[$self->source_name]} (".np($self->spec).")\n" if $ENV{SIMS_DEBUG};
    my $row = eval {
      #warn 'Creating (' . np($self->{create}) . ")\n";
      $self->source->resultset->create($self->{create});
    }; if ($@) {
      my $e = $@;
      warn "ERROR Creating @{[$self->source_name]} (".np($self->spec).")\n";
      die $e;
    }
    $self->row($row);

    # This tracks everything that was created, not just what was requested.
    $self->runner->{created}{$self->source_name}++;
  }
  $self->build_children;

  $self->runner->{hooks}{postprocess}->(
    $self->source_name, $self->source->source, $self->row,
  );

  return $self->row;
}

sub populate_columns {
  my $self = shift;
  my ($col_spec) = @_;

  foreach my $c ( $self->source->columns($col_spec) ) {
    my $col_name = $c->name;

    my $spec;
    if ( exists $self->spec->{$col_name} ) {
      if (
        $c->is_in_pk && $c->is_auto_increment &&
        !$self->allow_pk_set_value
      ) {
        warn sprintf(
          "Primary-key autoincrement columns should not be hardcoded in tests (%s.%s = %s)",
          $self->source_name, $col_name, $self->spec->{$col_name},
        );
      }

      # This is the original way of specifying an override with a HASHREFREF.
      # Reflection has realized it was an unnecessary distinction to a parent
      # specification. Either it's a relationship hashref or a simspec hashref.
      # We can never have both. It will be deprecated.
      if (
        reftype($self->spec->{$col_name}) eq 'REF' &&
        reftype(${$self->spec->{$col_name}}) eq 'HASH'
      ) {
        warn "DEPRECATED: Use a regular HASHREF for overriding simspec. HASHREFREF will be removed in a future release.";
        $spec = ${ $self->spec->{$col_name} };
      }
      elsif (
        reftype($self->spec->{$col_name}) eq 'HASH' &&
        # Assume a blessed hash is a DBIC object
        !blessed($self->spec->{$col_name}) &&
        # Do not assume we understand something to be inflated/deflated
        !$c->is_inflated
      ) {
        $spec = $self->spec->{$col_name};
      }
      else {
        $self->{create}{$col_name} = $self->spec->{$col_name};
      }
    }

    $spec //= $c->sim_spec;
    if ( ! exists $self->{create}{$col_name} ) {
      if ($spec) {
        if (ref($spec // '') eq 'HASH') {
          if ( exists $spec->{null_chance} && $c->is_nullable ) {
            # Add check for not a number
            if ( rand() < $spec->{null_chance} ) {
              $self->{create}{$col_name} = undef;
              next;
            }
          }

          if ( ref($spec->{func} // '') eq 'CODE' ) {
            $self->{create}{$col_name} = $spec->{func}->($c->info);
          }
          elsif ( exists $spec->{value} ) {
            if (ref($spec->{value} // '') eq 'ARRAY') {
              my @v = @{$spec->{value}};
              $self->{create}{$col_name} = $v[rand @v];
            }
            else {
              $self->{create}{$col_name} = $spec->{value};
            }
          }
          elsif ( $spec->{type} ) {
            my $meth = $self->runner->parent->sim_type($spec->{type});
            if ( $meth ) {
              $self->{create}{$col_name} = $meth->($c->info, $spec, $c);
            }
            else {
              warn "Type '$spec->{type}' is not loaded";
            }
          }
          else {
            $self->{create}{$col_name} = $c->generate_value(die_on_unknown => 0);
          }
        }
      }
      elsif (
        !$c->is_nullable &&
        !$c->is_in_pk
      ) {
        $self->{create}{$col_name} = $c->generate_value(die_on_unknown => 1);
      }
    }
  } continue {
    delete $self->{still_to_use}{$c->name};
  }

  return;
}

sub create_search {
  my $self = shift;
  my ($source, $proto) = @_;
  $proto = MyCloner::clone($proto);

  delete $proto->{__META__};

  # ASSUMPTIONS:
  #   * All k/v pairs in $cond are scalars
  #   * All keys in $cond exist as columns in $source
  # TODO: Write tests to force validation of these assumptions

  my $cond = {};
  foreach my $colname ( map { $_->name } $source->columns ) {
    next unless exists $proto->{$colname};
    $cond->{$colname} = delete $proto->{$colname};
  }

  # Handle the case of relationships

  if ( keys %$proto ) {
    my @cols = join "', '", sort keys %$proto;
    die $source->name . " has no column or relationship '@cols'";
  }

  #warn $source->name . ':' . np($cond), $/;

  return $cond, {};
}

sub populate_parents {
  my $self = shift;

  RELATIONSHIP:
  foreach my $r ( $self->source->parent_relationships ) {
    my $col = $r->self_fk_col;

    if (!$self->runner->{allow_relationship_column_names}) {
      if ($col ne $r->name && exists $self->spec->{$col}) {
        die "Cannot use column $col - use relationship @{[$r->name]}";
      }
    }

    my $cond;
    my $fkcol = $r->foreign_fk_col;
    my $proto = delete($self->spec->{$r->name}) // delete($self->spec->{$col});
    # TODO: Write a test if both the rel and the FK col are specified
    delete $self->{still_to_use}{$r->name};
    delete $self->{still_to_use}{$col};

    if ($proto) {
      # Assume anything blessed is blessed into DBIC.
      # TODO: Write tests to force us to ensure things about blessed things.
      # This should do "blessed($x) && $x->can($fkcol)" and assume this is okay
      if (blessed($proto)) {
        #$cond = { $fkcol => $proto->$fkcol };
        $self->spec->{$col} = $proto->get_column($fkcol);
        next RELATIONSHIP
      }
      # Assume any hashref is a Sims specification
      elsif (ref($proto) eq 'HASH') {
        $cond = $proto
      }
      # Assume any unblessed scalar is a column value.
      elsif (!ref($proto)) {
        $cond = { $fkcol => $proto };
      }
=pod
      # Use a referenced row
      elsif (ref($proto) eq 'SCALAR') {
        $cond = {
          $fkcol => $self->runner->convert_backreference(
            $self->runner->backref_name($self->runner, $r->name), $$proto, $fkcol,
          ),
        };
      }
=cut
      else {
        die "Unsure what to do about @{[$r->full_name]}():" . np($proto);
      }
    }

    my $fk_source = $r->target;
    my $rs = $fk_source->resultset;

    # If the child's column is within a UK, add a check to the $rs that ensures
    # we cannot pick a parent that's already being used.
    my @constraints = $self->source->unique_constraints_containing($col);
    if (@constraints) {
      # First, find the inverse relationship. If it doesn't exist or if there
      # is more than one, then die.
      my @inverse = $self->source->find_inverse_relationships(
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

    if ( $cond ) {
      $rs = $rs->search( $self->create_search($fk_source, $cond) );
    }
    else {
      $cond = {};
    }

    my $meta = delete $cond->{__META__} // {};

    my $parent;
    unless ($meta->{create}) {
      $parent = $rs->search(undef, { rows => 1 })->single;
    }
    unless ($parent) {
      my $fk_item = DBIx::Class::Sims::Item->new(
        runner => $self->runner,
        source => $fk_source,
        spec   => MyCloner::clone($cond),
      );
      $fk_item->set_allow_pk_to($self);

      $fk_item->create;
      $parent = $fk_item->row;
    }

    $self->spec->{$col} = $parent->get_column($fkcol);
  }

}

#sub populate_deferred_parents {
#  my $self = shift;
#}

sub quarantine_children {
  my $self = shift;

  $self->{children} = {};
  foreach my $r ( $self->source->child_relationships ) {
    if ($self->spec->{$r->name}) {
      $self->{children}{$r->name} = $self->spec->{$r->name};
      delete $self->{still_to_use}{$r->name};
    }
  }

  return;
}

sub build_children {
  my $self = shift;

  # 1. If we have something, then:
  #   a. If it's not an array, then make it an array
  # 2. If we don't have something,
  #   a. Make an array with an empty item
  #   XXX This is more than one item would be supported
  # In all cases, make sure to add { $fkcol => $row->get_column($col) } to the
  # child's $item
  foreach my $r ( $self->source->child_relationships ) {
    next unless $self->{children}{$r->name} // $r->constraints;

    my @children;
    if ($self->{children}{$r->name}) {
      my $n = normalize_aoh($self->{children}{$r->name})
        or die "Don't know what to do with @{[$r->full_name]}\n\t".np($self->{original_spec});

      @children = @{$n};
    }
    else {
      # ASSUMPTION: The constraint provided in the relationship is a number.
      @children = ( ({}) x $r->constraints );
    }

    # TODO: Add a test for $self->{children} >= $r->constraints. For example,
    # $r->constraints == 2, but only one child was added by hand.

    my $col = $r->self_fk_col;
    my $fkcol = $r->foreign_fk_col;
    my $fk_source = $r->target;
    foreach my $child (@children) {
      # FIXME $child is a hashref, not a ::Item. add_child() needs to be able to
      # handle ::Item's, which requires ::Item's to be Comparable. It also means
      # the ::Runner's spec has been converted to ::Item before iteration.
      ($child->{__META__} //= {})->{allow_pk_set_value} = 1;

      $child->{$fkcol} = $self->row->get_column($col);
      $self->runner->add_child($fk_source, $fkcol, $child, $self->source_name);
    }
  }
}

sub oracle_ensure_populated_pk {
  my $self = shift;

  # Oracle does not allow the "INSERT INTO x DEFAULT VALUES" syntax that DBIC
  # wants to use. Therefore, find a PK column and set it to NULL. If there
  # isn't one, complain loudly.
  if ($self->runner->is_oracle && keys(%{$self->{create}}) == 0) {
    my @pk_columns = grep {
      $_->is_in_pk
    } $self->source->columns;

    die "Must specify something about some column or have a PK in Oracle"
      unless @pk_columns;

    # This will work even if there are multiple columns in the PK.
    $self->spec->{$pk_columns[0]->name} = undef;
  }
}

1;
__END__
