// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// These libraries don't expose *exactly* the same API, but they overlap in all
// the cases we care about.
export 'dart:io' if (dart.library.js) 'package:node_io/node_io.dart';

// For cases that aren't covered by `node_io`.
export 'io/vm.dart' if (dart.library.js) 'io/node.dart';
