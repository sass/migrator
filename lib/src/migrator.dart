// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/sass.dart';
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/importer.dart';
import 'package:sass/src/import_cache.dart';

import 'package:args/command_runner.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sass_migrator/src/util/node_modules_importer.dart';
import 'package:source_span/source_span.dart';

import 'exception.dart';
import 'io.dart';
import 'utils.dart';

/// A migrator is a command that migrates the entrypoints provided to it and
/// (optionally) their dependencies.
///
/// Migrators should provide their [name], [description], and optionally
/// [aliases].
///
/// Subclasses need to implement [migrateFile], which takes an entrypoint,
/// migrates it, and stores the results in [migrated]. If [migrateDependencies]
/// is true, they should also migrate all of that entrypoint's direct and
/// indirect dependencies.
///
/// Most migrators will want to create a subclass of [MigrationVisitor] and
/// implement [migrateFile] with `MyMigrationVisitor(this, entrypoint).run()`.
abstract class Migrator extends Command<Map<Uri, String>> {
  String get invocation => super
      .invocation
      .replaceFirst("[arguments]", "[options] <entrypoints.scss...>");

  String get usage => "${super.usage}\n\n"
      "See also https://sass-lang.com/documentation/cli/migrator#$name";

  /// If true, dependencies will be migrated in addition to the entrypoints.
  bool get migrateDependencies => globalResults!['migrate-deps'] as bool;

  /// Map of missing dependency URLs to the spans that import/use them.
  ///
  /// Subclasses should add any missing dependencies to this when they are
  /// encountered during migration. If using [MigrationVisitor], all items in
  /// its `missingDependencies` property should be added to this after calling
  /// `run`.
  final missingDependencies = <Uri, FileSpan>{};

  /// Runs this migrator on [stylesheet] (and its dependencies, if the
  /// --migrate-deps flag is passed).
  ///
  /// Files that did not require any changes, even if touched by the migrator,
  /// should not be included map of results.
  @protected
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer);

  /// Runs this migrator.
  ///
  /// Each entrypoint is migrated separately. If a stylesheet is migrated more
  /// than once, the resulting migrated contents must be the same each time, or
  /// this will error.
  ///
  /// Entrypoints and dependencies that did not require any changes will not be
  /// included in the results.
  Map<Uri, String> run() {
    var allMigrated = <Uri, String>{};
    var importer = FilesystemImporter('.');
    var importCache = ImportCache(
        importers: [NodeModulesImporter()],
        loadPaths: globalResults!['load-path']);

    var entrypoints = [
      for (var argument in argResults!.rest)
        for (var entry in Glob(argument).listSync())
          if (entry is File) entry.path
    ];
    for (var entrypoint in entrypoints) {
      var tuple =
          importCache.import(Uri.parse(entrypoint), baseImporter: importer);
      if (tuple == null) {
        throw MigrationException("Could not find Sass file at '$entrypoint'.");
      }

      var migrated = migrateFile(importCache, tuple.item2, tuple.item1);
      migrated.forEach((file, contents) {
        if (allMigrated.containsKey(file) && contents != allMigrated[file]) {
          throw MigrationException(
              "The migrator has found multiple possible migrations for $file, "
              "depending on the context in which it's loaded.");
        }
        allMigrated[file] = contents;
      });
    }

    if (missingDependencies.isNotEmpty) _warnForMissingDependencies();
    return allMigrated;
  }

  /// Prints warnings for any missing dependencies encountered during migration.
  ///
  /// By default, this prints a short warning with one line per missing
  /// dependency.
  ///
  /// In verbose mode, this instead prints a full warning with the source span
  /// for each missing dependency.
  void _warnForMissingDependencies() {
    if (globalResults!['verbose'] as bool) {
      for (var uri in missingDependencies.keys) {
        emitWarning("Could not find Sass file at '${p.prettyUri(uri)}'.",
            missingDependencies[uri]);
      }
    } else {
      var count = missingDependencies.length;
      emitWarning(
          "$count dependenc${count == 1 ? 'y' : 'ies'} could not be found.");
      missingDependencies.forEach((url, context) {
        printStderr('  ${p.prettyUri(url)} '
            '@${p.prettyUri(context.sourceUrl)}:${context.start.line + 1}');
      });
    }
  }
}
