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

    $self->{ids} = {
      seen => 1,
      made => 1,
    };
    my @objects = ();

    $self->{rows} = {};
    my %still_to_use = map { $_ => 1 } keys %{$self->{spec}};
    while (1) {
      foreach my $name ( @{$self->{toposort}} ) {
        next unless $self->{spec}{$name};
        delete $still_to_use{$name};

        while ( my $proto = shift @{$self->{spec}{$name}} ) {
          push @objects, {
            table => $name,
            spec => MyCloner::clone($proto),
            seen => $self->{ids}{seen}++,
            parent => 0,
          };

          $proto->{__META__} //= {};
          $proto->{__META__}{create} = 1;

          my $item = DBIx::Class::Sims::Item->new(
            runner => $self,
            source => $self->{sources}{$name},
            spec   => $proto,
            trace  => $objects[-1],
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

    if ( $self->{object_trace} ) {
      use JSON::MaybeXS qw( encode_json );
      open my $fh, '>', $self->{object_trace};
      print $fh encode_json({
        objects => \@objects,
      });
      close $fh;
    }

    return $self->{rows};
  });
}

1;
__END__
