// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:cli_pkg/testing.dart' as pkg;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

import 'hrx.dart';

/// Whether to run tests using the Node.js executable, as opposed to the Dart VM
/// executable.
///
/// This is a global variable so that different test files can set it
/// differently and run the same tests.
var runNodeTests = false;

// Where the .hrx files are located for each migrator.
var migratorTestsHrxDir = "test/migrators/";

/// Makes sure the sass-migrator executable
void validateMigratorExecutable() {
  pkg.ensureExecutableUpToDate('sass-migrator', node: runNodeTests);
}

/// Starts a Sass migrator process with the given [args].
Future<TestProcess> runMigratorExecutable(List<String> args) {
  return pkg.start('sass-migrator', args,
      node: runNodeTests,
      workingDirectory: d.sandbox,
      description: "migrator",
      encoding: utf8);
}

/// Runs all tests for [migrator].
///
/// HRX files should be stored in `test/migrators/<migrator name>/`.
void testMigrator(String migrator) {
  setUpAll(() {
    validateMigratorExecutable();
  });

  var hrxTestDir = '$migratorTestsHrxDir$migrator';
  group(migrator, () {
    var files =
        Directory(hrxTestDir).listSync(recursive: true).whereType<File>();
    for (var file in files) {
      if (file.path.endsWith(".hrx")) {
        var testName =
            p.withoutExtension(p.relative(file.path, from: hrxTestDir));
        test(testName, () async {
          await hrxExecutableTest(file, (arguments) {
            return runMigratorExecutable(
                [migrator.replaceAll('_', '-'), '--no-unicode', ...arguments]);
          });
        });
      }
    }
  });
}
