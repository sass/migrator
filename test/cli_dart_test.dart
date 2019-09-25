// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'utils.dart';

void main() {
  ensureExecutableUpToDate();

  test("--version prints the migrator version", () async {
    var migrator = await runMigrator(["--version"]);
    expect(migrator.stdout, emits(matches(RegExp(r"^\d+\.\d+\.\d+"))));
    await migrator.shouldExit(0);
  });

  test("--help prints the usage documentation", () async {
    // Checking the entire output is brittle, so just do a sanity check to make
    // sure it's not totally busted.
    var migrator = await runMigrator(["--help"]);
    expect(
        migrator.stdout, emits("Migrates stylesheets to new Sass versions."));
    expect(migrator.stdout,
        emitsThrough(contains("Print this usage information.")));
    await migrator.shouldExit(0);
  });

  group("gracefully handles", () {
    test("an error from a migrator", () async {
      await d.file("test.scss", "@import 'nonexistent'").create();

      var migrator = await runMigrator(["--no-unicode", "module", "test.scss"]);
      expect(
          migrator.stderr,
          emitsInOrder([
            "line 1, column 9 of test.scss: Error: Could not find Sass file at "
                "'nonexistent'.",
            "  ,",
            "1 | @import 'nonexistent'",
            "  |         ^^^^^^^^^^^^^",
            "  '",
            "Migration failed!"
          ]));
      await migrator.shouldExit(1);
    });
  });
}
