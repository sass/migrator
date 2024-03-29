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

/// Whether to run tests using the Node.js executable, as opposed to the Dart VM
/// executable.
///
/// This is a global variable so that different test files can set it
/// differently and run the same tests.
var runNodeTests = false;

/// Starts a Sass migrator process with the given [args].
Future<TestProcess> runMigrator(List<String> args) =>
    pkg.start('sass-migrator', args,
        node: runNodeTests,
        workingDirectory: d.sandbox,
        description: "migrator",
        encoding: utf8);

/// Runs all tests for [migrator].
///
/// HRX files should be stored in `test/migrators/<migrator name>/`.
void testMigrator(String migrator) {
  setUpAll(() {
    pkg.ensureExecutableUpToDate('sass-migrator', node: runNodeTests);
  });

  var dir = "test/migrators/$migrator";
  group(migrator, () {
    for (var file
        in Directory(dir).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith(".hrx")) {
        test(p.withoutExtension(p.relative(file.path, from: dir)),
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

  var process = await runMigrator([
    migrator.replaceAll('_', '-'),
    '--no-unicode',
    ...files.arguments,
    for (var path in files.input.keys)
      if (path.startsWith("entrypoint")) path
  ]);

  var expectedLog = files.expectedLog;
  if (expectedLog != null) {
    expect(process.stdout, emitsInOrder(expectedLog.trimRight().split("\n")));
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
  Map<String, String?> input = {};
  Map<String, String?> output = {};
  List<String> arguments = [];
  String? expectedLog;
  String? expectedError;
  String? expectedWarning;

  _HrxTestFiles(String hrxText) {
    // TODO(jathak): Replace this with an actual HRX parser.
    String? filename;
    var contents = "";
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

  void _load(String filename, String? contents) {
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
      arguments = [
        for (var match in _argParseRegex.allMatches(contents!))
          match.group(1) ??
              match.group(2) ??
              match.group(3) ??
              (throw ArgumentError('Bad arguments for test'))
      ];
    }
  }

  /// Matches arguments, including quoted strings (but not escapes).
  ///
  /// To get the actual argument, you need to check groups 1, 2, and 3 (for
  /// double-quoted, single-quoted, and unquoted strings respectively).
  final _argParseRegex = RegExp(r'''"([^"]+)"|'([^']+)'|([^'"\s][^\s]*)''');

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
