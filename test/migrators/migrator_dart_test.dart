// Copyright 2022 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/test/utils.dart';

main() {
  testMigrator("division");
  testMigrator("media_logic");
  testMigrator("module");
  testMigrator("namespace");
  testMigrator("strict_unary");
}
