## 1.3.0

### Namespace Migrator

* Adds a new migrator for changing namespaces of `@use` rules.

* This migrator lets you change namespaces by matching regular expressions on
  existing namespaces or on `@use` rule URLs. You do this by passing scripts to
  the `--rename` flag in the form of `old-namespace to new-namespace` or
  `url rule-url to new-namespace` where `old-namespace` and `rule-url` are
  regular expressions that match the entirety of the existing namespace or the
  rule URL and `new-namespace` is an output pattern that can include references
  to captured groups from the matching regular expression (e.g. `\1`).

* Alternatively, you may use a sed-style syntax like
  `/old-namespace/new-namespace/` or `url/rule-url/new-namespace`.

* You can pass `--rename` multiple times and they will be checked in order
  until one matches (at which point subsequent renames will be ignored). You
  can also separate multiple renames with semicolons or line breaks.

* By default, if the renaming results in a conflict between multiple `@use`
  rules, the migration will fail, but you can force it to resolve conflicts with
  numerical suffixes by passing `--force`.

* This migrator will also check for `@use` rules without referenced members. If
  any of these results has a conflict, it will be resolved by namespacing the
  unreferenced rule with `_unreferenced#` instead of failing. You can disable
  this behavior with `--unreferenced=none` or have the migrator rename *all*
  unreferenced `@use` rules with this pattern (instead of just conflicting ones)
  by passing `--unreferenced=all`.

## 1.2.6

### Module Migrator

* Fix a bug where generated import-only files for index files would contain
  invalid forwards.

* Better handling for import-only files without corresponding regular files,
  including fixing a crash when `@import` rules for two files like this are
  adjacent to each other.

* Midstream files that both forward configurable variables and configure other
  variables themselves should now be properly migrated.

* When an `@import` rule is migrated to both a `@use` rule and a `@forward`
  rule, both rules will now be migrated in-place (previously, the `@use` rule
  would replace the `@import` rule and the `@forward` rule would be added after
  all other dependencies).

## 1.2.5

### Module Migrator

* The migrator now properly migrates built-in function calls with underscores
  (e.g. `map_get`).

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
