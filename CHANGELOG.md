## 2.5.4

* No user-visible changes.

## 2.5.3

* No user-visible changes.

## 2.5.2

* No user-visible changes.

## 2.5.1

* No user-visible changes.

## 2.5.0

### `if()` Function Migrator

* Added a new `if-function` migrator to convert the legacy Sass `if()` function
  syntax into the new CSS syntax. See [the Sass website] for details.

  [the Sass website]: https://sass-lang.com/d/if-function

## 2.4.2

### Module Migrator

* Late `@import` rules can now be hoisted above safe at-rules in the same file.

* Fix a typo in the error message for late `@import` rules that could not be
  migrated.

* Fix a bug where hoisted `@use` rules with configuration would have incorrect
  syntax.

## 2.4.1

### Module Migrator

* Fix a bug where a duplicate namespace would be added to a reassignment of a
  variable from another module when running on a partially migrated file.

## 2.4.0

### Module Migrator

* Better handling of late `@import` rules. Previously, these were treated
  identically to nested imports, but now they can be hoisted to the top of the
  file where `@use` is allowed if they do not emit any CSS.

  To allow the migrator to hoist even late imports that _do_ emit CSS, use the
  `--unsafe-hoist` flag. `@import` rules that emit CSS will still be converted
  to `meta.load-css()` even with this flag if no Sass members are referenced
  from them.

  If there are any plain CSS at-rules that are used by your post-processing
  tools but never actually result in meaningful CSS, you can pass them
  (without the `@`) to `--safe-at-rule` so that the migrator doesn't consider
  them to emit CSS when handling late imports.

  The migrator's behavior when encountering actual nested imports remains
  unchanged.

* Fix a bug that resulted in duplicate `@use` rules when migrating stylesheets
  that contained both a `@use` and an `@import` of the same dependency.

## 2.3.3

### Module Migrator

* Fix some bugs in the conversion of private names that are referenced across
  files to public names, especially when `--remove-prefix` and/or multiple
  leading dashes/underscores are involved.

## 2.3.2

* Update to be compatible with the latest version of the Dart Sass AST.

## 2.3.1

### Color Function Migrator

* Fix a bug where deprecated color functions nested inside other functions would
  not be migrated.

## 2.3.0

* Add a `--pkg-importer` flag to enable loading dependencies from `pkg:` URLs
  with the same behavior as the compiler. Currently this only supports the
  Node.js package resolution algorithm, via `--pkg-importer=node`. For example,
  `@use "pkg:bootstrap"` will load `node_modules/bootstrap/scss/bootstrap.scss`.

## 2.2.1

### Module Migrator

* Fix a bug where plain CSS `min()` and `max()` functions would incorrectly
  be migrated to `math.min()` and `math.max()`.

## 2.2.0

### Module Migrator

* Add a new `--built-in-only` flag, which migrates global functions to their
  `sass:` module equivalents, while leaving `@import` rules unchanged.

* Fix bug where some functions (`opacity`, `is-bracketed`, and
  `selector-extend`) would not be migrated.

## 2.1.0

### Color Function Migrator

* Adds a new `color` migrator that migrates off of legacy color functions that
  were deprecated in Dart Sass 1.79.0.

## 2.0.3

### Module Migrator

* Fixes some crashes due to null pointer errors.

## 2.0.2

### Calc Functions Interpolation Migrator

* Fix the interpretation of a dash in a variable name as a minus sign.

## 2.0.1

### Calc Functions Interpolation Migrator

* Add parentheses in place of interpolation when necessary to preserve the evaluation order.
* Keep interpolation in `var()` CSS functions.

## 2.0.0

* **Breaking change**: The `media-logic` migrator has been removed as the
  [corresponding breaking change][media logic] has been completed in Dart Sass.
  If you still need to migrate legacy code, use migrator version 1.8.1.

  [media logic]: https://sass-lang.com/documentation/breaking-changes/media-logic/

* Update to be compatible with the latest version of the Dart Sass AST.

### Division Migrator

* `/` division should now be left untouched in all CSS calculation functions.
  This was already the case for `calc`, `clamp`, `min`, and `max`, but it now
  applies to the new functions that Dart Sass 1.67.0 added support for.

## 1.8.1

### Calc Functions Interpolation Migrator

* Migration for more than one interpolation or expressions in a calc function
  parameter.

## 1.8.0

### Calc Functions Interpolation Migrator

* Removes interpolation in calculation functions `calc()`, `clamp()`, `min()`,
  and `max()`. See the [scss/function-calculation-no-interpolation] rule for
  more information.

  [scss/function-calculation-no-interpolation]: https://github.com/stylelint-scss/stylelint-scss/tree/master/src/rules/function-calculation-no-interpolation

