// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:charcode/charcode.dart';
import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/ast/node.dart';

import 'io.dart';
import 'patch.dart';

extension ExtendSpan on FileSpan {
  /// Extends this span so it encompasses any whitespace on either side of it.
  FileSpan extendThroughWhitespace() {
    var text = file.getText(0);

    var newStart = start.offset - 1;
    for (; newStart >= 0; newStart--) {
      if (!isWhitespace(text.codeUnitAt(newStart))) break;
    }

    var newEnd = end.offset;
    for (; newEnd < text.length; newEnd++) {
      if (!isWhitespace(text.codeUnitAt(newEnd))) break;
    }

    // Add 1 to start because it's guaranteed to end on either -1 or a character
    // that's not whitespace.
    return file.span(newStart + 1, newEnd);
  }

  /// Extends this span forward if it's followed by exactly [pattern].
  ///
  /// If it doesn't match, returns the span as-is.
  FileSpan extendIfMatches(Pattern pattern) {
    var text = file.getText(end.offset);
    var match = pattern.matchAsPrefix(text);
    if (match == null) return this;
    return file.span(start.offset, end.offset + match.end);
  }

  /// Returns true if this span is preceded by exactly [text].
  bool matchesBefore(String text) {
    if (start.offset - text.length < 0) return false;
    return file.getText(start.offset - text.length, start.offset) == text;
  }
}

extension NullableExtension<T> on T? {
  /// If [this] is `null`, returns `null`. Otherwise, runs [fn] and returns its
  /// result.
  ///
  /// Based on Rust's `Option.and_then`.
  V? andThen<V>(V Function(T value) fn) {
    var self = this; // dart-lang/language#1520
    return self == null ? null : fn(self);
  }
}

/// Returns the default namespace for a use rule with [path].
String namespaceForPath(String path) {
  // TODO(jathak): Confirm that this is a valid Sass identifier
  var basename = path.split('/').last.split('.').first;
  return basename.startsWith('_') ? basename.substring(1) : basename;
}

/// Creates a patch that adds [text] immediately before [node].
Patch patchBefore(AstNode node, String text) =>
    Patch.insert(node.span.start, text);

/// Creates a patch that adds [text] immediately after [node].
Patch patchAfter(AstNode node, String text) =>
    Patch.insert(node.span.end, text);

/// Returns true if [map] does not contain any duplicate values.
bool valuesAreUnique(Map<Object, Object> map) =>
    map.values.toSet().length == map.length;

/// Creates a patch deleting all of or part of [span].
///
/// By default, this deletes the entire span. If [start] and/or [end] are
/// provided, this deletes only the portion of the span within that range.
Patch patchDelete(FileSpan span, {int start = 0, int? end}) =>
    Patch(span.subspan(start, end), "");

/// Returns the next location after [import] that it would be safe to insert
/// a `@use` or `@forward` rule.
///
/// This is generally the start of the next line, but may vary if there's any
/// non-whitespace, non-comment code on the same line.
FileLocation afterImport(ImportRule import, {bool shouldHaveSemicolon = true}) {
  var loc = import.span.end;
  var textAfter = loc.file.getText(loc.offset);
  var inLineComment = false;
  var inBlockComment = false;
  var i = 0;
  for (; i < textAfter.length; i++) {
    var char = textAfter.codeUnitAt(i);
    if (inBlockComment) {
      if (char == $asterisk && textAfter.codeUnitAt(i + 1) == $slash) {
        i++;
        inBlockComment = false;
      }
    } else if (char == $lf && !shouldHaveSemicolon) {
      i++;
      break;
    } else if (inLineComment) {
      continue;
    } else if (char == $slash) {
      var next = textAfter.codeUnitAt(i + 1);
      if (next == $slash) {
        inLineComment = true;
      } else if (next == $asterisk) {
        inBlockComment = true;
      } else {
        break;
      }
    } else if (shouldHaveSemicolon && char == $semicolon) {
      shouldHaveSemicolon = false;
    } else if (!isWhitespace(char)) {
      break;
    }
  }
  return loc.file.location(loc.offset + i);
}

/// Returns whether [character] is whitespace, according to Sass's definition.
bool isWhitespace(int character) =>
    character == $space ||
    character == $tab ||
    character == $lf ||
    character == $cr ||
    character == $ff;

