// Copyright 2026 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/command_runner.dart';

import '../exception.dart';

/// A class for migrators that were supported in previous versions but are not
/// supported any longer because the code they migrated from can no longer be
/// parsed.
class OutdatedMigrator extends Command<Map<Uri, String>> {
  final String name;

  String get description =>
      "A migrator that is no longer supported by this tool.\n"
      "The most recent version of sass_migrator that supported this is "
      "$_version.";

  /// The most recent version of `sass_migrator` that supported this migration.
  final String _version;

  @override
  bool get hidden => true;

  OutdatedMigrator(this.name, this._version);

  /// Prints an error message and exits.
  Map<Uri, String> run() {
    throw MigrationException(
      "The $name migrator is no longer supported by this tool.\n"
      "Please install sass_migrator $_version to do this migration.",
    );
  }
}
