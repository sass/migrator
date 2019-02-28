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

/// Runs a migration of multiple [entrypoints] and their dependencies without
/// writing any changes to disk.
///
/// Each entrypoint migrates all of its dependencies separately from the other
/// entrypoints. Certain stylesheets may be migrated multiple times. If the
/// migrated text of a stylesheet for each run is not identical, this will
/// error.
///
/// If [directory] is provided, the entrypoints will be interpreted relative to
/// it. Otherwise, they'll be interpreted relative to the current directory.
///
/// Entrypoints and dependencies that did not require any changes will not be
/// included in the results.
p.PathMap<String> migrateFiles(Iterable<String> entrypoints,
    {String directory}) {
  var allMigrated = p.PathMap<String>();
  for (var entrypoint in entrypoints) {
    var migrated = _Migrator(directory: directory).migrate(entrypoint);
    for (var file in migrated.keys) {
      if (allMigrated.containsKey(file) &&
          migrated[file] != allMigrated[file]) {
        throw UnsupportedError(
            "$file is migrated in more than one way by these entrypoints.");
      }
      allMigrated[file] = migrated[file];
    }
  }
  return allMigrated;
}

class _Migrator extends RecursiveStatementVisitor implements ExpressionVisitor {
  /// List of all migrations for files touched by this run.
  final _migrations = p.PathMap<StylesheetMigration>();

  /// List of migrations in progress. The last item is the current migration.
  final _activeMigrations = <StylesheetMigration>[];

  /// Global variables defined at any time during the migrator run.
  final _variables = normalizedMap<VariableDeclaration>();

  /// Global mixins defined at any time during the migrator run.
  final _mixins = normalizedMap<MixinRule>();

  /// Global functions defined at any time during the migrator run.
  final _functions = normalizedMap<FunctionRule>();

  /// Directory this migration is run from.
  final String _directory;

  _Migrator({String directory}) : _directory = directory ?? p.current;

  /// Local variables, mixins, and functions for migrations in progress.
  ///
  /// The migrator will modify this as it traverses stylesheets. When at the
  /// top level of a stylesheet, this will be null.
  LocalScope _localScope;

  /// Current stylesheet being actively migrated.
  StylesheetMigration get _currentMigration =>
      _activeMigrations.isNotEmpty ? _activeMigrations.last : null;

  /// Runs the migrator on [entrypoint] and its dependencies and returns a map
  /// of migrated contents.
  p.PathMap<String> migrate(String entrypoint) {
    _migrateStylesheet(entrypoint);
    var results = p.PathMap<String>();
    for (var migration in _migrations.values) {
      results[migration.path] = migration.migratedContents;
    }
    return results;
  }

  /// Migrates the stylesheet at [path] if it hasn't already been migrated and
  /// returns the StylesheetMigration instance for it regardless.
  StylesheetMigration _migrateStylesheet(String path) {
    path = canonicalizePath(p.join(
        _currentMigration == null
            ? _directory
            : p.dirname(_currentMigration.path),
        path));
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
    _localScope = LocalScope(_localScope);
    super.visitChildren(node);
    _localScope = _localScope.parent;
  }

  /// Adds a namespace to any function call that require it.
  void visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    visitArgumentInvocation(node.arguments);

    if (node.name.asPlain == null) return;
    var name = node.name.asPlain;
    if (_localScope?.isLocalFunction(name) ?? false) return;

    var namespace = _functions.containsKey(name)
        ? _currentMigration.namespaceForNode(_functions[name])
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
    _declareFunction(node);
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

    if (_localScope != null) {
      // TODO(jathak): Handle nested imports
      return;
    }
    // TODO(jathak): Confirm that this import appears before other rules

    var importMigration = _migrateStylesheet(import.url);
    _currentMigration.namespaces[importMigration.path] =
        namespaceForPath(import.url);

    var overrides = [];
    for (var variable in importMigration.configurableVariables) {
      if (_variables.containsKey(variable)) {
        var declaration = _variables[variable];
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
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    super.visitIncludeRule(node);
    if (_localScope?.isLocalMixin(node.name) ?? false) return;
    if (!_mixins.containsKey(node.name)) return;
    var namespace = _currentMigration.namespaceForNode(_mixins[node.name]);
    if (namespace == null) return;
    var endName = node.arguments.span.start.offset;
    var startName = endName - node.name.length;
    var nameSpan = node.span.file.span(startName, endName);
    _currentMigration.patches.add(Patch(nameSpan, "$namespace.${node.name}"));
  }

  /// Declares the mixin within the current scope before visiting it.
  @override
  void visitMixinRule(MixinRule node) {
    _declareMixin(node);
    super.visitMixinRule(node);
  }

  /// Adds a namespace to any variable that requires it.
  visitVariableExpression(VariableExpression node) {
    if (_localScope?.isLocalVariable(node.name) ?? false) {
      return;
    }
    if (!_variables.containsKey(node.name)) return;
    var namespace = _currentMigration.namespaceForNode(_variables[node.name]);
    if (namespace == null) return;
    _currentMigration.patches
        .add(Patch(node.span, "\$$namespace.${node.name}"));
  }

  /// Declares a variable within the current scope before visiting it.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _declareVariable(node);
    super.visitVariableDeclaration(node);
  }

  /// Declares a variable within this stylesheet, in the current local scope if
  /// it exists, or as a global variable otherwise.
  void _declareVariable(VariableDeclaration node) {
    if (_localScope == null || node.isGlobal) {
      if (node.isGuarded) {
        _currentMigration.configurableVariables.add(node.name);

        // Don't override if variable already exists.
        _variables.putIfAbsent(node.name, () => node);
      } else {
        _variables[node.name] = node;
      }
    } else {
      _localScope.variables.add(node.name);
    }
  }

  /// Declares a mixin within this stylesheet, in the current local scope if
  /// it exists, or as a global mixin otherwise.
  void _declareMixin(MixinRule node) {
    if (_localScope == null) {
      _mixins[node.name] = node;
    } else {
      _localScope.mixins.add(node.name);
    }
  }

  /// Declares a function within this stylesheet, in the current local scope if
  /// it exists, or as a global function otherwise.
  void _declareFunction(FunctionRule node) {
    if (_localScope == null) {
      _functions[node.name] = node;
    } else {
      _localScope.functions.add(node.name);
    }
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
