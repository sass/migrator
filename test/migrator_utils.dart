// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

/// Runs all tests for [migrator].
///
/// HRX files should be stored in `test/migrators/<migrator name>/`.
void testMigrator(String migrator) {
  var migrationTests = Directory("test/migrators/$migrator");
  group(migrator, () {
    for (var file in migrationTests.listSync().whereType<File>()) {
      if (file.path.endsWith(".hrx")) {
        test(p.basenameWithoutExtension(file.path),
            () => _testHrx(file, migrator));
      }
    }
  });
}

/// Run the migration test in [hrxFile].
///
/// See migrations/README.md for details.
Future<void> _testHrx(File hrxFile, String migrator) async {
  var files = _HrxTestFiles(hrxFile.readAsStringSync());
  await files.unpack();

  var process = await TestProcess.start(
      Platform.executable,
      [
        "--enable-asserts",
        p.absolute("bin/sass_migrator.dart"),
        migrator,
        '--no-unicode'
      ]
        ..addAll(files.arguments)
        ..addAll(
            files.input.keys.where((path) => path.startsWith("entrypoint"))),
      workingDirectory: d.sandbox,
      description: "migrator");

  if (files.expectedLog != null) {
    expect(process.stdout,
        emitsInOrder(files.expectedLog.trimRight().split("\n")));
  }
  expect(process.stdout, emitsDone);
  await process.shouldExit(0);

  await Future.wait(files.output.keys
      .map((path) => d.file(path, files.output[path]).validate()));
}

class _HrxTestFiles {
  Map<String, String> input = {};
  Map<String, String> output = {};
  List<String> arguments = [];
  String expectedLog;

  _HrxTestFiles(String hrxText) {
    // TODO(jathak): Replace this with an actual HRX parser.
    String filename;
    String contents;
    for (var line in hrxText.substring(0, hrxText.length - 1).split("\n")) {
      if (line.startsWith("<==> ")) {
        if (filename != null) {
          _load(filename, contents.substring(0, contents.length - 1));
        }
        filename = line.substring(5).trim();
        contents = "";
      } else {
        contents += line + "\n";
      }
    }
    if (filename != null) _load(filename, contents);
  }

  void _load(String filename, String contents) {
    if (filename.startsWith("input/")) {
      input[filename.substring(6)] = contents;
    } else if (filename.startsWith("output/")) {
      output[filename.substring(7)] = contents;
    } else if (filename == "log.txt") {
      expectedLog = contents;
    } else if (filename == "arguments") {
      arguments = contents.trim().split(" ");
    }
  }

  /// Unpacks this test's input files into a temporary directory.
  Future unpack() async {
    for (var file in input.keys) {
      var parts = p.split(file);
      d.Descriptor descriptor = d.file(parts.removeLast(), input[file]);
      while (parts.isNotEmpty) {
        descriptor = d.dir(parts.removeLast(), [descriptor]);
      }
      await descriptor.create();
    }
  }
}
