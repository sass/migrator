// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';
import 'dart:convert';

import 'package:grinder/grinder.dart';

import 'package:cli_pkg/cli_pkg.dart' as pkg;

export 'grind/sanity_check.dart';

main(List<String> args) {
  pkg.humanName = "Sass Migrator";
  pkg.botName = "Sass Bot";
  pkg.botEmail = "sass.bot.beep.boop@gmail.com";
  pkg.executables = {"sass-migrator": "bin/sass_migrator.dart"};
  pkg.homebrewRepo = "sass/homebrew-sass";
  pkg.homebrewFormula = "migrator.rb";
  pkg.jsRequires = {"fs": "fs", "os": "os", "path": "path"};
  pkg.npmPackageJson =
      json.decode(File("package/package.json").readAsStringSync())
          as Map<String, Object>;
  pkg.npmReadme = File("README.md").readAsStringSync();
  pkg.standaloneName = "sass-migrator";

  pkg.githubReleaseNotes = "";

  pkg.addAllTasks();
  grind(args);
}
