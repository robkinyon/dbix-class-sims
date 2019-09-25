# This class exists to represent a row requested (and subsequently created) by
# the Sims. It will have a link back to a Sims::Source which will have the link
# back to the $schema object.

package DBIx::Class::Sims::Item;

use 5.010_001;

use strictures 2;

use DDP;

#use List::PowerSet qw(powerset);
use Scalar::Util qw( blessed );

use DBIx::Class::Sims::Util qw(
  normalize_aoh reftype compare_values
  powerset powerset_lazy
);

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

  $self->{created} = 0;
  $self->{create} = {};

  $self->{still_to_use} = { map { $_ => 1 } keys %{$self->spec} };
  delete $self->{still_to_use}{__META__};

  $self->{skip_relationship} = {};

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

sub has_value {
  my $self = shift;
  my ($col) = @_;
  return exists $self->{create}{$col} || exists $self->spec->{$col};
}
sub value {
  my $self = shift;
  my ($col) = @_;

  return unless $self->has_value($col);
  return exists $self->{create}{$col}
    ? $self->{create}{$col}
    : $self->spec->{$col};
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
    unless ($self->has_value($c->name)) {
      $matched_all_columns = 0;
      last;
    }

    # Undefined values cannot be searched over because undefined values appear
    # different to the UK, but appear the same in a query. Therefore, this
    # searcher cannot work.
    $to_find->{$c->name} = $self->value($c->name) // return;
  }

  return $to_find if keys(%$to_find) && $matched_all_columns;
  return;
}

