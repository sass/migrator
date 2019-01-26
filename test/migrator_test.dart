// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sass_module_migrator/src/migrator.dart';
import 'package:sass_module_migrator/src/stylesheet_api.dart';
import 'package:test/test.dart';

void main() {
  testHrx("variables");
  testHrx("subdirectories");
  testHrx("functions");
  testHrx("mixins");
}

const testDirectory = "/test/";

class TestMigrator extends Migrator {
  Map<String, String> testFiles = {};

  TestMigrator(this.testFiles);

  @override
  String loadFile(Path path) =>
      testFiles[p.relative(path.path, from: testDirectory)];

  @override
  bool exists(Path path) =>
      testFiles.containsKey(p.relative(path.path, from: testDirectory));

  @override
  String entrypointDirectory = testDirectory;

  final List<String> logged = [];

  @override
  void log(String text) => logged.add(text);
}

class HrxTestFiles {
  Map<String, String> testFiles = {};
  Map<String, String> expectedOutput = {};
  Map<String, List<String>> recursiveManifest = {};

  HrxTestFiles(String hrxName) {
    var hrxText = File("test/migrations/$hrxName.hrx").readAsStringSync();
    // TODO(jathak): Replace this with an actual HRX parser.
    String filename;
    String contents;
    for (String line in hrxText.substring(0, hrxText.length - 1).split("\n")) {
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

  _load(String filename, String contents) {
    if (filename.startsWith("input/")) {
      testFiles[filename.substring(6)] = contents;
    } else if (filename.startsWith("expected/")) {
      expectedOutput[filename.substring(9)] = contents;
    } else if (filename == "recursive_manifest") {
      for (var line in contents.trim().split("\n")) {
        if (line.startsWith("#")) continue;
        var source = line.split("->").first.trim();
        var deps = line.split("->").last.trim();
        recursiveManifest[source] =
            deps.split(" ").map((x) => x.trim()).toList();
      }
    }
  }
}

testHrx(String hrxName) {
  var files = HrxTestFiles(hrxName);
  group(hrxName, () {
    for (var file in files.testFiles.keys) {
      test(file, () {
        var migrator = TestMigrator(files.testFiles);
        var migrated = migrator.runMigration(file);
        expect(migrated, equals(files.expectedOutput[file]));
      });
    }
    group("recursive from", () {
      for (var entry in files.recursiveManifest.keys) {
        test(entry, () {
          var migrator = TestMigrator(files.testFiles);
          var migrated =
              migrator.runMigrations([entry], migrateDependencies: true);
          expect(migrated[p.join(testDirectory, entry)],
              equals(files.expectedOutput[entry]));
          for (var dep in files.recursiveManifest[entry]) {
            expect(migrated[p.join(testDirectory, dep)],
                equals(files.expectedOutput[dep]));
          }
          expect(migrated.length,
              equals(files.recursiveManifest[entry].length + 1));
        });
      }
    });
  });
}
