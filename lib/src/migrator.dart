// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

abstract class Migrator {
  /// Name passed at the command line to use this migrator.
  String get name;

  /// Brief description of what this migrator does.
  String get description;

  /// Parser for the arguments that this migrator takes.
  ArgParser get argParser => ArgParser();

  /// Set by the executable based on [argParser] and the provided arguments.
  ArgResults argResults;

  /// Runs this migrator on [entrypoint], returning a map of migrated contents.
  ///
  /// This may also migrate dependencies of this entrypoint, depending on the
  /// migrator and its configuration.
  ///
  /// Files that did not require migration, even if touched by the migrator,
  /// should not be included map of results.
  p.PathMap<String> migrateFile(String entrypoint);

  /// Runs this migrator on multiple [entrypoints], returning a merged map of
  /// migrated contents.
  ///
  /// Each entrypoint is migrated separately. If a stylesheet is migrated more
  /// than once, the resulting migrated contents must be the same each time, or
  /// this will error.
  ///
  /// Entrypoints and dependencies that did not require any changes will not be
  /// included in the results.
  p.PathMap<String> migrateFiles(Iterable<String> entrypoints) {
    var allMigrated = p.PathMap<String>();
    for (var entrypoint in entrypoints) {
      var migrated = migrateFile(entrypoint);
      for (var file in migrated.keys) {
        if (allMigrated.containsKey(file) &&
            migrated[file] != allMigrated[file]) {
          throw UnsupportedError(
              "$file is migrated in more than one way by these entrypoints.");
        }
        allMigrated[file] = migrated[file];
      }
    }
    return allMigrated;
  }
}
