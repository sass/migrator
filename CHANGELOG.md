## 1.0.0-beta.1

* Too many changes to list.

## 1.0.0-alpha.5

* **Breaking change**: Remove `lib/runner.dart`. This package is only meant to
  be used as an executable, not as a library.

* **Breaking change**: Remove the option to negate the `--migrate-deps`,
  `--dry-run`, and `--verbose` flags.

* Expose `sass-migrator` as a globally-installable executable.

### Division Migrator

* Fix a type error.

### Module Migrator

* Convert removed color functions to `color.adjust()`.

## 1.0.0-alpha.4

* Internal changes only.

## 1.0.0-alpha.3

* Division migrator: Treat most slash operations within argument lists as
  division.
* Division migrator: Only migrate slash operations to slash-list calls in a
  non-plain-CSS context.

## 1.0.0-alpha.2

* Internal changes only.

## 1.0.0-alpha.1

* Initial alpha release.
