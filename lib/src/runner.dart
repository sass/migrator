// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:term_glyph/term_glyph.dart' as glyph;

import 'io.dart';
import 'migrators/division.dart';
import 'migrators/module.dart';
import 'utils.dart';

/// A command runner that runs a migrator based on provided arguments.
class MigratorRunner extends CommandRunner<Map<Uri, String>> {
  final invocation = "sass_migrator <migrator> [options] <entrypoint.scss...>";

  MigratorRunner()
      : super("sass_migrator", "Migrates stylesheets to new Sass versions.") {
    argParser
      ..addMultiOption('load-path',
          abbr: 'I',
          valueHelp: 'PATH',
          help: 'A path to use when resolving imports.\n'
              'May be passed multiple times.',
          splitCommas: false)
      ..addFlag('migrate-deps',
          abbr: 'd',
          help: 'Migrate dependencies in addition to entrypoints.',
          negatable: false)
      ..addFlag('dry-run',
          abbr: 'n',
          help: 'Show which files would be migrated but make no changes.',
          negatable: false)
      ..addFlag(
        'unicode',
        help: 'Whether to use Unicode characters for messages.',
      )
      // TODO(jathak): Make this flag print a diff instead.
      ..addFlag('verbose',
          abbr: 'v', help: 'Print more information.', negatable: false)
      ..addFlag('version',
          help: 'Print the version of the Sass migrator.', negatable: false);
    addCommand(DivisionMigrator());
    addCommand(ModuleMigrator());
  }

  /// Runs a migrator and then writes the migrated files to disk unless
  /// `--dry-run` is passed.
  Future execute(Iterable<String> args) async {
    var argResults = parse(args);
    if (argResults['version'] as bool) {
      print(await _loadVersion());
      exitCode = 0;
      return;
    }

    if (argResults.wasParsed('unicode')) {
      glyph.ascii = !(argResults['unicode'] as bool);
    }
    Map<Uri, String> migrated;
    try {
      migrated = await runCommand(argResults);
    } on MigrationException catch (e) {
      print(e);
      print('Migration failed!');
      return;
    }
    if (migrated == null) return;

    if (migrated.isEmpty) {
      print('Nothing to migrate!');
      return;
    }

    if (argResults['dry-run']) {
      print('Dry run. Logging migrated files instead of overwriting...\n');
      for (var url in migrated.keys) {
        print(p.prettyUri(url));
        if (argResults['verbose']) {
          print('=' * 80);
          print(migrated[url]);
          print('-' * 80);
        }
      }
    } else {
      for (var url in migrated.keys) {
        assert(url.scheme == null || url.scheme == "file",
            "$url is not a file path.");
        if (argResults['verbose']) print("Migrating ${p.prettyUri(url)}");
        File(url.toFilePath()).writeAsStringSync(migrated[url]);
      }
    }
  }
}

/// Loads and returns the current version of the Sass migrator.
Future<String> _loadVersion() async {
  var version = const String.fromEnvironment('version');
  if (const bool.fromEnvironment('node')) {
    version += " compiled with dart2js "
        "${const String.fromEnvironment('dart-version')}";
  }
  if (version != null) return version;

  var libDir = p.fromUri(
      await Isolate.resolvePackageUri(Uri.parse('package:sass_migrator/')));
  var pubspec = File(p.join(libDir, '..', 'pubspec.yaml')).readAsStringSync();
  return pubspec
      .split("\n")
      .firstWhere((line) => line.startsWith('version: '))
      .split(" ")
      .last;
}
