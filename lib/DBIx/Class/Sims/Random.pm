# vim: set sw=2 ft=perl:
package DBIx::Class::Sims::Random;

use 5.010_001;

use strictures 2;

use base 'Exporter';

our @EXPORT_OK = qw(
  random_integer
  random_decimal
  random_string
  random_regex
  random_item
  random_choice
);

use String::Random ();

sub random_integer {
  my ($runner, $min, $max) = @_;
  return $min if $runner->{predictable_values};
  return int(rand($max-$min))+$min;
}

sub random_decimal {
  my ($runner, $min, $max) = @_;
  return $min if $runner->{predictable_values};
  return rand($max-$min)+$min;
}

sub random_string {
  my ($runner, $pattern, @choices) = @_;

  if ( $runner->{predictable_values} ) {
    no strict;
    no warnings 'redefine';
    local *{ "String::Random::_rand" } = sub { 0 };
    return String::Random::random_string($pattern, @choices);
  }
  return String::Random::random_string($pattern, @choices);
}

sub random_regex {
  my ($runner, $template) = @_;

  # This is reaching into the guts of String::Random. It may break at any time.
  if ( $runner->{predictable_values} ) {
    no strict;
    no warnings 'redefine';
    local *{ "String::Random::_rand" } = sub { 0 };
    return String::Random::random_regex($template);
  }
  return String::Random::random_regex($template);
}

sub random_item {
  my ($runner, $arr) = @_;
  return $runner->{predictable_values}
    ? $arr->[0] : $arr->[rand @$arr];
}

sub random_choice {
  my ($runner, $threshold) = @_;
  return $runner->{predictable_values}
      ? 1 : rand() < $threshold;
}

1;
__END__
