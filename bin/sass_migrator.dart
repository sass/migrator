// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:args/args.dart';

import 'package:sass_migrator/src/migrator.dart';
import 'package:sass_migrator/src/migrators/module.dart';

final migrators = <Migrator>[ModuleMigrator()];

void main(List<String> args) {
  var argParser = ArgParser(usageLineLength: 80)
    ..addFlag('dry-run',
        abbr: 'n',
        help: 'Show which files would be migrated but make no changes.')
    ..addFlag('verbose',
        abbr: 'v',
        help: 'Print text of migrated files when running with --dry-run.')
    ..addFlag('help', abbr: 'h', help: 'Print help text.', negatable: false);

  for (var migrator in migrators) {
    argParser.addSeparator('${migrator.name} migrator\n' +
        '=' * 80 +
        '\n${migrator.description}\n${migrator.argParser.usage}');
    argParser.addCommand(migrator.name, migrator.argParser);
  }
  var argResults = argParser.parse(args);

  if (argResults['help'] == true || argResults.command == null) {
    _printUsage(argParser);
    return;
  }

  Migrator migrator;

  try {
    migrator = migrators
        .singleWhere((migrator) => migrator.name == argResults.command.name);
  } on StateError {
    _printUsage(argParser);
    return;
  }
  migrator.argResults = argResults.command;
  var migrated = migrator.migrateFiles(argResults.command.rest);

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

void _printUsage(ArgParser argParser) {
  print('Runs a migrator on one or more Sass files.\n\n'
      'Usage: sass_migrator <migrator> [options] <entrypoint.scss ...>\n\n'
      '${argParser.usage}');
  exitCode = 64;
}
