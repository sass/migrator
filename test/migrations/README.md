# Migration Tests

Each set of source files used for a test of the migrator is represented a single
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
