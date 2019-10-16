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

/// Returns the default namespace for a use rule with [path].
String namespaceForPath(String path) {
  // TODO(jathak): Confirm that this is a valid Sass identifier
  return path.split('/').last.split('.').first;
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
Patch patchDelete(FileSpan span, {int start = 0, int end}) =>
    Patch(subspan(span, start: start, end: end), "");

/// Returns a subsection of [span].
FileSpan subspan(FileSpan span, {int start = 0, int end}) => span.file
    .span(span.start.offset + start, span.start.offset + (end ?? span.length));

/// Extends [span] so it encompasses any whitespace on either side of it.
FileSpan extendThroughWhitespace(FileSpan span) {
  var text = span.file.getText(0);

  var start = span.start.offset - 1;
  for (; start >= 0; start--) {
    if (!isWhitespace(text.codeUnitAt(start))) break;
  }

  var end = span.end.offset;
  for (; end < text.length; end++) {
    if (!isWhitespace(text.codeUnitAt(end))) break;
  }

  // Add 1 to start because it's guaranteed to end on either -1 or a character
  // that's not whitespace.
  return span.file.span(start + 1, end);
}

/// Extends [span] forward if it's followed by exactly [text].
///
/// If [span] is followed by anything other than [text], returns `null`.
FileSpan extendForward(FileSpan span, String text) {
  var end = span.end.offset;
  if (end + text.length > span.file.length) return null;
  if (span.file.getText(end, end + text.length) != text) return null;
  return span.file.span(span.start.offset, end + text.length);
}

/// Extends [span] backward if it's preceded by exactly [text].
///
/// If [span] is preceded by anything other than [text], returns `null`.
FileSpan extendBackward(FileSpan span, String text) {
  var start = span.start.offset;
  if (start - text.length < 0) return null;
  if (span.file.getText(start - text.length, start) != text) return null;
  return span.file.span(start - text.length, span.end.offset);
}

/// Returns true if [span] is preceded by exactly [text].
bool matchesBeforeSpan(FileSpan span, String text) {
  var start = span.start.offset;
  if (start - text.length < 0) return false;
  return span.file.getText(start - text.length, start) == text;
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
    var start = node.namespace == null ? 1 : node.namespace.length + 2;
    return subspan(node.span, start: start, end: start + node.name.length);
  } else if (node is VariableExpression) {
    return subspan(node.span,
        start: node.namespace == null ? 1 : node.namespace.length + 2);
  } else if (node is FunctionRule) {
    var startName = node.span.text
        .replaceAll('_', '-')
        .indexOf(node.name, '@function'.length);
    return subspan(node.span,
        start: startName, end: startName + node.name.length);
  } else if (node is FunctionExpression) {
    return node.name.span;
  } else if (node is MixinRule) {
    var startName = node.span.text
        .replaceAll('_', '-')
        .indexOf(node.name, node.span.text[0] == '=' ? 1 : '@mixin'.length);
    return subspan(node.span,
        start: startName, end: startName + node.name.length);
  } else if (node is IncludeRule) {
    var startName = node.span.text
        .replaceAll('_', '-')
        .indexOf(node.name, node.span.text[0] == '+' ? 1 : '@include'.length);
    return subspan(node.span,
        start: startName, end: startName + node.name.length);
  } else {
    throw UnsupportedError(
        "$node of type ${node.runtimeType} doesn't have a name");
  }
}

/// Emits a warning with [message] and optionally [context];
void emitWarning(String message, [FileSpan context]) {
  if (context == null) {
    printStderr("WARNING: $message");
  } else {
    printStderr("WARNING on ${context.message(message)}");
  }
}

/// Returns the only argument in [invocation], or null if [invocation] does not
/// contain exactly one argument.
Expression getOnlyArgument(ArgumentInvocation invocation) {
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
FileSpan getStaticNameForGetFunctionCall(FunctionExpression node) {
  if (node.name.asPlain != 'get-function') return null;
  var nameArgument =
      node.arguments.named['name'] ?? node.arguments.positional.first;
  if (nameArgument is! StringExpression ||
      (nameArgument as StringExpression).text.asPlain == null) {
    return null;
  }
  return (nameArgument as StringExpression).hasQuotes
      ? subspan(nameArgument.span, start: 1, end: nameArgument.span.length - 1)
      : nameArgument.span;
}

/// If [node] is a `get-function` call whose module argument can be statically
/// determined, this returns the span containing it.
///
/// Otherwise, this returns null.
FileSpan getStaticModuleForGetFunctionCall(FunctionExpression node) {
  if (node.name.asPlain != 'get-function') return null;
  var moduleArg = node.arguments.named['module'];
  if (moduleArg == null && node.arguments.positional.length > 2) {
    moduleArg = node.arguments.positional[2];
  }
  if (moduleArg is! StringExpression ||
      (moduleArg as StringExpression).text.asPlain == null) {
    return null;
  }
  return (moduleArg as StringExpression).hasQuotes
      ? subspan(moduleArg.span, start: 1, end: moduleArg.span.length - 2)
      : moduleArg.span;
}

/// Returns the import-only URL that corresponds to a regular canonical [url].
Uri getImportOnlyUrl(Uri url) {
  var filename = url.pathSegments.last;
  var extension = filename.split('.').last;
  var basename = filename.substring(0, filename.length - extension.length - 1);
  return url.resolve('$basename.import.$extension');
}

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
