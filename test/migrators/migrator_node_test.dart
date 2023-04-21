// Copyright 2022 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

@Tags(["node"])

import 'package:sass_migrator/test/utils.dart';
import 'package:test/test.dart';

import 'migrator_dart_test.dart' as dart;

main() {
  runNodeTests = true;
  dart.main();
}
