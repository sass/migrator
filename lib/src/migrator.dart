// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';

/// A migrator is a command the migrates the entrypoints provided to it and
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
abstract class Migrator extends Command<p.PathMap<String>> {
  /// The entrypoints that this migrator will run from.
  List<String> get entrypoints => argResults.rest;

  /// If true, dependencies will be migrated in addition to the entrypoints.
  bool get migrateDependencies => globalResults['migrate-deps'] as bool;

  /// Migrated contents of stylesheets that have already been migrated.
  final migrated = p.PathMap<String>();

  /// Runs this migrator on [entrypoint] (and its dependencies, if the
  /// --migrate-deps flag is passed).
  ///
  /// Files that did not require any changes, even if touched by the migrator,
  /// should not be included map of results.
  void migrateFile(String entrypoint);

  /// Runs this migrator.
  ///
  /// Each entrypoint is migrated separately. If a stylesheet is migrated more
  /// than once, the resulting migrated contents must be the same each time, or
  /// this will error.
  ///
  /// Entrypoints and dependencies that did not require any changes will not be
  /// included in the results.
  p.PathMap<String> run() {
    var allMigrated = p.PathMap<String>();
    for (var entrypoint in entrypoints) {
      migrated.clear();
      migrateFile(canonicalizePath(p.join(Directory.current.path, entrypoint)));
      for (var file in migrated.keys) {
        if (allMigrated.containsKey(file) &&
            migrated[file] != allMigrated[file]) {
          throw MigrationException(
              "$file is migrated in more than one way by these entrypoints.");
        }
        allMigrated[file] = migrated[file];
      }
    }
    return allMigrated;
  }
}
