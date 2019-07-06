# This class exists to represent a row requested (and subsequently created) by
# the Sims. It will have a link back to a Sims::Source which will have the link
# back to the $schema object.

package DBIx::Class::Sims::Item;

use 5.010_001;

use strictures 2;

use Scalar::Util qw( blessed );

use DBIx::Class::Sims::Util;

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  # Lots of code assumes __META__ exists.
  # TODO: Should we check for _META__ or __META_ or __MTA__ etc?
  $self->spec->{__META__} //= {};

  #$self->{original} = MyCloner::clone($self->{spec});

  # Should we quarantine_children() immediately?

  return;
}

sub runner { $_[0]{runner} }
sub source { $_[0]{source} }
sub spec   { $_[0]{spec}   }

sub meta   { shift->spec->{__META__} }
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
      my $n = DBIx::Class::Sims::Util->normalize_aoh($self->{children}{$r->name});
      unless ($n) {
        die "Don't know what to do with @{[$r->full_name]}\n\t".np($self->row);
      }
      @children = @{$n};
    }
    else {
      # ASSUMPTION: The constraint provided in the relationship is a number.
      @children = ( ({}) x $r->constraints );
    }

    # Need to ensure that $self->{children} >= $r->constraints

    my $col = $r->self_fk_col;
    my $fkcol = $r->foreign_fk_col;
    my $fk_name = $r->short_fk_source;
    foreach my $child (@children) {
      # FIXME $child is a hashref, not a ::Item. add_child() needs to be able to
      # handle ::Item's, which requires ::Item's to be Comparable
      ($child->{__META__} //= {})->{allow_pk_set_value} = 1;

      $child->{$fkcol} = $self->row->get_column($col);
      $self->runner->add_child($fk_name, $fkcol, $child, $self->source_name);
    }
  }
}

1;
__END__
