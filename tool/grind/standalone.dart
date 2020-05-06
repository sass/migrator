// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:grinder/grinder.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

import 'utils.dart';

/// Whether we're using a 64-bit Dart SDK.
bool get _is64Bit => Platform.version.contains("x64");

@Task('Build Dart script snapshot.')
snapshot() {
  ensureBuild();
  Dart.run('bin/sass_migrator.dart',
      vmArgs: ['--snapshot=build/sass_migrator.dart.snapshot']);
}

@Task('Build a dev-mode Dart application snapshot.')
appSnapshot() => _appSnapshot(release: false);

@Task('Build a release-mode Dart application snapshot.')
releaseAppSnapshot() => _appSnapshot(release: true);

/// Compiles the Sass Migrator to an application snapshot.
///
/// If [release] is `false`, this compiles with asserts enabled.
void _appSnapshot({@required bool release}) {
  var args = [
    '--snapshot=build/sass_migrator.dart.app.snapshot',
    '--snapshot-kind=app-jit'
  ];

  if (!release) args.add('--enable-asserts');

  ensureBuild();
  Dart.run('bin/sass_migrator.dart',
      arguments: ['--help'], vmArgs: args, quiet: true);
}

@Task('Build standalone packages for all OSes.')
@Depends(snapshot, releaseAppSnapshot)
package() async {
  var client = http.Client();
  await Future.wait(["linux", "macos", "windows"].expand((os) => [
        _buildPackage(client, os, x64: true),
        if (os != "macos") _buildPackage(client, os, x64: false)
      ]));
  client.close();
}

/// Builds a standalone Sass Migrator package for the given [os] and
/// architecture.
///
/// The [client] is used to download the corresponding Dart SDK.
Future _buildPackage(http.Client client, String os, {bool x64 = true}) async {
  var architecture = x64 ? "x64" : "ia32";

  // TODO: Compile a single executable that embeds the Dart VM and the snapshot
  // when dart-lang/sdk#27596 is fixed.
  var channel = isDevSdk ? "dev" : "stable";
  var url = "https://storage.googleapis.com/dart-archive/channels/$channel/"
      "release/$dartVersion/sdk/dartsdk-$os-$architecture-release.zip";
  log("Downloading $url...");
  var response = await client.get(Uri.parse(url));
  if (response.statusCode ~/ 100 != 2) {
    throw "Failed to download package: ${response.statusCode} "
        "${response.reasonPhrase}.";
  }

  var dartExecutable = ZipDecoder().decodeBytes(response.bodyBytes).firstWhere(
      (file) => os == 'windows'
          ? file.name.endsWith("/bin/dart.exe")
          : file.name.endsWith("/bin/dart"));
  var executable = dartExecutable.content as List<int>;

  // Use the app snapshot when packaging for the current operating system.
  //
  // TODO: Use an app snapshot everywhere when dart-lang/sdk#28617 is fixed.
  var snapshot = os == Platform.operatingSystem && x64 == _is64Bit
      ? "build/sass_migrator.dart.app.snapshot"
      : "build/sass_migrator.dart.snapshot";

  var archive = Archive()
    ..addFile(fileFromBytes(
        "sass-migrator/src/dart${os == 'windows' ? '.exe' : ''}", executable,
        executable: true))
    ..addFile(
        file("sass-migrator/src/DART_LICENSE", p.join(sdkDir.path, 'LICENSE')))
    ..addFile(file("sass-migrator/src/sass_migrator.dart.snapshot", snapshot))
    ..addFile(file("sass-migrator/src/SASS_MIGRATOR_LICENSE", "LICENSE"))
    ..addFile(fileFromString(
        "sass-migrator/sass-migrator${os == 'windows' ? '.bat' : ''}",
        readAndReplaceVersion(
            "package/sass-migrator.${os == 'windows' ? 'bat' : 'sh'}"),
        executable: true));

  var prefix = 'build/sass-migrator-$version-$os-$architecture';
  if (os == 'windows') {
    var output = "$prefix.zip";
    log("Creating $output...");
    File(output).writeAsBytesSync(ZipEncoder().encode(archive));
  } else {
    var output = "$prefix.tar.gz";
    log("Creating $output...");
    File(output)
        .writeAsBytesSync(GZipEncoder().encode(TarEncoder().encode(archive)));
  }
}
