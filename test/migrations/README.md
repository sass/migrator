# Migration Tests

Each set of source files used for a test of the migrator is represented a single
[HRX archive](https://github.com/google/hrx).

> Note: The test script does not currently use a proper HRX parser, so `<==>` is
> only boundary allowed.

Each HRX archive should have two root directories, `input` and `expected`, and
optionally one file at the root, `recursive_manifest`.

All source files to be migrated should live in `input` (or its subdirectories).
These files should not attempt to import any other files outside of the `input`
directory of this HRX archive.

For each source file in `input`, there should be a corresponding file in
`expected` that represents the expected output of the migrator for that file.

By default, each source file in `input` will be individually migrated and then
compared to the corresponding file in `expected`.

See `variables.hrx` for an example.
