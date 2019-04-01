// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:sass_migrator/src/migrator_base.dart';
import 'package:sass_migrator/src/patch.dart';
import 'package:sass_migrator/src/utils.dart';

import 'module/built_in_functions.dart';
import 'module/local_scope.dart';
import 'module/stylesheet_migration.dart';

class ModuleMigrator extends MigratorBase {
  final name = "module";
  final description = "Migrates stylesheets to the new module system.";
  final argParser = ArgParser()
    ..addFlag('migrate-deps',
        abbr: 'd', help: 'Migrate dependencies in addition to entrypoints.');

  bool get _migrateDependencies => argResults['migrate-deps'];

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

  /// Local variables, mixins, and functions for migrations in progress.
  ///
  /// The migrator will modify this as it traverses stylesheets. When at the
  /// top level of a stylesheet, this will be null.
  LocalScope _localScope;

  /// Current stylesheet being actively migrated.
  StylesheetMigration get _currentMigration =>
      _activeMigrations.isNotEmpty ? _activeMigrations.last : null;

  /// The patches to be aplied to the stylesheet being actively migrated.
  List<Patch> get patches => _currentMigration.patches;

  /// Runs the module migrator on [entrypoint] and its dependencies and returns
  /// a map of migrated contents.
  ///
  /// If [_migrateDependencies] is false, the migrator will still be run on
  /// dependencies, but they will be excluded from the resulting map.
  @override
  p.PathMap<String> migrateFile(String entrypoint) {
    var migration = _migrateStylesheet(entrypoint, Directory.current.path);
    var results = p.PathMap<String>();
    addMigration(StylesheetMigration migration) {
      var migrated = migration.migratedContents;
      if (migrated != migration.contents) {
        results[migration.path] = migrated;
      }
    }

    if (_migrateDependencies) {
      _migrations.values.forEach(addMigration);
    } else {
      addMigration(migration);
    }
    return results;
  }

  /// Migrates the stylesheet at [path] if it hasn't already been migrated and
  /// returns the StylesheetMigration instance for it regardless.
  StylesheetMigration _migrateStylesheet(String path, String directory) {
    path = canonicalizePath(p.join(directory, path));
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
    _patchNamespaceForFunction(node.name.asPlain, (name, namespace) {
      _currentMigration.patches.add(Patch(node.name.span, "$namespace.$name"));
    });
    visitArgumentInvocation(node.arguments);

    if (node.name.asPlain == "get-function") {
      var nameArgument =
          node.arguments.named['name'] ?? node.arguments.positional.first;
      if (nameArgument is! StringExpression ||
          (nameArgument as StringExpression).text.asPlain == null) {
        warn("get-function call may require \$module parameter",
            nameArgument.span);
        return;
      }
      var fnName = nameArgument as StringExpression;
      _patchNamespaceForFunction(fnName.text.asPlain, (name, namespace) {
        var span = fnName.span;
        if (fnName.hasQuotes) {
          span = span.file.span(span.start.offset + 1, span.end.offset - 1);
        }
        _currentMigration.patches.add(Patch(span, name));
        var beforeParen = node.span.end.offset - 1;
        _currentMigration.patches.add(Patch(
            node.span.file.span(beforeParen, beforeParen),
            ', \$module: "$namespace"'));
      });
    }
  }

  /// Calls [patcher] when the function [name] requires a namespace and adds a
  /// new use rule if necessary.
  ///
  /// [patcher] takes two arguments: the name used to refer to that function
  /// when namespaced, and the namespace itself. The name will match the name
  /// provided to the outer function except for built-in functions whose name
  /// within a module differs from its original name.
  void _patchNamespaceForFunction(
      String name, void patcher(String name, String namespace)) {
    if (name == null) return;
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
    if (namespace != null) patcher(name, namespace);
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

    var importMigration =
        _migrateStylesheet(import.url, p.dirname(_currentMigration.path));
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

  @override
  void visitUseRule(UseRule node) {
    // TODO(jathak): Handle existing @use rules.
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
}
