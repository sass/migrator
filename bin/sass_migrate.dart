// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:args/args.dart';
import 'package:meta/meta.dart';

import 'package:sass_migrate/src/migrator.dart';

void main(List<String> args) {
  var files = {
    "a.scss": """
@import 'b';
span { color: 0; }
    """,
    "b.scss": """
a { color: 1; }
    """,
  };
  var migrator = Migrator();
  migrator.loader = (path) => files[path];
  migrator.pathResolver = (rawPath) => rawPath;
  migrator.migrate("a.scss");
  print(migrator.migrated['a.scss']);
  print("----");
  print(migrator.migrated['b.scss']);
}
