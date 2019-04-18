// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/importer/filesystem.dart';

import 'package:path/path.dart' as p;
import 'package:term_glyph/term_glyph.dart' as glyph;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'package:sass_migrator/runner.dart';

/// Runs all tests for [migrator].
///
/// HRX files should be stored in `test/migrators/<migrator name>/`.
void testMigrator(String migrator) {
  glyph.ascii = true;
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
_testHrx(File hrxFile, String migrator) async {
  var files = _HrxTestFiles(hrxFile.readAsStringSync());
  await files.unpack();
  Map<Uri, String> migrated;
  var entrypoints =
      files.input.keys.where((path) => path.startsWith("entrypoint"));
  var arguments = [migrator]..addAll(files.arguments)..addAll(entrypoints);
  await expect(
      () => IOOverrides.runZoned(() async {
            migrated = await MigratorRunner().run(arguments);
          }, getCurrentDirectory: () => Directory(d.sandbox)),
      prints(files.expectedLog?.replaceAll("\$TEST_DIR", d.sandbox) ?? ""));
  var importer = FilesystemImporter(d.sandbox);
  for (var file in files.input.keys) {
    expect(migrated[importer.canonicalize(Uri.parse(file))],
        equals(files.output[file]),
        reason: 'Incorrect migration of $file.');
  }
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
