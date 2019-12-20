## 1.1.0

* Add support for glob inputs on the command line.

* Better handling when migrating files whose dependencies have complex
  import-only files.

### Module Migrator

* Make `--remove-prefix=<prefix> --forward=prefixed` forward members that
  previously started with `<prefix>` and were unprefixed by a previous migrator
  run. This includes cases where the previously removed prefix is longer than
  the prefix for the current migrator run.

## 1.0.1

### Module Migrator

* Improve ordering of `@use` and `@forward` rules.

* Fix a bug in the migrating of configurable variables. Variables should now
  only be considered configured when the configuring declaration is upstream of
  the `!default` declaration.

* When namespacing a negated variable, adds parentheses around it to prevent the
  `-` from being parsed as part of the namespace.

* Fix a bug in the migrating of removed color functions when the amount is a
  variable being namespaced.

## 1.0.0

* Initial release.
