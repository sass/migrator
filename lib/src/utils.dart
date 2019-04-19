// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:source_span/source_span.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/ast/node.dart';
import 'package:sass/src/importer/filesystem.dart';
export 'package:sass/src/utils.dart' show normalizedMap, normalizedSet;

import 'patch.dart';

/// A filesystem importer that loads Sass files relative to the current working
/// directory.
final _filesystemImporter = FilesystemImporter('.');

/// Returns the canonical version of [url].
Uri canonicalize(Uri url) => _filesystemImporter.canonicalize(url);

/// Parses the file at [url] into a stylesheet.
Stylesheet parseStylesheet(Uri url) {
  var canonicalUrl = _filesystemImporter.canonicalize(url);
  var result = _filesystemImporter.load(canonicalUrl);
  return Stylesheet.parse(result.contents, result.syntax, url: canonicalUrl);
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

/// An exception thrown by a migrator.
class MigrationException {
  final String message;

  /// The span that triggered this exception, or null if there is none.
  final FileSpan span;

  MigrationException(this.message, {this.span});

  String toString() {
    if (span != null) {
      return span.message(message);
    } else {
      return message;
    }
  }
}
