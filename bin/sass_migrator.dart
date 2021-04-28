// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/src/node_interop_stub.dart'
    if (dart.library.js) 'package:node_interop/node.dart';

import 'package:sass_migrator/src/runner.dart';

// We can't declare args as a List<String> or Iterable<String> beacause of
// dart-lang/sdk#36627.
main(Iterable args) {
  var argv = process.argv;
  if (argv != null) args = argv.skip(2);
  MigratorRunner().execute(args.cast<String>());
}