## 1.7.3

* Fixes a bug where path arguments on the command line were incorrectly treated
  as URLs, resulting in errors finding paths containing certain special
  characters.

## 1.7.2

### Module Migrator

* Fixes a rare crash in certain cases involving reassignments of variables from
  another module.

## 1.7.1

* Eliminates invalid warnings when running `--migrate-deps` on a file that
  uses a built-in module.

## 1.7.0

### Media Logic Migrator

* Adds a new migrator for migrating [deprecated `@media` query logic].

[deprecated `@media` query logic]: https://sass-lang.com/d/media-logic

## 1.6.0

### Strict Unary Migrator

* Add a new migrator for eliminating ambiguous syntax for the `+` and `-`
  operators that will soon be deprecated.

## 1.5.6

* No user-visible changes.

## 1.5.5

* No user-visible changes.

## 1.5.4

### Module Migrator

* Fix a bug where the built-in function `keywords` was incorrectly migrated.

## 1.5.3

### Division Migrator

* Fix a bug where division inside calc expressions was unnecessarily migrated.

## 1.5.2

* No user-visible changes.

## 1.5.1

### Division Migrator

* Fix a bug where some division nested in a parenthesized expression would not
  be migrated.

## 1.5.0

### Division Migrator

* When migrating division where the divisor is a common constant value, the
  migrator will now convert it to multiplication, rather than `math.div`.

  For example: `$variable / 2` would be migrated to `$variable * 0.5`.

  To disable this and migrate all division to `math.div`, pass
  `--no-multiplication`.

## 1.4.5

* Glob syntax will no longer be resolved if a file with that literal name
  exists.

## 1.4.4

### Division Migrator

* Fix a bug where `@use "sass:math"` would sometimes be incorrectly inserted
  after other rules.

## 1.4.3

### Division Migrator

* Fix a crash when encountering parentheses in an expression that's definitely
  not division.

## 1.4.2

### Division Migrator

* Fix a bug where negated division could be migrated incorrectly.

## 1.4.1

* Globs containing `**` should now be properly resolved when running on Node.

## 1.4.0

### Division Migrator

* The division migrator is now enabled, and will convert slash-as-division to
  the `math.div` function.

## 1.3.9

* Fix crash when running on Node.

## 1.3.8

* No user-visible changes.

## 1.3.7

### Module Migrator

* Fix a crash in a rare edge case involving orphan import-only files and
  multiple load paths.

## 1.3.6

### Module Migrator

* Fix a bug that could result in unnecessary import-only files being generated
  when running `--forward=import-only` on a file with no dependencies.

## 1.3.5

### Module Migrator

* Fix a bug where `@use` rules could be duplicated if the same file is depended
  on via both an indirect `@import` and an existing `@use` rule.

* Fix a bug where imports of orphan import-only files that only forward other
  import-only files would not be removed.

## 1.3.4

### Module Migrator

* Fix a crash when resolving references to orphan import-only files in a
  different directory from the file depending on them.

## 1.3.3

* No user-visible changes.

## 1.3.2

### Module Migrator

* Fix a bug on Windows where load paths would not be used in some cases.

## 1.3.1

### Module Migrator

* Prefixes will now be removed from private members (e.g. a variable
  `$_lib-variable` will be renamed to `$_variable` when `--remove-prefix=lib-`
  is passed).

* Fix a bug where private members would be incorrectly added to `hide` clauses
  in generated import-only files.

## 1.3.0

### Namespace Migrator

* Add a new migrator for changing namespaces of `@use` rules.

  This migrator lets you change namespaces by matching regular expressions on
  existing namespaces or on `@use` rule URLs.

  You do this by passing expressions to the `--rename` in one of the following
  forms:

  * `<old-namespace> to <new-namespace>`: The `<old-namespace>` regular
    expression matches the entire existing namespace, and `<new-namespace>` is
    the replacement.

  * `url <rule-url> to <new-namespace>`: The `<old-namespace>` regular
    expression matches the entire URL in the `@use` rule, and `<new-namespace>`
    is the namespace that's chosen for it.

  The `<new-namespace>` patterns can include references to [captured groups][]
  from the matching regular expression (e.g. `\1`).

  [captured groups]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions/Groups_and_Ranges

  You can pass `--rename` multiple times and they will be checked in order until
  one matches (at which point subsequent renames will be ignored). You can also
  separate multiple rename expressions with semicolons or line breaks.

  By default, if the renaming results in a conflict between multiple `@use`
  rules, the migration will fail, but you can force it to resolve conflicts with
  numerical suffixes by passing `--force`.

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
