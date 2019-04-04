// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/node.dart';
import 'package:sass/src/importer/utils.dart' show resolveImportPath;
export 'package:sass/src/utils.dart' show normalizedMap, normalizedSet;

import 'patch.dart';

/// Returns the canonical version of [path].
String canonicalizePath(String path) {
  return p.canonicalize(resolveImportPath(path));
}

/// Returns the default namespace for a use rule with [path].
String namespaceForPath(String path) {
  // TODO(jathak): Confirm that this is a valid Sass identifier
  return path.split('/').last.split('.').first;
}

/// Creates a patch that adds [text] immediately before [node].
Patch patchBefore(AstNode node, String text) {
  var start = node.span.start;
  return Patch(start.file.span(start.offset, start.offset), text);
}

/// Creates a patch that adds [text] immediately after [node].
Patch patchAfter(AstNode node, String text) {
  var end = node.span.end;
  return Patch(end.file.span(end.offset, end.offset), text);
}

/// Emits a warning with [message] and [context];
void warn(String message, FileSpan context) {
  print(context.message("WARNING - $message"));
}

class MigrationException {
  final String message;
  final FileSpan context;

  MigrationException(this.message, {this.context});

  toString() {
    if (context != null) {
      return context.message(message);
    } else {
      return message;
    }
  }
}
