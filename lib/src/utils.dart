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

import 'migrators/module/forwarded.dart';
import 'patch.dart';

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
Patch patchDelete(FileSpan span, {int start = 0, int end}) =>
    Patch(subspan(span, start: start, end: end), "");

/// Returns a subsection of [span].
FileSpan subspan(FileSpan span, {int start = 0, int end}) => span.file
    .span(span.start.offset + start, span.start.offset + (end ?? span.length));

/// Returns a span containing the name of a member declaration or reference.
///
/// This does not include the namespace if present and does not include the
/// `$` at the start of variable names.
FileSpan nameSpan(SassNode node) {
  var span = node is Forwarded ? node.originalSpan : node.span;
  if (node is VariableDeclaration) {
    var start = node.namespace == null ? 1 : node.namespace.length + 2;
    return subspan(span, start: start, end: start + node.name.length);
  } else if (node is VariableExpression) {
    return subspan(span,
        start: node.namespace == null ? 1 : node.namespace.length + 2);
  } else if (node is FunctionRule) {
    var startName =
        span.text.replaceAll('_', '-').indexOf(node.name, '@function'.length);
    return subspan(span, start: startName, end: startName + node.name.length);
  } else if (node is FunctionExpression) {
    return node.name.span;
  } else if (node is MixinRule) {
    var startName = span.text
        .replaceAll('_', '-')
        .indexOf(node.name, span.text[0] == '=' ? 1 : '@mixin'.length);
    return subspan(span, start: startName, end: startName + node.name.length);
  } else if (node is IncludeRule) {
    var startName = span.text
        .replaceAll('_', '-')
        .indexOf(node.name, span.text[0] == '+' ? 1 : '@include'.length);
    return subspan(span, start: startName, end: startName + node.name.length);
  } else {
    throw UnsupportedError(
        "$node of type ${node.runtimeType} doesn't have a name");
  }
}

/// Emits a warning with [message] and optionally [context];
void emitWarning(String message, [FileSpan context]) {
  if (context == null) {
    print("WARNING - $message");
  } else {
    print(context.message("WARNING - $message"));
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
