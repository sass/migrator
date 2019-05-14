// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:meta/meta.dart';
import 'package:node_preamble/preamble.dart' as preamble;

import 'utils.dart';

@Task('Compile to JS in dev mode.')
js() => _js(release: false);

@Task('Compile to JS in release mode.')
jsRelease() => _js(release: true);

/// Compiles Sass to JS.
///
/// If [release] is `true`, this compiles minified with
/// --trust-type-annotations. Otherwise, it compiles unminified with pessimistic
/// type checks.
void _js({@required bool release}) {
  ensureBuild();
  var destination = File('build/sass_migrator.dart.js');

  var args = [
    '--server-mode',
    '-Dnode=true',
    '-Dversion=$version',
    '-Ddart-version=$dartVersion',
  ];
  if (release) {
    // We use O4 because:
    //
    // * We don't care about the string representation of types.
    // * We expect our test coverage to ensure that nothing throws subtypes of
    //   Error.
    // * We thoroughly test edge cases in user input.
    args..add("-O4")..add("--fast-startup");
  }

  Dart2js.compile(File('bin/sass_migrator.dart'),
      outFile: destination, extraArgs: args);
  var text = destination.readAsStringSync();

  if (release) {
    // We don't ship the source map, so remove the source map comment.
    text =
        text.replaceFirst(RegExp(r"\n*//# sourceMappingURL=[^\n]+\n*$"), "\n");
  }

  destination.writeAsStringSync(
      "#!/usr/bin/env node\n" + preamble.getPreamble(minified: release) + text);
}

@Task('Build a pure-JS dev-mode npm package.')
@Depends(js)
npmPackage() => _npm(release: false);

@Task('Build a pure-JS release-mode npm package.')
@Depends(jsRelease)
npmReleasePackage() => _npm(release: true);

/// Builds a pure-JS npm package.
///
/// If [release] is `true`, this compiles minified with `-O4`. Otherwise, it
/// compiles unminified with no extra optimization.
void _npm({@required bool release}) {
  var json = jsonDecode(File('package/package.json').readAsStringSync())
      as Map<String, dynamic>;
  json['version'] = version;

  var dir = Directory('build/npm');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  log("copying package/package.json to build/npm");
  File('build/npm/package.json').writeAsStringSync(jsonEncode(json));

  copy(File('build/sass_migrator.dart.js'), dir);
  copy(File('README.md'), dir);
}
