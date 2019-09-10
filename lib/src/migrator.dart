// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/import_cache.dart';

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

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
  /// If true, dependencies will be migrated in addition to the entrypoints.
  bool get migrateDependencies => globalResults['migrate-deps'] as bool;

  /// Map of missing dependency URLs to the spans that import/use them.
  ///
  /// Subclasses should add any missing dependencies to this when they are
  /// encountered during migration. If using [MigrationVisitor], all items in
  /// its `missingDependencies` property should be added to this after calling
  /// `run`.
  final missingDependencies = <Uri, FileSpan>{};

  /// Runs this migrator on [entrypoint] (and its dependencies, if the
  /// --migrate-deps flag is passed).
  ///
  /// Files that did not require any changes, even if touched by the migrator,
  /// should not be included map of results.
  @protected
  Map<Uri, String> migrateFile(ImportCache importCache, Uri entrypoint);

  /// Runs this migrator.
  ///
  /// Each entrypoint is migrated separately. If a stylesheet is migrated more
  /// than once, the resulting migrated contents must be the same each time, or
  /// this will error.
  ///
  /// Entrypoints and dependencies that did not require any changes will not be
  /// included in the results.
  Map<Uri, String> run() {
    var allMigrated = Map<Uri, String>();
    // TODO(jathak): Add support for passing loadPaths from command line.
    var importCache = ImportCache([], loadPaths: ['.']);
    for (var entrypoint in argResults.rest) {
      var canonicalUrl = importCache.canonicalize(Uri.parse(entrypoint)).item2;
      if (canonicalUrl == null) {
        throw MigrationException(
            "Error: Could not find Sass file at '$entrypoint'.");
      }

      var migrated = migrateFile(importCache, canonicalUrl);
      for (var file in migrated.keys) {
        if (allMigrated.containsKey(file) &&
            migrated[file] != allMigrated[file]) {
          throw MigrationException(
              "$file is migrated in more than one way by these entrypoints.");
        }
        allMigrated[file] = migrated[file];
      }
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
    if (globalResults['verbose'] as bool) {
      for (var uri in missingDependencies.keys) {
        emitWarning("Could not find Sass file at '${p.prettyUri(uri)}'.",
            missingDependencies[uri]);
      }
    } else {
      var count = missingDependencies.length;
      emitWarning(
          "$count dependenc${count == 1 ? 'y' : 'ies'} could not be found.");
      for (var uri in missingDependencies.keys) {
        var context = missingDependencies[uri];
        print('  ${p.prettyUri(uri)} '
            '@${p.prettyUri(context.sourceUrl)}:${context.start.line + 1}');
      }
    }
  }
}
