// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrate_to_modules/src/migrator.dart';
import 'package:test/test.dart';

class TestMigrator extends Migrator {
  final testFiles = {
    "one.scss": r"""@import "two";
span {
  color: $a;
  background: $b;
  height: $c;
}
""",
    "two.scss": r"""@import "three";
$a: green;
a {
  background: $b;
}
""",
    "three.scss": r"""$b: blue;
$c: 5px !default;
b {
  width: 0;
}
""",
    "four.scss": r"""$c: 4px;
@import "three";
"""
  };
  final expectedMigrations = {
    "one.scss": r"""@use "three";
@use "two";
span {
  color: $two.a;
  background: $three.b;
  height: $three.c;
}
""",
    "two.scss": r"""@use "three";
$a: green;
a {
  background: $three.b;
}
""",
    "three.scss": null,
    "four.scss": r"""$c: 4px;
@use "three" with (
  $c: 4px
);
"""
  };
  @override
  String loadFile(Path path) => testFiles[path.path];

  @override
  Path resolvePath(String rawPath) => Path(rawPath);

  final List<String> logged = [];

  @override
  void log(String text) => logged.add(text);
}

void main() {
  test("file that needs no migrations", () {
    var migrator = TestMigrator();
    var migrated = migrator.runMigration("three.scss");
    expect(migrated, isEmpty);
    expect(migrator.logged, equals(["Nothing to migrate in three.scss"]));
  });
  test("single import and variable use", () {
    var migrator = TestMigrator();
    var migrated = migrator.runMigration("two.scss");
    expect(migrated, hasLength(1));
    expect(migrated, contains("two.scss"));
    expect(migrated["two.scss"], migrator.expectedMigrations["two.scss"]);
    expect(
        migrator.logged,
        equals([
          "Nothing to migrate in three.scss",
          "Successfully migrated two.scss"
        ]));
  });
  test("variable used without explicit import", () {
    var migrator = TestMigrator();
    var migrated = migrator.runMigration("one.scss");
    expect(migrated, hasLength(2));
    expect(migrated, contains("one.scss"));
    expect(migrated, contains("two.scss"));
    expect(migrated["one.scss"], migrator.expectedMigrations["one.scss"]);
    expect(migrated["two.scss"], migrator.expectedMigrations["two.scss"]);
    expect(
        migrator.logged,
        equals([
          "Nothing to migrate in three.scss",
          "Successfully migrated two.scss",
          "Successfully migrated one.scss"
        ]));
  });

  test("overriden variable becomes configured @use", () {
    var migrator = TestMigrator();
    var migrated = migrator.runMigration("four.scss");
    expect(migrated, hasLength(1));
    expect(migrated, contains("four.scss"));
    expect(migrated["four.scss"], migrator.expectedMigrations["four.scss"]);
    expect(
        migrator.logged,
        equals([
          "Nothing to migrate in three.scss",
          "Successfully migrated four.scss"
        ]));
  });
}