/// Returns a span containing the name of a member declaration or reference.
///
/// This does not include the namespace if present and does not include the
/// `$` at the start of variable names.
FileSpan nameSpan(SassNode node) {
  if (node is VariableDeclaration) {
    var namespace = node.namespace;
    var start = namespace == null ? 1 : namespace.length + 2;
    return node.span.subspan(start, start + node.name.length);
  } else if (node is VariableExpression) {
    var namespace = node.namespace;
    return node.span.subspan(namespace == null ? 1 : namespace.length + 2);
  } else if (node is FunctionRule) {
    var startName = node.span.text
        .replaceAll('_', '-')
        .indexOf(node.name, '@function'.length);
    return node.span.subspan(startName, startName + node.name.length);
  } else if (node is FunctionExpression) {
    return node.name.span;
  } else if (node is MixinRule) {
    var startName = node.span.text
        .replaceAll('_', '-')
        .indexOf(node.name, node.span.text[0] == '=' ? 1 : '@mixin'.length);
    return node.span.subspan(startName, startName + node.name.length);
  } else if (node is IncludeRule) {
    var startName = node.span.text
        .replaceAll('_', '-')
        .indexOf(node.name, node.span.text[0] == '+' ? 1 : '@include'.length);
    return node.span.subspan(startName, startName + node.name.length);
  } else {
    throw UnsupportedError(
        "$node of type ${node.runtimeType} doesn't have a name");
  }
}

/// Emits a warning with [message] and optionally [context];
void emitWarning(String message, [FileSpan? context]) {
  if (context == null) {
    printStderr("WARNING: $message");
  } else {
    printStderr("WARNING on ${context.message(message)}");
  }
}

/// Returns the only argument in [invocation], or null if [invocation] does not
/// contain exactly one argument.
Expression? getOnlyArgument(ArgumentInvocation invocation) {
  if (invocation.positional.length == 0 && invocation.named.length == 1) {
    return invocation.named.values.first;
  } else if (invocation.positional.length == 1 && invocation.named.isEmpty) {
    return invocation.positional.first;
  } else {
    return null;
  }
}

/// If [node] is a `get-function` call whose name argument can be statically
/// determined, this returns the span containing it.
///
/// Otherwise, this returns null.
FileSpan? getStaticNameForGetFunctionCall(FunctionExpression node) {
  if (node.name.asPlain != 'get-function') return null;
  var nameArgument =
      node.arguments.named['name'] ?? node.arguments.positional.first;
  if (nameArgument is! StringExpression || nameArgument.text.asPlain == null) {
    return null;
  }
  return nameArgument.hasQuotes
      ? nameArgument.span.subspan(1, nameArgument.span.length - 1)
      : nameArgument.span;
}

/// If [node] is a `get-function` call whose module argument can be statically
/// determined, this returns the span containing it.
///
/// Otherwise, this returns null.
FileSpan? getStaticModuleForGetFunctionCall(FunctionExpression node) {
  if (node.name.asPlain != 'get-function') return null;
  var moduleArg = node.arguments.named['module'];
  if (moduleArg == null && node.arguments.positional.length > 2) {
    moduleArg = node.arguments.positional[2];
  }
  if (moduleArg is! StringExpression || moduleArg.text.asPlain == null) {
    return null;
  }
  return moduleArg.hasQuotes
      ? moduleArg.span.subspan(1, moduleArg.span.length - 2)
      : moduleArg.span;
}

/// Returns the import-only URL that corresponds to a regular canonical [url].
Uri getImportOnlyUrl(Uri url) {
  var filename = url.pathSegments.last;
  var extension = filename.split('.').last;
  var basename = filename.substring(0, filename.length - extension.length - 1);
  return url.resolve('$basename.import.$extension');
}

/// Returns true if [url] is an import-only file.
bool isImportOnlyFile(Uri url) =>
    url.path.endsWith('.import.scss') || url.path.endsWith('.import.sass');

/// Partitions [iterable] into two lists based on the types of its inputs.
///
/// This asserts that every element in [iterable] is either an `F` or a `G`, and
/// returns one list containing all the `F`s and one containing all the `G`s.
Tuple2<List<F>, List<G>> partitionOnType<E, F extends E, G extends E>(
    Iterable<E> iterable) {
  var fs = <F>[];
  var gs = <G>[];

  for (var element in iterable) {
    if (element is F) {
      fs.add(element);
    } else {
      gs.add(element as G);
    }
  }

  return Tuple2(fs, gs);
}
