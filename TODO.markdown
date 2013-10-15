* Return back the whole object, not just the primary keys
* Allow `{ Artist => 2 }` as a synonym for `{ Artist => [ {}, {} ] }`
* Add a time sim\_type which takes the following values:
   * yesterday, today, tomorrow
   * Date::Calc-parsable datetimes
* Allow a column value in load\_sims() to be a sim specification, such as:
```perl
load_sims({
    Artist => [
        {
            name => 'Joe',
            birth_date => {
                type => 'time',
                value => 'yesterday',
            },
        }
    ],
});
* Fnord
