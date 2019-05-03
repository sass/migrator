// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charcode/charcode.dart';
import 'package:grinder/grinder.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:string_scanner/string_scanner.dart';

import 'standalone.dart';
import 'utils.dart';

@Task('Release the current version as to GitHub.')
@Depends(package)
githubRelease() async {
  var authorization = _githubAuthorization();

  var client = http.Client();
  var response = await client.post(
      "https://api.github.com/repos/sass/migrator/releases",
      headers: {
        "content-type": "application/json",
        "authorization": authorization
      },
      body: jsonEncode({
        "tag_name": version,
        "name": "Sass Migrator $version",
        "prerelease": Version.parse(version).isPreRelease,
        "body": _releaseMessage()
      }));

  if (response.statusCode != 201) {
    fail("${response.statusCode} error creating release:\n${response.body}");
  } else {
    log("Released Sass Migrator $version to GitHub.");
  }

  var uploadUrl = json
      .decode(response.body)["upload_url"]
      // Remove the URL template.
      .replaceFirst(RegExp(r"\{[^}]+\}$"), "");

  await Future.wait(["linux", "macos", "windows"].expand((os) {
    return ["ia32", "x64"].map((architecture) async {
      var format = os == "windows" ? "zip" : "tar.gz";
      var package = "sass-migrator-$version-$os-$architecture.$format";
      var response = await http.post("$uploadUrl?name=$package",
          headers: {
            "content-type":
                os == "windows" ? "application/zip" : "application/gzip",
            "authorization": authorization
          },
          body: File(p.join("build", package)).readAsBytesSync());

      if (response.statusCode != 201) {
        fail("${response.statusCode} error uploading $package:\n"
            "${response.body}");
      } else {
        log("Uploaded $package.");
      }
    });
  }));

  client.close();
}

/// Returns the Markdown-formatted message to use for a GitHub release.
String _releaseMessage() {
  var changelogUrl =
      "https://github.com/sass/migrator/blob/master/CHANGELOG.md#" +
          version.replaceAll(".", "");
  var installUrl =
      "https:/github.com/sass/migrator/blob/master/README.md#install";
  return "To install Sass Migrator $version, download one of the packages above "
      "and [add it to your PATH](https://katiek2.github.io/path-doc/), or see "
      "[the README]($installUrl) for full installation instructions.\n\n"
      "## Changes\n\n" +
      _lastChangelogSection() +
      "\n\n"
      "See the [full changelog]($changelogUrl) for changes in earlier "
      "releases.";
}

/// A regular expression that matches a Markdown code block.
final _codeBlock = RegExp(" *```");

/// Returns the most recent section in the CHANGELOG, reformatted to remove line
/// breaks that will show up on GitHub.
String _lastChangelogSection() {
  var scanner = StringScanner(File("CHANGELOG.md").readAsStringSync(),
      sourceUrl: "CHANGELOG.md");

  // Scans the remainder of the current line and returns it. This consumes the
  // trailing newline but doesn't return it.
  String scanLine() {
    var start = scanner.position;
    while (scanner.readChar() != $lf) {}
    return scanner.substring(start, scanner.position - 1);
  }

  scanner.expect("## $version\n");

  var buffer = StringBuffer();
  while (!scanner.isDone && !scanner.matches("## ")) {
    if (scanner.matches(_codeBlock)) {
      do {
        buffer.writeln(scanLine());
      } while (!scanner.matches(_codeBlock));
      buffer.writeln(scanLine());
    } else if (scanner.matches(RegExp(" *\n"))) {
      buffer.writeln();
      buffer.writeln(scanLine());
    } else if (scanner.matches(RegExp(r" *([*-]|\d+\.)"))) {
      buffer.write(scanLine());
      buffer.writeCharCode($space);
    } else {
      buffer.write(scanLine());
      buffer.writeCharCode($space);
    }
  }

  return buffer.toString().trim();
}

/// Returns the HTTP basic authentication Authorization header from the
/// environment.
String _githubAuthorization() {
  var username = environment("GITHUB_USER");
  var token = environment("GITHUB_AUTH");
  return "Basic ${base64.encode(utf8.encode("$username:$token"))}";
}
