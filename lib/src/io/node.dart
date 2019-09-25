// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:js/js.dart';
import 'package:node_interop/node.dart';

// Node seems to support ANSI escapes on all terminals.
//
// TODO(nweiz): Use `node_interop` for this when pulyaevskiy/node-interop#69 is
// fixed.
@JS('process.stdout.isTTY')
external bool get supportsAnsiEscapes;

void printStderr(Object message) => process.stderr.write("$message\n");
