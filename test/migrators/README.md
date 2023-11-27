# Migration Tests

Each migrator should have a directory `<migrator-name>` that contains that
migrator's HRX tests.

A line `testMigrator(<migrator-name>)` should then be added to the `main`
function of `migrator_dart_test.dart`.

## HRX Format

Each set of source files used for a test of a migrator is represented a single
[HRX archive](https://github.com/google/hrx).

> Note: The test script does not currently use a proper HRX parser, so `<==>` is
> the only boundary allowed.

Each HRX archive should have two root directories, `input` and `output`.

The `input` directory should contain one or more Sass files with paths starting
with `entrypoint` (e.g. `input/entrypoint.scss`). These files should not attempt
to import any other files outside of the `input` directory of this HRX archive.
The migrator will run starting from these entrypoints.

For each file in `input` that would be modified by this migration, there should
be a corresponding file in `output` with the migrated contents. `output` should
not contain a file if it would not be changed by the migrator.

The migration's expected standard output should be included in a file named
`log.txt`. Its standard error should be included in a file called `error.txt` if
the migration fails, or `warning.txt` if it completes successfully.

## Testing
Run `dart run grinder pkg-compile-snapshot-dev` for compiling the latest changes of code, 
`dart test` for running all tests and `dart test -x node` to run all tests except the node tests.
