// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:term_glyph/term_glyph.dart' as glyph;

import 'io.dart';
import 'migrators/division.dart';
import 'migrators/module.dart';

/// A command runner that runs a migrator based on provided arguments.
class MigratorRunner extends CommandRunner<Map<Uri, String>> {
  final invocation = "sass_migrator <migrator> [options] <entrypoint.scss...>";

  MigratorRunner()
      : super("sass_migrator", "Migrates stylesheets to new Sass versions.") {
    argParser
      ..addFlag('migrate-deps',
          abbr: 'd', help: 'Migrate dependencies in addition to entrypoints.')
      ..addFlag('dry-run',
          abbr: 'n',
          help: 'Show which files would be migrated but make no changes.')
      ..addFlag('unicode',
          help: 'Whether to use Unicode characters for messages.')
      // TODO(jathak): Make this flag print a diff instead.
      ..addFlag('verbose',
          abbr: 'v',
          help: 'Print text of migrated files when running with --dry-run.');
    addCommand(DivisionMigrator());
    addCommand(ModuleMigrator());
  }

  /// Runs a migrator and then writes the migrated files to disk unless
  /// `--dry-run` is passed.
  Future execute(Iterable<String> args) async {
    var argResults = parse(args);
    if (argResults['unicode'] != null) {
      glyph.ascii = !(argResults['unicode'] as bool);
    }

    var migrated = await runCommand(argResults);
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
        if (argResults['verbose']) print("Overwriting $url...");
        File(url.toFilePath()).writeAsStringSync(migrated[url]);
      }
    }
  }
}
