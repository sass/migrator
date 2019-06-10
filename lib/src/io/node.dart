// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:js/js.dart';

export 'package:node_io/node_io.dart';

// ignore: missing_js_lib_annotation
@JS("process.stderr.write")
external _writeToStderr(String text);

class Stderr {
  void write(object) => _writeToStderr(object.toString());
  void writeln([object]) => _writeToStderr("${object ?? ''}\n");
}

final stderr = Stderr();
