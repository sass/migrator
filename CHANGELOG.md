## 1.2.4

### Module Migrator

* The migrator no longer crashes when it encounters an import-only file without
  a corresponding regular file.
* If an import-only file does not forward its corresponding regular file, the
  migrator no longer includes a `@use` rule for it.

## 1.2.3

* Updates help text to use the correct binary name (`sass-migrator`).

## 1.2.2

* No user-visible changes.

## 1.2.1

### Module Migrator

* Fixes a bug where semicolons would be missing when migrating an `@import` rule
  with multiple imports.

## 1.2.0

### Module Migrator

* The `--remove-prefix` flag can now take multiple prefixes.

* Correctly migrate assignments to members in already-migrated modules.

## 1.1.5

### Module Migrator

* Fix a few bugs when migrating files that imported members through multiple
  layers of import-only files.

## 1.1.4

### Module Migrator

* When generating import-only files that for files that used to import
  import-only files, forward the upstream import-only files.

* Don't double-prefix members imported from a prefixed `@forward` rule.

## 1.1.3

### Module Migrator

* Don't remove prefixes from members that would become invalid identifiers
  afterwards.

## 1.1.2

### Module Migrator

* Generate better `@use` rules for index files.

## 1.1.1

### Module Migrator

* When using `--forward=import-only`, `@forward` rules in an import-only file
  are now sorted with the regular file last, allowing variables in indirect
  dependencies to be configured.

* Fixes a bug where some references weren't renamed if a variable is declared
  twice when using `--remove-prefix`.

## 1.1.0

* Add support for glob inputs on the command line.

### Module Migrator

* Add `--forward=import-only` option, which will not forward any members through
  the regular entrypoint, but it will forward all members through the
  entrypoint's import-only file. `--forward=prefixed,import-only` is also
  supported, which will forward prefixed members through the regular entrypoint
  and all members through the import-only file.

* Make `--remove-prefix=<prefix> --forward=prefixed` forward members that
  previously started with `<prefix>` and were unprefixed by a previous migrator
  run. This includes cases where the previously removed prefix is longer than
  the prefix for the current migrator run.

* Better handling when migrating files whose dependencies have complex
  import-only files.

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
