// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:test/test.dart';

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
}
