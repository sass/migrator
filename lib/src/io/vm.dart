// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';

/// Whether this process is connected to a terminal that supports ANSI escape
/// sequences.
bool get supportsAnsiEscapes {
  if (!stdout.hasTerminal) return false;

  // We don't trust [stdout.supportsAnsiEscapes] except on Windows because it
  // relies on the TERM environment variable which has many false negatives.
  if (!Platform.isWindows) return true;
  return stdout.supportsAnsiEscapes;
}

/// Prints [message] to standard error, followed by a newline.
void printStderr(Object message) => stderr.writeln(message);

/// The local filesystem.
FileSystem get fileSystem => const LocalFileSystem();
