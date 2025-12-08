// Copyright 2022 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import '../utils.dart';

main() {
  testMigrator("calc_interpolation");
  testMigrator("color");
  testMigrator("division");
  testMigrator("module");
  testMigrator("namespace");
  testMigrator("strict_unary");
  testMigrator("if_function");
}
