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
///
/// If [node] is `true`, runs the Node.js version of the executable. Otherwise,
/// runs the Dart VM version.
void testMigrator(String migrator, {bool node: false}) {
  if (node) {
    _ensureUpToDate("build/sass_migrator.dart.js", "pub run grinder js");
  }

  var migrationTests = Directory("test/migrators/$migrator");
  group(migrator, () {
    for (var file in migrationTests.listSync().whereType<File>()) {
      if (file.path.endsWith(".hrx")) {
        test(p.basenameWithoutExtension(file.path),
            () => _testHrx(file, migrator, node: node));
      }
    }
  });
}

/// Ensures that [path] (usually a compilation artifact) has been modified more
/// recently than all this package's source files.
///
/// If [path] isn't up-to-date, this throws an error encouraging the user to run
/// [commandToRun].
void _ensureUpToDate(String path, String commandToRun) {
  // Ensure path is relative so the error messages are more readable.
  path = p.relative(path);
  if (!File(path).existsSync()) {
    throw "$path does not exist. Run $commandToRun.";
  }

  var lastModified = File(path).lastModifiedSync();
  var entriesToCheck = Directory("lib").listSync(recursive: true).toList();

  // If we have a dependency override, "pub run" will touch the lockfile to mark
  // it as newer than the pubspec, which makes it unsuitable to use for
  // freshness checking.
  if (File("pubspec.yaml")
      .readAsStringSync()
      .contains("dependency_overrides")) {
    entriesToCheck.add(File("pubspec.yaml"));
  } else {
    entriesToCheck.add(File("pubspec.lock"));
  }

  for (var entry in entriesToCheck) {
    if (entry is File) {
      var entryLastModified = entry.lastModifiedSync();
      if (lastModified.isBefore(entryLastModified)) {
        throw "${entry.path} was modified after ${p.prettyUri(p.toUri(path))} "
            "was generated.\n"
            "Run $commandToRun.";
      }
    }
  }
}

/// Run the migration test in [hrxFile].
///
/// See migrations/README.md for details.
///
/// If [node] is `true`, runs the Node.js version of the executable. Otherwise,
/// runs the Dart VM version.
Future<void> _testHrx(File hrxFile, String migrator, {bool node: false}) async {
  var files = _HrxTestFiles(hrxFile.readAsStringSync());
  await files.unpack();

  var executable = node ? "node" : Platform.executable;
  var executableArgs = node
      ? [p.absolute("build/sass_migrator.dart.js")]
      : ["--enable-asserts", p.absolute("bin/sass_migrator.dart")];

  var process = await TestProcess.start(
      executable,
      executableArgs
        ..addAll([migrator, '--no-unicode'])
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

  await Future.wait([
    Future.wait(files.output.keys
        .map((path) => d.file(path, files.output[path]).validate())),
    // Ensure that the migrator *doesn't* migrate files it's not supposed to.
    Future.wait(files.input.keys
        .where((path) => !files.output.containsKey(path))
        .map((path) => d.file(path, files.input[path]).validate()))
  ]);
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
