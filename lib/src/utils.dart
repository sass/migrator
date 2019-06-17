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
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/ast/node.dart';
import 'package:sass/src/importer/filesystem.dart';
export 'package:sass/src/utils.dart' show normalizedMap, normalizedSet;

import 'patch.dart';

/// A filesystem importer that loads Sass files relative to the current working
/// directory.
final _filesystemImporter = FilesystemImporter('.');

/// Returns the canonical version of [url].
Uri canonicalize(Uri url, {FileSpan context}) {
  var canonicalUrl = url == null ? null : _filesystemImporter.canonicalize(url);
  if (canonicalUrl == null) {
    emitWarning("Could not find Sass file at '${p.prettyUri(url)}'.",
        context: context);
  }
  return canonicalUrl;
}

/// Parses the file at [url] into a stylesheet.
Stylesheet parseStylesheet(Uri url, {FileSpan context}) {
  var canonicalUrl = canonicalize(url, context: context);
  if (canonicalUrl == null) return null;
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

/// Creates a patch deleting all of or part of [span].
///
/// By default, this deletes the entire span. If [start] and/or [end] are
/// provided, this deletes only the portion of the span within that range.
Patch patchDelete(FileSpan span, {int start = 0, int end}) {
  end ??= span.length;
  return Patch(
      span.file.span(span.start.offset + start, span.start.offset + end), "");
}

/// Emits a warning with [message] and optionally [context];
void emitWarning(String message, {FileSpan context}) {
  if (context == null) {
    print("WARNING - $message");
  } else {
    print(context.message("WARNING - $message"));
  }
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
