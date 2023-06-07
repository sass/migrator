// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:collection/collection.dart';
import 'package:grinder/grinder.dart';

main(List<String> args) {
  pkg.humanName.value = "Sass Migrator";
  pkg.botName.value = "Sass Bot";
  pkg.botEmail.value = "sass.bot.beep.boop@gmail.com";
  pkg.homebrewRepo.value = "sass/homebrew-sass";
  pkg.homebrewFormula.value = "Formula/migrator.rb";
  pkg.jsRequires.value = [
    pkg.JSRequire('fs'),
    pkg.JSRequire('os'),
    pkg.JSRequire('path')
  ];
  pkg.standaloneName.value = "sass-migrator";
  pkg.githubUser.fn = () => Platform.environment["GH_USER"]!;
  pkg.githubPassword.fn = () => Platform.environment["GH_TOKEN"]!;

  pkg.addAllTasks();
  grind(args);
}

@Task('Verify that the package is in a good state to release.')
sanityCheckBeforeRelease() {
  var ref = environment("GITHUB_REF");
  if (ref != "refs/tags/${pkg.version}") {
    fail("GITHUB_REF $ref is different than pubspec version ${pkg.version}.");
  }
  if (const ListEquality().equals(pkg.version.preRelease, ["dev"])) {
    fail("${pkg.version} is a dev release.");
  }

  var versionHeader =
      RegExp("^## ${RegExp.escape(pkg.version.toString())}\$", multiLine: true);
  if (!File("CHANGELOG.md").readAsStringSync().contains(versionHeader)) {
    fail("There's no CHANGELOG entry for ${pkg.version}.");
  }
}

/// Returns the environment variable named [name], or throws an exception if it
/// can't be found.
String environment(String name) {
  var value = Platform.environment[name];
  if (value == null) fail("Required environment variable $name not found.");
  return value;
}
