// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/migrators/module.dart';

/// A command runner that runs a migrator based on provided arguments.
class MigratorRunner extends CommandRunner<Map<Uri, String>> {
  final invocation = "sass_migrator <migrator> [options] <entrypoint.scss...>";

  MigratorRunner()
      : super("sass_migrator", "Migrates stylesheets to new Sass versions.") {
    argParser.addFlag('migrate-deps',
        abbr: 'd', help: 'Migrate dependencies in addition to entrypoints.');
    argParser.addFlag('dry-run',
        abbr: 'n',
        help: 'Show which files would be migrated but make no changes.');
    // TODO(jathak): Make this flag print a diff instead.
    argParser.addFlag('verbose',
        abbr: 'v',
        help: 'Print text of migrated files when running with --dry-run.');
    addCommand(ModuleMigrator());
  }

  /// Runs a migrator and then writes the migrated files to disk unless
  /// `--dry-run` is passed.
  Future execute(Iterable<String> args) async {
    var argResults = parse(args);
    var migrated = await runCommand(argResults);
    if (migrated == null) return;

    if (migrated.isEmpty) {
      print('Nothing to migrate!');
      return;
    }

    if (argResults['dry-run']) {
      print('Dry run. Logging migrated files instead of overwriting...\n');
      for (var url in migrated.keys) {
        print('$url');
        if (argResults['verbose']) {
          print('=' * 80);
          print(migrated[url]);
          print('-' * 80);
        }
      }
    } else {
      for (var url in migrated.keys) {
        if (url.scheme != null && url.scheme != "file") {
          print("Cannot write to $url");
        }
        if (argResults['verbose']) print("Overwriting $url...");
        File(url.toFilePath()).writeAsStringSync(migrated[url]);
      }
    }
  }
}
