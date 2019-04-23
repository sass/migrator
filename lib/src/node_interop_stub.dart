// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

/// A stub library that implements the subset of [`node_interop/node`][] that we
/// use, so that it can be imported on the Dart VM.
///
/// [`node_interop/node`]: https://pub.dartlang.org/documentation/node_interop/latest/node_interop.node/node_interop.node-library.html

class Process {
  List get argv => null;
}

final process = Process();
