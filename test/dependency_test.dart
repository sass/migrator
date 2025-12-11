// Copyright 2025 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:path/path.dart' as p;

void main() {
  test("declares a compatible dependency for sass_api", () {
    var migratorPubspec = Pubspec.parse(File("pubspec.yaml").readAsStringSync(),
        sourceUrl: p.toUri("pubspec.yaml"));
    var sassApiPubspecPath = p.normalize(p.join(
        p.fromUri(
            Isolate.resolvePackageUriSync(Uri.parse("package:sass_api/."))),
        "../pubspec.yaml"));
    var sassApiPubspec = Pubspec.parse(
        File(sassApiPubspecPath).readAsStringSync(),
        sourceUrl: p.toUri(sassApiPubspecPath));

    switch (migratorPubspec.dependencies["sass_api"]) {
      case HostedDependency dep:
        if (!dep.version.allows(sassApiPubspec.version!)) {
          fail("sass_api dependency $dep doesn't include actual sass_api "
              "version ${sassApiPubspec.version!}");
        }

      case var dep?:
        fail("Expected a hosted dependency on sass_api, was $dep");

      case null:
        fail("This package doesn't seem to have a dependency on sass_api");
    }
  });
}
