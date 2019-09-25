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

/// Whether to run tests using the Node.js executable, as opposed to the Dart VM
/// executable.
///
/// This is a global variable so that different test files can set it
/// differently and run the same tests.
var runNodeTests = false;

/// Whether [ensureExecutableUpToDate] has been called.
var _ensuredExecutableUpToDate = false;

/// Starts a Sass migrator process with the given [args].
Future<TestProcess> runMigrator(List<String> args) {
  expect(_ensuredExecutableUpToDate, isTrue,
      reason:
          "ensureExecutableUpToDate() must be called at top of the test file.");

  var executable = runNodeTests ? "node" : Platform.executable;

  var executableArgs = <String>[];
  if (runNodeTests) {
    executableArgs.add(p.absolute("build/sass_migrator.dart.js"));
  } else {
    executableArgs.add("--enable-asserts");

    var snapshotPath = "build/sass_migrator.dart.app.snapshot";
    executableArgs.add(p.absolute(File(snapshotPath).existsSync()
        ? snapshotPath
        : "bin/sass_migrator.dart"));
  }

  return TestProcess.start(executable, [...executableArgs, ...args],
      workingDirectory: d.sandbox, description: "migrator");
}

/// Runs all tests for [migrator].
///
/// HRX files should be stored in `test/migrators/<migrator name>/`.
void testMigrator(String migrator) {
  ensureExecutableUpToDate();

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

/// Creates a [setUpAll] that verifies that the compiled form of the migrator
/// executable is up-to-date, if necessary.
///
/// This should always be called before [runMigrator].
void ensureExecutableUpToDate() {
  setUpAll(() {
    _ensuredExecutableUpToDate = true;

    if (runNodeTests) {
      _ensureUpToDate("build/sass_migrator.dart.js", "pub run grinder js");
    } else {
      _ensureUpToDate("build/sass_migrator.dart.app.snapshot",
          'pub run grinder app-snapshot',
          ifExists: true);
    }
  });
}

/// Ensures that [path] (usually a compilation artifact) has been modified more
/// recently than all this package's source files.
///
/// If [path] isn't up-to-date, this throws an error encouraging the user to run
/// [commandToRun].
///
/// If [ifExists] is `true`, this won't throw an error if the file in question
/// doesn't exist.
void _ensureUpToDate(String path, String commandToRun, {bool ifExists: false}) {
  // Ensure path is relative so the error messages are more readable.
  path = p.relative(path);
  if (!File(path).existsSync()) {
    if (ifExists) return;
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
Future<void> _testHrx(File hrxFile, String migrator) async {
  var files = _HrxTestFiles(hrxFile.readAsStringSync());
  await files.unpack();

  var process = await runMigrator([
    migrator,
    '--no-unicode',
    ...files.arguments,
    for (var path in files.input.keys) if (path.startsWith("entrypoint")) path
  ]);

  if (files.expectedLog != null) {
    expect(process.stdout,
        emitsInOrder(files.expectedLog.trimRight().split("\n")));
  }
  expect(process.stdout, emitsDone);

  var expectedStderr = files.expectedError ?? files.expectedWarning;
  if (expectedStderr != null) {
    expect(
        process.stderr, emitsInOrder(expectedStderr.trimRight().split("\n")));
  }
  expect(process.stderr, emitsDone);

  await process.shouldExit(files.expectedError != null ? 1 : 0);

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
  String expectedError;
  String expectedWarning;

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
    } else if (filename == "error.txt") {
      expectedError = contents;
      if (expectedWarning != null) {
        throw "Only one of error.txt and warning.txt may be included in a "
            "given test.";
      }
    } else if (filename == "warning.txt") {
      expectedWarning = contents;
      if (expectedError != null) {
        throw "Only one of error.txt and warning.txt may be included in a "
            "given test.";
      }
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
