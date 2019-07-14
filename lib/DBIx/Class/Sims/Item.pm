# This class exists to represent a row requested (and subsequently created) by
# the Sims. It will have a link back to a Sims::Source which will have the link
# back to the $schema object.

package DBIx::Class::Sims::Item;

use 5.010_001;

use strictures 2;

use DDP;

use Scalar::Util qw( blessed );

use DBIx::Class::Sims::Util qw( normalize_aoh );

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
# These are the expected interface methods
#
################################################################################

sub create {
  my $self = shift;

  $self->populate_columns;

  #warn "Creating @{[$self->source_name]} (".np($self->spec).")\n" if $ENV{SIMS_DEBUG};
  my $row = eval {
    $self->oracle_ensure_populated_pk;

    #warn 'Creating (' . np($self->{create}) . ")\n";
    $self->source->resultset->create($self->{create});
  }; if ($@) {
    my $e = $@;
    warn "ERROR Creating @{[$self->source_name]} (".np($self->spec).")\n";
    die $e;
  }
  $self->row($row);

  return $self->row;
}

sub populate_columns {
  my $self = shift;

  foreach my $c ( $self->source->columns ) {
    my $col_name = $c->name;

    my $spec;
    if ( exists $self->spec->{$col_name} ) {
      #if (
      #  reftype($spec) eq 'HASH' &&
      #  # Assume a blessed hash is a DBIC object
      #  !blessed($spec) &&
      #  # Do not assume we understand something to be inflated/deflated
      #  !$c->is_inflated
      #) {
      #  $sim_spec = delete $item->spec->{$col_name};
      #}
      #else {
        $self->{create}{$col_name} = $self->spec->{$col_name};
      #}
    }

    $spec //= $c->sim_spec;
    if ($spec) {
      $self->{create}{$col_name} = $c->resolve_sim_spec($spec, $self);
    }
    elsif (
      !exists $self->{create}{$col_name} &&
      !$c->is_nullable &&
      !$c->is_in_pk
    ) {
      $self->{create}{$col_name} = $c->generate_value(die_on_unknown => 1);
    }
  }

  #warn np($self->{create});
  return;
}

sub quarantine_children {
  my $self = shift;

  $self->{children} = {};
  foreach my $r ( $self->source->child_relationships ) {
    if ($self->spec->{$r->name}) {
      $self->{children}{$r->name} = delete $self->spec->{$r->name};
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
