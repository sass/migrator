// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:args/args.dart';
import 'package:meta/meta.dart';

import 'package:sass_migrate_to_modules/src/migrator.dart';

void main(List<String> args) {
  var argParser = new ArgParser()
    ..addFlag('dry-run',
        abbr: 'n',
        help: 'Show which files would be migrated but make no changes.')
    ..addFlag('verbose',
        abbr: 'v',
        help: 'Print text of migrated files when running with --dry-run.')
    ..addFlag('help', abbr: 'h', help: 'Print help text.', negatable: false);
  var argResults = argParser.parse(args);

  if (argResults['help'] == true || argResults.rest.isEmpty) {
    print(
        'Migrates a scss file and its dependencies to the new module system.\n\n'
        'Usage: sass_migrate_to_modules [options] <entrypoint.scss ...>\n\n'
        '${argParser.usage}');
    exitCode = 64;
    return;
  }

  var migrated = Migrator().runMigrations(argResults.rest);

  if (migrated.isEmpty) {
    print('Nothing to migrate!');
    return;
  }

  if (argResults['dry-run']) {
    print('Dry run. Logging migrated files instead of overwriting...\n');
    for (var path in migrated.keys) {
      print('$path');
      if (argResults['verbose']) {
        print('=' * 80);
        print(migrated[path]);
      }
    }
  } else {
    for (var path in migrated.keys) {
      if (argResults['verbose']) print("Overwriting $path...");
      File(path).writeAsStringSync(migrated[path]);
    }
  }
}
