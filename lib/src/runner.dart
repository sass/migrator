// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:isolate';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:term_glyph/term_glyph.dart' as glyph;

import 'io.dart';
import 'migrators/division.dart';
import 'migrators/module.dart';
import 'migrators/namespace.dart';
import 'exception.dart';

/// A command runner that runs a migrator based on provided arguments.
class MigratorRunner extends CommandRunner<Map<Uri, String>> {
  String get invocation =>
      "$executableName <migrator> [options] <entrypoint.scss...>";

  String get usage => "${super.usage}\n\n"
      "See also https://sass-lang.com/documentation/cli/migrator";

  MigratorRunner()
      : super("sass-migrator", "Migrates stylesheets to new Sass versions.") {
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
      ..addFlag('color',
          abbr: 'c', help: 'Whether to use terminal colors for messages..')
      ..addFlag('unicode',
          help: 'Whether to use Unicode characters for messages.')
      // TODO(jathak): Make this flag print a diff instead.
      ..addFlag('verbose',
          abbr: 'v', help: 'Print more information.', negatable: false)
      ..addFlag('version',
          help: 'Print the version of the Sass migrator.', negatable: false);
    addCommand(DivisionMigrator());
    addCommand(ModuleMigrator());
    addCommand(NamespaceMigrator());
  }

  /// Runs a migrator and then writes the migrated files to disk unless
  /// `--dry-run` is passed.
  Future execute(Iterable<String> args) async {
    ArgResults argResults;
    try {
      argResults = parse(args);
    } on UsageException catch (e) {
      printStderr(e);
      exitCode = 64;
      return;
    }

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
    } on UsageException catch (e) {
      printStderr(e);
      exitCode = 64;
      return;
    } on SourceSpanException catch (e) {
      printStderr(e.toString(
          color: argResults.wasParsed('color')
              ? argResults['color'] as bool /*!*/
              : supportsAnsiEscapes));
      printStderr('Migration failed!');
      exitCode = 1;
      return;
    } on MigrationException catch (e) {
      printStderr(e);
      printStderr('Migration failed!');
      exitCode = 1;
      return;
    }
    if (migrated == null) return;

    if (migrated.isEmpty) {
      print('Nothing to migrate!');
      return;
    }

    if (argResults['dry-run']) {
      print('Dry run. Logging migrated files instead of overwriting...\n');

      migrated.forEach((url, contents) {
        if (argResults['verbose']) {
          // This isn't *strictly* HRX format, since it can produce absolute
          // URLs rather than those that are relative to the HRX root, but we
          // just need it to be readable, not to interoperate with other tools.
          print('<===> ${p.prettyUri(url)}');
          print(contents);
        } else {
          print(p.prettyUri(url));
        }
      });
    } else {
      migrated.forEach((url, contents) {
        assert(url.scheme == null || url.scheme == "file",
            "$url is not a file path.");
        if (argResults['verbose']) print("Migrating ${p.prettyUri(url)}");
        File(url.toFilePath()).writeAsStringSync(contents);
      });
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
  if (version != null && version.isNotEmpty) return version;

  var libDir = p.fromUri(
      await Isolate.resolvePackageUri(Uri.parse('package:sass_migrator/')));
  var pubspec = File(p.join(libDir, '..', 'pubspec.yaml')).readAsStringSync();
  return pubspec
      .split("\n")
      .firstWhere((line) => line.startsWith('version: '))
      .split(" ")
      .last;
}
