// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

@Tags(["node"])

import 'package:sass_migrator/test/utils.dart';
import 'package:test/test.dart';

import 'cli_dart_test.dart' as dart;

void main() {
  runNodeTests = true;
  dart.main();
}
