// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/visitor/recursive_statement.dart';
import 'package:sass/src/visitor/interface/expression.dart';

import 'package:path/path.dart' as p;

import 'built_in_functions.dart';
import 'local_scope.dart';
import 'patch.dart';
import 'stylesheet_migration.dart';
import 'utils.dart';

/// Runs a migration of [entrypoints] and their dependencies without writing
/// any changes to disk.
p.PathMap<String> migrateFiles(List<String> entrypoints) =>
    _Migrator().migrate(entrypoints);

class _Migrator extends RecursiveStatementVisitor implements ExpressionVisitor {
  /// List of all migrations for files touched by this run.
  final _migrations = p.PathMap<StylesheetMigration>();

  /// List of migrations in progress. The last item is the current migration.
  final _activeMigrations = <StylesheetMigration>[];

  /// Current stylesheet being actively migrated.
  StylesheetMigration get _currentMigration =>
      _activeMigrations.isNotEmpty ? _activeMigrations.last : null;

  /// Runs the migrator on each item in [entrypoints] in turn and returns a
  /// map of migrated contents.
  p.PathMap<String> migrate(List<String> entrypoints) {
    for (var entrypoint in entrypoints) {
      _migrateStylesheet(entrypoint);
    }
    var results = p.PathMap<String>();
    for (var migration in _migrations.values) {
      results[migration.path] = migration.migratedContents;
    }
    return results;
  }

  /// Migrates the stylesheet at [path] if it hasn't already been migrated and
  /// returns the StylesheetMigration instance for it regardless.
  StylesheetMigration _migrateStylesheet(String path) {
    path = canonicalizePath(_currentMigration == null
        ? path
        : p.join(p.dirname(_currentMigration.path), path));
    return _migrations.putIfAbsent(path, () {
      var migration = StylesheetMigration(path);
      _activeMigrations.add(migration);
      visitStylesheet(migration.stylesheet);
      _activeMigrations.remove(migration);
      return migration;
    });
  }

  /// Visits the children of [node] with a local scope.
  ///
  /// Note: The children of a stylesheet are at the root, so we should not add
  /// a local scope.
  @override
  void visitChildren(ParentStatement node) {
    if (node is Stylesheet) {
      super.visitChildren(node);
      return;
    }
    _currentMigration.localScope = LocalScope(_currentMigration.localScope);
    super.visitChildren(node);
    _currentMigration.localScope = _currentMigration.localScope.parent;
  }

  /// Adds a namespace to any function call that require it.
  void visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    visitArgumentInvocation(node.arguments);

    if (node.name.asPlain == null) return;
    var name = node.name.asPlain;
    if (_currentMigration.localScope?.isLocalFunction(name) ?? false) return;

    var namespace = _currentMigration.functions.containsKey(name)
        ? _currentMigration.namespaceForNode(_currentMigration.functions[name])
        : null;

    if (namespace == null) {
      if (!builtInFunctionModules.containsKey(name)) return;

      namespace = builtInFunctionModules[name];
      name = builtInFunctionNameChanges[name] ?? name;
      _currentMigration.additionalUseRules.add("sass:$namespace");
    }
    _currentMigration.patches.add(Patch(node.name.span, "$namespace.$name"));
  }

  /// Declares the function within the current scope before visiting it.
  @override
  void visitFunctionRule(FunctionRule node) {
    _currentMigration.declareFunction(node);
    super.visitFunctionRule(node);
  }

  /// Migrates @import to @use after migrating the imported file.
  void visitImportRule(ImportRule node) {
    if (node.imports.first is StaticImport) {
      super.visitImportRule(node);
      return;
    }
    if (node.imports.length > 1) {
      throw UnimplementedError(
          "Migration of @import rule with multiple imports not supported.");
    }
    var import = node.imports.first as DynamicImport;

    if (_currentMigration.localScope != null) {
      // TODO(jathak): Handle nested imports
      return;
    }
    // TODO(jathak): Confirm that this import appears before other rules

    var importMigration = _migrateStylesheet(import.url);

    var overrides = [];
    for (var variable in importMigration.configurableVariables) {
      if (_currentMigration.variables.containsKey(variable)) {
        var declaration = _currentMigration.variables[variable];
        if (_currentMigration.namespaceForNode(declaration) == null) {
          overrides.add("\$${declaration.name}: ${declaration.expression}");
        }
        // TODO(jathak): Remove this declaration from the current stylesheet if
        //   it's not referenced before this point.
      }
    }
    var config = "";
    if (overrides.isNotEmpty) {
      config = " with (\n  " + overrides.join(',\n  ') + "\n)";
    }
    _currentMigration.patches
        .add(Patch(node.span, '@use ${import.span.text}$config'));
    _currentMigration.namespaces[importMigration.path] =
        namespaceForPath(import.url);

    // Ensure that references to members' transient dependencies can be
    // namespaced.
    _currentMigration.variables.addEntries(importMigration.variables.entries);
    _currentMigration.mixins.addEntries(importMigration.mixins.entries);
    _currentMigration.functions.addEntries(importMigration.functions.entries);
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    super.visitIncludeRule(node);
    if (_currentMigration.localScope?.isLocalMixin(node.name) ?? false) return;
    if (!_currentMigration.mixins.containsKey(node.name)) return;
    var namespace =
        _currentMigration.namespaceForNode(_currentMigration.mixins[node.name]);
    if (namespace == null) return;
    var endName = node.arguments.span.start.offset;
    var startName = endName - node.name.length;
    var nameSpan = node.span.file.span(startName, endName);
    _currentMigration.patches.add(Patch(nameSpan, "$namespace.${node.name}"));
  }

  /// Declares the mixin within the current scope before visiting it.
  @override
  void visitMixinRule(MixinRule node) {
    _currentMigration.declareMixin(node);
    super.visitMixinRule(node);
  }

  /// Adds a namespace to any variable that requires it.
  visitVariableExpression(VariableExpression node) {
    if (_currentMigration.localScope?.isLocalVariable(node.name) ?? false) {
      return;
    }
    if (!_currentMigration.variables.containsKey(node.name)) return;
    var namespace = _currentMigration
        .namespaceForNode(_currentMigration.variables[node.name]);
    if (namespace == null) return;
    _currentMigration.patches
        .add(Patch(node.span, "\$$namespace.${node.name}"));
  }

  /// Declares a variable within the current scope before visiting it.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _currentMigration.declareVariable(node);
    super.visitVariableDeclaration(node);
  }

  // Expression Tree Treversal

  @override
  visitExpression(Expression expression) => expression.accept(this);

  visitBinaryOperationExpression(BinaryOperationExpression node) {
    node.left.accept(this);
    node.right.accept(this);
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

  // No-Op Expression Tree Leaves

  visitBooleanExpression(BooleanExpression node) {}
  visitColorExpression(ColorExpression node) {}
  visitNullExpression(NullExpression node) {}
  visitNumberExpression(NumberExpression node) {}
  visitSelectorExpression(SelectorExpression node) {}
  visitValueExpression(ValueExpression node) {}
}
