// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/syntax.dart';
import 'package:sass/src/visitor/recursive_statement.dart';
import 'package:sass/src/visitor/interface/expression.dart';

import 'package:path/path.dart' as p;

import 'migrator.dart';
import 'patch.dart';
import 'utils.dart';

/// This base migrator parses the stylesheet at each provided entrypoint and
/// recursively visits every statement and expression it contains.
///
/// Migrators based on this should add appropriate patches to [patches] in
/// overridden methods.
///
/// On its own, this migrator only touches the entrypoints that are directly
/// provided to it; it does not migrate dependencies.
abstract class MigratorBase extends RecursiveStatementVisitor
    with Migrator, ExpressionVisitor {
  List<Patch> _patches = [];

  /// The patches to be applied to the stylesheet being migrated.
  ///
  /// Subclasses that override this should also override [migrateFile].
  List<Patch> get patches => _patches;

  /// Runs this migrator on [entrypoint].
  ///
  /// This will return either a map containing only the migrated contents of
  /// [entrypoint], or an empty map if no migration was necessary.
  p.PathMap<String> migrateFile(String entrypoint) {
    _patches = [];
    var path = canonicalizePath(p.join(Directory.current.path, entrypoint));
    var contents = File(path).readAsStringSync();
    var syntax = Syntax.forPath(path);
    visitStylesheet(Stylesheet.parse(contents, syntax, url: path));

    var results = p.PathMap<String>();
    if (_patches.isNotEmpty) {
      results[path] = Patch.applyAll(_patches.first.selection.file, _patches);
    }
    _patches = null;
    return results;
  }

  // Expression Tree Traversal

  @override
  visitExpression(Expression expression) => expression.accept(this);

  visitBinaryOperationExpression(BinaryOperationExpression node) {
    node.left.accept(this);
    node.right.accept(this);
  }

  visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    visitArgumentInvocation(node.arguments);
  }

  visitIfExpression(IfExpression node) {
    visitArgumentInvocation(node.arguments);
  }

  visitListExpression(ListExpression node) {
    for (var item in node.contents) {
      item.accept(this);
    }
  }

  visitMapExpression(MapExpression node) {
    for (var pair in node.pairs) {
      pair.item1.accept(this);
      pair.item2.accept(this);
    }
  }

  visitParenthesizedExpression(ParenthesizedExpression node) {
    node.expression.accept(this);
  }

  visitStringExpression(StringExpression node) {
    visitInterpolation(node.text);
  }

  visitUnaryOperationExpression(UnaryOperationExpression node) {
    node.operand.accept(this);
  }

  // Expression Leaves

  visitBooleanExpression(BooleanExpression node) {}
  visitColorExpression(ColorExpression node) {}
  visitNullExpression(NullExpression node) {}
  visitNumberExpression(NumberExpression node) {}
  visitSelectorExpression(SelectorExpression node) {}
  visitValueExpression(ValueExpression node) {}
  visitVariableExpression(VariableExpression node) {}
  visitUseRule(UseRule node) {}
}
