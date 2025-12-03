// Copyright 2025 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../utils.dart';

/// Migrates the legacy `if()` function to the CSS syntax.
class IfMigrator extends Migrator {
  final name = "if-function";
  final description = "Migrates the legacy if() to CSS syntax.";

  @override
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var visitor = _IfMigrationVisitor(importCache,
        migrateDependencies: migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

/// The parameter list for `if()`.
final _parameters =
    ParameterList.parse(r"@rule if($condition, $if-true, $if-false) {");

/// A definition of an SCSS polyfill for the legacy `if()` function.
final _scssPolyfill = r"""
/// A polyfill for the legacy Sass `if()` function, for cases that couldn't be
/// directly migrated to CSS if().
@function -if($condition, $if-true, $if-false) {
  @return if(sass($condition): $if-true; else: $if-false);
}""";

/// A definition of an indented syntax polyfill for the legacy `if()` function.
final _sassPolyfill = r"""
/// A polyfill for the legacy Sass `if()` function, for cases that couldn't be
/// directly migrated to CSS if().
@function -if($condition, $if-true, $if-false)
  @return if(sass($condition): $if-true; else: $if-false)""";

/// A regular expression matching a sequence characters followed by a semicolon.
final _semicolonRegExp = RegExp(r".*?;");

class _IfMigrationVisitor extends MigrationVisitor {
  /// Whether to add an `@function -if()` definition to the root of the
  /// stylesheet to polyfill rest arguments.
  var _addPolyfill = false;

  _IfMigrationVisitor(super.importCache, {required super.migrateDependencies});

  @override
  void beforePatch(Stylesheet node) {
    if (!_addPolyfill) return;
    AstNode? nodeBefore;
    for (var node in node.children) {
      if (node is UseRule ||
          node is ForwardRule ||
          node is LoudComment ||
          node is SilentComment) {
        nodeBefore = node;
      } else if (node is! VariableDeclaration) {
        break;
      }
    }

    switch (nodeBefore) {
      case LoudComment(:var span) || SilentComment(:var span):
        addPatch(Patch.insert(span.end,
            '\n' + (isIndented ? _sassPolyfill : _scssPolyfill) + '\n'));

      case AstNode(:var span):
        addPatch(Patch.insert(span.extendIfMatches(_semicolonRegExp).end,
            '\n\n' + (isIndented ? _sassPolyfill : _scssPolyfill)));

      case _:
        addPatch(Patch.insert(node.span.start,
            (isIndented ? _sassPolyfill : _scssPolyfill) + '\n\n'));
    }
  }

  @override
  void visitLegacyIfExpression(LegacyIfExpression node) {
    switch (getArguments(_parameters, node.arguments)) {
      case GetArgumentsNotResolvable():
      case GetArgumentsArguments(inOrder: false):
        _addPolyfill = true;
        addPatch(patchBefore(node, '-'));

      case GetArgumentsInvalidCall(:var span, :var description):
        warn(span.message("invalid if(): $description"));

      case GetArgumentsArguments(:var arguments):
        arguments[0].patchOutName().andThen(addPatch);
        addPatch(patchBefore(arguments[0].argument, 'sass('));
        addPatch(
            patchBetween(arguments[0].argument, arguments[1].argument, '): '));

        if (arguments[1].argument case NullExpression()) {
          addPatch(Patch(node.span.after(arguments[1].span), ')'));
        } else {
          addPatch(patchReplaceFirst(
              arguments[1].span.between(arguments[2].span), ',', ';')!);
          arguments[2].patchOutName().andThen(addPatch);
          addPatch(patchBefore(arguments[2].argument, 'else: '));
        }
    }

    super.visitLegacyIfExpression(node);
  }
}
