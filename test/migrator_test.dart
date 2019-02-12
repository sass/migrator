// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:sass_module_migrator/src/migrator.dart';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  testHrx("variables");
  testHrx("subdirectories");
  testHrx("functions");
  testHrx("mixins");
}

class HrxTestFiles {
  String hrxName;
  Map<String, String> input = {};
  Map<String, String> output = {};

  HrxTestFiles(this.hrxName) {
    var hrxText = File("test/migrations/$hrxName.hrx").readAsStringSync();
    // TODO(jathak): Replace this with an actual HRX parser.
    String filename;
    String contents;
    for (String line in hrxText.substring(0, hrxText.length - 1).split("\n")) {
      if (line.startsWith("<==> ")) {
        if (filename != null) {
          _load(filename, contents.substring(0, contents.length - 1));
        }
        filename = line.substring(5).trim();
        contents = "";
      } else {
        contents += line + "\n";
      }
    }
    if (filename != null) _load(filename, contents);
  }

  void _load(String filename, String contents) {
    if (filename.startsWith("input/")) {
      input[filename.substring(6)] = contents;
    } else if (filename.startsWith("output/")) {
      output[filename.substring(6)] = contents;
    }
  }

  Future unpack() async {
    for (var file in input.keys) {
      var parts = p.split(file);
      d.Descriptor descriptor = d.file(parts.removeLast(), input[file]);
      while (parts.isNotEmpty) {
        descriptor = d.dir(parts.removeLast(), [descriptor]);
      }
      await descriptor.create();
    }
  }
}

testHrx(String hrxName) {
  var files = HrxTestFiles(hrxName);
  group(hrxName, () {
    for (var file in files.input.keys) {
      test(file, () async {
        await files.unpack();
        var path = p.join(d.sandbox, file);
        var migrated = migrateFiles([path]);
        expect(migrated[path], equals(files.output[file]));
      });
    }
  });
}
