requires 'strictures';
requires 'Clone::Any';
requires 'Data::Compare';
requires 'Data::Printer';
requires 'Data::Walk';
requires 'DateTime';
requires 'DBIx::Class::TopoSort' => '0.060000';
requires 'Hash::Merge';
requires 'List::Util';
requires 'List::MoreUtils';
requires 'Scalar::Util';
requires 'String::Random';
requires 'YAML::Any'; # Removes a warning.

on test => sub {
  requires 'File::Temp'        => '0.01';
  requires 'JSON'              => '0.01';
  requires 'Test::DBIx::Class' => '0.01';
  requires 'Test::Exception'   => '0.21';
  requires 'Test::More'        => '0.88'; # done_testing
  requires 'Test::Deep'        => '0.01';
  requires 'Test::Warn'        => '0.01';
  requires 'Test::Trap'        => '0.3.2';
  requires 'DBD::SQLite'       => '1.40';

  # All of the following are needed for Devel::Cover and its optional reports.
  requires 'Devel::Cover';
  requires 'Template';
  requires 'PPI::HTML';
  requires 'Perl::Tidy';
  requires 'Pod::Coverage::CountParents';
  requires 'JSON::MaybeXS';
  requires 'Parallel::Iterator';
};
