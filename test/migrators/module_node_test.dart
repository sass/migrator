// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

@Tags(["node"])

import 'package:test/test.dart';

import '../migrator_utils.dart';

main() {
  testMigrator("module", node: true);
}