sub unique_id {
  my $self = shift;
  my ($row) = @_;

  my @cols = $row->result_source->columns;
  my %data = $row->get_columns;
  my @vals = %data{@cols};
  return ref($row) . join(',',@cols) . join(',',map {$_//''} @vals);
}

sub find_unique_match {
  my $self = shift;

  my @uniques = $self->source->uniques;

  my $rs = $self->source->resultset;

  if ( my $to_find = $self->build_searcher_for_constraints(@uniques) ) {
    my $row = $rs->search($to_find, { rows => 1 })->first;
    if ($row) {
      push @{$self->runner->{duplicates}{$self->source_name}}, {
        criteria => [$to_find],
        found    => { $row->get_columns },
      };
      $self->row($row);

      $self->{trace}{find} = $self->{runner}{ids}{find}++;
      $self->{trace}{row} = { $row->get_columns };
      $self->{trace}{criteria} = [$to_find];
      $self->{trace}{unique} = 1;

      return;
    }
  }

  # Search through all the possible iterations of unique keys.
  #  * Don't populate $self->{create}
  #  * If found with all keys, great.
  #  * Otherwise, keep track of what we find for each combination (if at all)
  #    * If we have multiple finds, die.
  # TODO: Use List::Powerset->powerset_lazy() instead of powerset()
  my %rows_found;
  foreach my $bundle (@{powerset(@uniques)}) {
    # Skip the all (already handled) and the empty (unneeded).
    next if @$bundle == 0 || @$bundle == @uniques;

    my $finder = $self->build_searcher_for_constraints(@$bundle)
      or next;

    my $row = $rs->search($finder, { rows => 1 })->first;
    if ($row) {
      my $unique_id = $self->unique_id($row);
      $rows_found{$unique_id} //= {
        row => $row,
        finders => [],
      };
      push @{$rows_found{$unique_id}{finders}}, $finder;
    }
  }

  if (keys(%rows_found) > 1) {
    die "Rows found by multiple unique constraints";
  }

  if (keys(%rows_found) == 1) {
    my $x = (values %rows_found)[0];
    my ($finders, $row) = @{$x}{qw(finders row)};
    push @{$self->runner->{duplicates}{$self->source_name}}, {
      criteria => $finders,
      found    => { $row->get_columns },
    };
    $self->row($row);

    $self->{trace}{find} = $self->{runner}{ids}{find}++;
    $self->{trace}{row} = { $row->get_columns };
    $self->{trace}{criteria} = $finders;
    $self->{trace}{unique} = 1;

    return;
  }

  return;
}

sub find_any_match {
  my $self = shift;

  my $rs = $self->source->resultset;

  if ($self->meta->{restriction}) {
    my $c = $self->meta->{restriction};
    $rs = $rs->search( $c->{cond}, $c->{extra} );
  }

  my $cond = {};
  foreach my $colname ( map { $_->name } $self->source->columns ) {
    next unless $self->has_value($colname);
    $cond->{'me.' . $colname} = $self->value($colname);
  }

  my $row = $rs->search($cond, { rows => 1 })->single;
  $self->row($row) if $row;

  return $self->row;
}

sub resolve_direct_values {
  my $self = shift;

  my @unknowns;
  while ( my ($k,$v) = each %{$self->spec} ) {
    # Ignore __META__
    next if $k eq '__META__';

    # If $k is a relationship, handle that.
    if ( my $r = $self->source->relationship($k) ) {
      my $fkcol = $r->foreign_fk_col;
      if (blessed($v)) {
        $self->{create}{$r->self_fk_col} = $v->get_column($fkcol);
        $self->{skip_relationship}{$r->name} = 1;

        # Otherwise, the tracer will try and write out a blessed object.
        $self->{trace}{spec}{$r->self_fk_col} = $self->{create}{$r->self_fk_col};
      }
      elsif (ref($v) eq 'SCALAR') {
        $self->{create}{$r->self_fk_col} = $self->runner->convert_backreference(
          $self->runner->backref_name($self, $k),
          ${$v},
          $fkcol,
        );
      }
    }
    # If $k is a column,
    elsif ( my $c = $self->source->column($k) ) {
      # If $k is in a relationship, find the appropriate one via the class.
      if ( $c->is_in_fk ) {
        # Find the appropriate FK.
        if ( my $kls = blessed $v ) {
          my @rels = grep {
            $kls eq $_->foreign_class
          } $c->fks;

          if ( @rels != 1 ) {
            die "ERROR: @{[$self->source_name]} Cannot figure out what relationship belongs to $k (@{[np $v]})!\n@{[join ',', sort map{$_->name}@rels]}";
          }
          my $r = $rels[0];

          $self->{create}{$k} = $v->get_column($r->foreign_fk_col);
          $self->{skip_relationship}{$_->name} = 1 for $c->fks;

          # Otherwise, the tracer will try and write out a blessed object.
          $self->{trace}{spec}{$k} = $self->{create}{$k};
        }
        elsif (ref($v) eq 'SCALAR') {
          my ($kls_base) = ${$v} =~ /([^:]+)\[/;
          my @rels = grep {
            my ($k) = $_->foreign_class =~ /([^:]+)$/;
            ${$v} =~ /$k/
          } $c->fks;

          if ( @rels != 1 ) {
            die "ERROR: @{[$self->source_name]} Cannot figure out what relationship belongs to $k (@{[np $v]})!\n@{[join ',', sort map{$_->name}@rels]}";
          }
          my $r = $rels[0];

          $self->{create}{$k} = $self->runner->convert_backreference(
            $self->runner->backref_name($self, $r->name),
            ${$v},
            $r->foreign_fk_col,
          );
        }
      }
      # Else handle it via column
      else {
        if (reftype($v) eq 'SCALAR') {
          $self->{create}{$k} = $self->runner->convert_backreference(
            $self->runner->backref_name($self, $k),
            ${$v},
          );
        }
      }
    }
    # Otherwise, DIE DIE DIE
    else {
      push @unknowns, $k;
    }
  }

  # Things were passed in, but don't exist in the table.
  if (!$self->runner->{ignore_unknown_columns} && @unknowns) {
    my $msg = "The following names are in the spec, but not the table @{[$self->source_name]}\n";
    $msg .= join ',', sort @unknowns;
    $msg .= "\n";
    die $msg;
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

  warn "Received @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};

  # If, in the current stack of in-flight items, we've attempted to make this
  # exact item, die because we've obviously entered an infinite loop.
  if ($self->runner->has_item($self)) {
    die "ERROR: @{[$self->source_name]} (".np($self->spec).") was seen more than once\n";
  }
  $self->runner->add_item($self);

  # This resolves all of the values that can be resolved immediately.
  #   * Back references
  #   * Objects
  $self->resolve_direct_values;
  warn "After RDV @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};

  $self->runner->{hooks}{preprocess}->(
    $self->source_name, $self->source->source, $self->spec,
  );
  warn "After preprocess @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};

  $self->find_unique_match;
  if ($self->row && $self->runner->{die_on_unique_mismatch}) {
    my @failed;
    foreach my $c ( $self->source->columns ) {
      my $col_name = $c->name;

      next unless $self->has_value($col_name);

      my $row_value = $self->row->get_column($col_name);
      my $spec_value = $self->value($col_name);
      unless (compare_values($row_value, $spec_value)) {
        push @failed, "\t$col_name: row(@{[$row_value//'[undef]']}) spec(@{[$spec_value//'[undef]']})\n";
      }
    }
    if (@failed) {
      die "ERROR Retrieving unique @{[$self->source_name]} (".np($self->spec).") (".np($self->{create}).")\n" . join('', sort @failed) . $/ . np($self->runner->{duplicates}{$self->source_name}[-1]{criteria});
    }
  }

  $self->quarantine_children;
  warn "After quarantine_children @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};

  unless ($self->row) {
    $self->populate_parents(nullable => 0);
    warn "After populate_parents @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};
  }

  if ( ! $self->row && ! $self->meta->{create} ) {
    $self->find_any_match;
  }

  unless ($self->row) {
    $self->populate_columns;
    warn "After populate_columns @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};

    $self->oracle_ensure_populated_pk;

    warn "Creating @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).")\n" if $ENV{SIMS_DEBUG};
    my $row = eval {
      $self->source->resultset->create($self->{create});
    }; if ($@) {
      my $e = $@;
      warn "ERROR Creating @{[$self->source_name]} (".np($self->spec).") (".np($self->{create}).")\n";
      die $e;
    }
    $self->row($row);

    $self->{created} = 1;

    # This tracks everything that was created, not just what was requested.
    $self->runner->{created}{$self->source_name}++;

    $self->{trace}{made} = $self->{runner}{ids}{made}++;
    $self->{trace}{created} = $self->{create};

    # This occurs when a FK condition was specified, but the column is
    # nullable and we didn't find an existing parent row. We want to defer these
    # because self-referential values need to be set after creation.
    $self->populate_parents(nullable => 1);
  }
  $self->build_children;

  $self->runner->{hooks}{postprocess}->(
    $self->source_name, $self->source->source, $self->row,
  );

  $self->runner->remove_item($self);

  if ($ENV{SIMS_DEBUG}) {
    my %x = $self->row->get_columns;
    warn "Finished @{[$self->source_name]}($self) (".np($self->spec).") (".np($self->{create}).") (" . np(%x) . ")\n";
  }

  return $self->row;
}

sub populate_columns {
  my $self = shift;

  foreach my $c ( $self->source->columns_not_in_parent_relationships ) {
    my $col_name = $c->name;
    next if $self->{create}->{$col_name};

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
      elsif (reftype($self->spec->{$col_name}) eq 'SCALAR') {
        $self->{create}{$col_name} = $self->runner->convert_backreference(
          $self->runner->backref_name($self, $c->name),
          ${$self->spec->{$col_name}},
        );
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
        !$c->is_in_pk &&
        !$c->has_default_value
        # These clauses were in the original code. Do they still need to exist?
        # && !$c->is_in_uk
      ) {
        $self->{create}{$col_name} = $c->generate_value(die_on_unknown => 1);
      }
    }
  } continue {
    delete $self->{still_to_use}{$c->name};
  }

  return;
}

sub populate_parents {
  my $self = shift;
  my %opts = @_;

  RELATIONSHIP:
  foreach my $r ( $self->source->parent_relationships ) {
    my $col = $r->self_fk_col;

    if ( $opts{nullable} && !$self->source->column($col)->is_nullable ) {
      next RELATIONSHIP;
    }
    if ( !$opts{nullable} && $self->source->column($col)->is_nullable ) {
      next RELATIONSHIP;
    }

    if (!$self->runner->{allow_relationship_column_names}) {
      if ($col ne $r->name && exists $self->spec->{$col}) {
        die "Cannot use column $col - use relationship @{[$r->name]}";
      }
    }

    my $fkcol = $r->foreign_fk_col;
    my $proto = delete($self->spec->{$r->name}) // delete($self->spec->{$col});
    # TODO: Write a test if both the rel and the FK col are specified
    delete $self->{still_to_use}{$r->name};
    delete $self->{still_to_use}{$col};

    if ($self->{skip_relationship}{$r->name}) {
      next RELATIONSHIP;
    }

    my $spec;
    if ($proto) {
      if (blessed($proto)) {
        if ($opts{nullable}) {
          $self->row->set_column($col => $proto->get_column($fkcol));
          $self->row->update;
        }
        else {
          $self->{create}{$col} = $proto->get_column($fkcol);

          # Otherwise, the tracer will try and write out a blessed object.
          warn "Converting $col to @{[$self->{create}{$col}]}\n";
          $self->{trace}{spec}{$col} = $self->{create}{$col};
        }
        next RELATIONSHIP;
      }

      # Assume any hashref is a Sims specification
      if (ref($proto) eq 'HASH') {
        $spec = $proto;
      }
      # Use a referenced row
      elsif (ref($proto) eq 'SCALAR') {
        $spec = {
          $fkcol => $self->runner->convert_backreference(
            $self->runner->backref_name($self, $r->name), $$proto, $fkcol,
          ),
        };
      }
      # Assume any unblessed scalar is a column value.
      elsif (!ref($proto)) {
        $spec = { $fkcol => $proto };
      }
      else {
        die "Unsure what to do about @{[$r->full_name]}():" . np($proto);
      }
    }

    unless ( $spec ) {
      if ( $self->source->column($col)->is_nullable ) {
        next RELATIONSHIP;
      }

      $spec = {};
    }

    my $fk_source = $r->target;
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

      # We cannot add this relationship to the $spec because that would result
      # in an infinite loop. So, add a restriction to the parent's __META__
      $spec->{__META__} //= {};
      $spec->{__META__}{restriction} = {
        cond  => { join('.', $inverse[0]{rel}, $inverse[0]{col}) => undef },
        extra => { join => $inverse[0]{rel} },
      };
    }

    warn "Parent (@{[$fk_source->name]}): " . np($spec) .$/ if $ENV{SIMS_DEBUG};
    push @{$self->{runner}{traces}}, {
      table  => $fk_source->name,
      spec   => MyCloner::clone($spec // {}),
      seen   => $self->{runner}{ids}{seen}++,
      parent => $self->{trace}{seen},
    };
    my $fk_item = DBIx::Class::Sims::Item->new(
      runner => $self->runner,
      source => $fk_source,
      spec   => MyCloner::clone($spec // {}),
      trace  => $self->{runner}{traces}[-1],
    );
    $fk_item->set_allow_pk_to($self);
    $fk_item->create;

    if ($opts{nullable}) {
      $self->row->set_column($col => $fk_item->row->get_column($fkcol));
      $self->row->update;
    }
    else {
      $self->{create}{$col} = $fk_item->row->get_column($fkcol);
    }
  }

  return;
}

sub quarantine_children {
  my $self = shift;

  $self->{children} = {};
  foreach my $r ( $self->source->child_relationships ) {
    if ($self->spec->{$r->name}) {
      $self->{children}{$r->name} = $self->spec->{$r->name};
    }
  } continue {
    delete $self->{still_to_use}{$r->name};
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
      # Don't do "( ({}) x $r->constraints );" because that doesn't create
      # independent hashrefs.
      push @children, {} for 1 .. $r->constraints;
    }

    # TODO: Add a test for $self->{children} >= $r->constraints. For example,
    # $r->constraints == 2, but only one child was added by hand.

    my $fkcol = $r->foreign_fk_col;
    my $fk_source = $r->target;
    foreach my $child (@children) {
      # FIXME $child is a hashref, not a ::Item. add_child() needs to be able to
      # handle ::Item's, which requires ::Item's to be Comparable. It also means
      # the ::Runner's spec has been converted to ::Item before iteration.
      ($child->{__META__} //= {})->{allow_pk_set_value} = 1;

      # Do not do $self->row->get_column($col). This causes an infinite loop
      # because the child then needs a parent ::Item that tries to create a
      # child, and so forth.
      $child->{$fkcol} = $self->row;
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
    $self->{create}{$pk_columns[0]->name} = undef;
  }
}

1;
__END__
