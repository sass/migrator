// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:charcode/charcode.dart';
import 'package:sass_api/sass_api.dart';
import 'package:source_span/source_span.dart';

import 'io.dart';
import 'patch.dart';
import 'util/span.dart';

export 'util/span.dart';
export 'util/get_arguments.dart';

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

/// Creates a patch that replaces any existing syntax between [before] and
/// [after] with [text].
Patch patchBetween(AstNode before, AstNode after, String text) =>
    Patch(before.span.between(after.span), text);

/// Replaces the first match of [from] in [span]'s text with [to].
///
/// Returns `null` if [from] has no matches within [span]'s text.
Patch? patchReplaceFirst(FileSpan span, Pattern from, String to) => from
    .allMatches(span.text)
    .firstOrNull
    ?.andThen((match) => Patch(span.subspan(match.start, match.end), to));

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

/// Like [SassDeclaration.nameSpan] or [SassReference.nameSpan], but removes the
/// `$` from variable spans.
FileSpan nameSpan(SassNode node) {
  var span = node is SassDeclaration
      ? node.nameSpan
      : node is SassReference
          ? node.nameSpan
          : (throw UnsupportedError(
              "$node of type ${node.runtimeType} doesn't have a nameSpan"));
  return node is VariableDeclaration || node is VariableExpression
      ? span.subspan(1)
      : span;
}

/// Emits a warning with [message] and optionally [context];
void emitWarning(String message, [FileSpan? context]) {
  if (context == null) {
    printStderr("WARNING: $message");
  } else {
    printStderr("WARNING on ${context.message(message)}");
  }
}

/// Returns the only argument in [arguments], or null if [arguments] does not
/// contain exactly one argument.
Expression? getOnlyArgument(ArgumentList arguments) {
  if (arguments.positional.length == 0 && arguments.named.length == 1) {
    return arguments.named.values.first;
  } else if (arguments.positional.length == 1 && arguments.named.isEmpty) {
    return arguments.positional.first;
  } else {
    return null;
  }
}

/// If [node] is a `get-function` call whose name argument can be statically
/// determined, this returns the span containing it.
///
/// Otherwise, this returns null.
FileSpan? getStaticNameForGetFunctionCall(FunctionExpression node) {
  if (node.name != 'get-function') return null;
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
  if (node.name != 'get-function') return null;
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
(List<F>, List<G>) partitionOnType<E, F extends E, G extends E>(
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

  return (fs, gs);
}
