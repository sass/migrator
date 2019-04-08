// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:path/path.dart' as p;

import 'package:sass_migrator/src/migration_visitor.dart';
import 'package:sass_migrator/src/migrator.dart';
import 'package:sass_migrator/src/patch.dart';
import 'package:sass_migrator/src/utils.dart';

import 'module/built_in_functions.dart';
import 'module/local_scope.dart';

/// Migrates stylesheets to the new module system.
class ModuleMigrator extends Migrator {
  final name = "module";
  final description = "Migrates stylesheets to the new module system.";

  /// Global variables defined at any time during the migrator run.
  final _variables = normalizedMap<VariableDeclaration>();

  /// Global mixins defined at any time during the migrator run.
  final _mixins = normalizedMap<MixinRule>();

  /// Global functions defined at any time during the migrator run.
  final _functions = normalizedMap<FunctionRule>();

  /// Runs the module migrator on [entrypoint] and its dependencies and returns
  /// a map of migrated contents.
  ///
  /// If [migrateDependencies] is false, the migrator will still be run on
  /// dependencies, but they will be excluded from the resulting map.
  Map<Uri, String> migrateFile(Uri entrypoint) {
    var migrated = _ModuleMigrationVisitor(this, entrypoint).run();
    if (!migrateDependencies) {
      migrated.removeWhere((url, contents) => url != entrypoint);
    }
    return migrated;
  }
}

class _ModuleMigrationVisitor extends MigrationVisitor {
  final ModuleMigrator migrator;

  /// Constructs a new module migration visitor.
  ///
  /// Note: We always set [migratedDependencies] to true since the module
  /// migrator needs to always run on dependencies. The `migrateFile` method of
  /// the module migrator will filter out the dependencies' migration results.
  _ModuleMigrationVisitor(this.migrator, Uri url, {Map<Uri, String> migrated})
      : super(url, true, migrated: migrated);

  _ModuleMigrationVisitor newInstance(Uri url) =>
      _ModuleMigrationVisitor(migrator, url, migrated: migrated);

  /// Namespaces of modules used in this stylesheet.
  final _namespaces = <Uri, String>{};

  /// Set of additional use rules necessary for referencing members of
  /// implicit dependencies / built-in modules.
  ///
  /// This set contains the path provided in the use rule, not the canonical
  /// path (e.g. "a" rather than "dir/a.scss").
  final _additionalUseRules = Set<String>();

  /// Global variables declared with !default that could be configured.
  final _configurableVariables = normalizedSet();

  /// Local variables, mixins, and functions for this migration.
  ///
  /// When at the top level of the stylesheet, this will be null.
  LocalScope _localScope;

  /// Returns the migrated contents of this stylesheet, based on [patches] and
  /// [_additionalUseRules], or null if the stylesheet does not change.
  @override
  String getMigratedContents() {
    var results = super.getMigratedContents();
    if (results == null) return null;
    var semicolon = stylesheet.span.file.url.path.endsWith('.sass') ? "" : ";";
    var uses = _additionalUseRules.map((use) => '@use "$use"$semicolon\n');
    return uses.join("") + results;
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
  @override
  void visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    patchNamespaceForFunction(node.name.asPlain, (name, namespace) {
      addPatch(Patch(node.name.span, "$namespace.$name"));
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
      patchNamespaceForFunction(fnName.text.asPlain, (name, namespace) {
        var span = fnName.span;
        if (fnName.hasQuotes) {
          span = span.file.span(span.start.offset + 1, span.end.offset - 1);
        }
        addPatch(Patch(span, name));
        var beforeParen = node.span.end.offset - 1;
        addPatch(Patch(node.span.file.span(beforeParen, beforeParen),
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
  void patchNamespaceForFunction(
      String name, void patcher(String name, String namespace)) {
    if (name == null) return;
    if (_localScope?.isLocalFunction(name) ?? false) return;

    var namespace = migrator._functions.containsKey(name)
        ? namespaceForNode(migrator._functions[name])
        : null;

    if (namespace == null) {
      if (!builtInFunctionModules.containsKey(name)) return;
      namespace = builtInFunctionModules[name];
      name = builtInFunctionNameChanges[name] ?? name;
      _additionalUseRules.add("sass:$namespace");
    }
    if (namespace != null) patcher(name, namespace);
  }

  /// Declares the function within the current scope before visiting it.
  @override
  void visitFunctionRule(FunctionRule node) {
    declareFunction(node);
    super.visitFunctionRule(node);
  }

  /// Migrates @import to @use after migrating the imported file.
  @override
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
    var url = resolveRelativeUrl(Uri.parse(import.url));
    var importMigration = newInstance(url)..run();
    _namespaces[importMigration.stylesheet.span.sourceUrl] =
        namespaceForPath(import.url);

    var overrides = [];
    for (var variable in importMigration._configurableVariables) {
      if (migrator._variables.containsKey(variable)) {
        var declaration = migrator._variables[variable];
        if (namespaceForNode(declaration) == null) {
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
    addPatch(Patch(node.span, '@use ${import.span.text}$config'));
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    super.visitIncludeRule(node);
    if (_localScope?.isLocalMixin(node.name) ?? false) return;
    if (!migrator._mixins.containsKey(node.name)) return;
    var namespace = namespaceForNode(migrator._mixins[node.name]);
    if (namespace == null) return;
    var endName = node.arguments.span.start.offset;
    var startName = endName - node.name.length;
    var nameSpan = node.span.file.span(startName, endName);
    addPatch(Patch(nameSpan, "$namespace.${node.name}"));
  }

  /// Declares the mixin within the current scope before visiting it.
  @override
  void visitMixinRule(MixinRule node) {
    declareMixin(node);
    super.visitMixinRule(node);
  }

  @override
  void visitUseRule(UseRule node) {
    // TODO(jathak): Handle existing @use rules.
    throw UnsupportedError(
        "Migrating files with existing @use rules is not yet supported");
  }

  /// Adds a namespace to any variable that requires it.
  @override
  visitVariableExpression(VariableExpression node) {
    if (_localScope?.isLocalVariable(node.name) ?? false) {
      return;
    }
    if (!migrator._variables.containsKey(node.name)) return;
    var namespace = namespaceForNode(migrator._variables[node.name]);
    if (namespace == null) return;
    addPatch(Patch(node.span, "\$$namespace.${node.name}"));
  }

  /// Declares a variable within the current scope before visiting it.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    declareVariable(node);
    super.visitVariableDeclaration(node);
  }

  /// Declares a variable within this stylesheet, in the current local scope if
  /// it exists, or as a global variable otherwise.
  void declareVariable(VariableDeclaration node) {
    if (_localScope == null || node.isGlobal) {
      if (node.isGuarded) {
        _configurableVariables.add(node.name);

        // Don't override if variable already exists.
        migrator._variables.putIfAbsent(node.name, () => node);
      } else {
        migrator._variables[node.name] = node;
      }
    } else {
      _localScope.variables.add(node.name);
    }
  }

  /// Declares a mixin within this stylesheet, in the current local scope if
  /// it exists, or as a global mixin otherwise.
  void declareMixin(MixinRule node) {
    if (_localScope == null) {
      migrator._mixins[node.name] = node;
    } else {
      _localScope.mixins.add(node.name);
    }
  }

  /// Declares a function within this stylesheet, in the current local scope if
  /// it exists, or as a global function otherwise.
  void declareFunction(FunctionRule node) {
    if (_localScope == null) {
      migrator._functions[node.name] = node;
    } else {
      _localScope.functions.add(node.name);
    }
  }

  /// Finds the namespace for the stylesheet containing [node], adding a new use
  /// rule if necessary.
  String namespaceForNode(SassNode node) {
    if (node.span.sourceUrl == stylesheet.span.sourceUrl) return null;
    if (!_namespaces.containsKey(node.span.sourceUrl)) {
      /// Add new use rule for indirect dependency
      var relativePath = p.relative(node.span.sourceUrl.path,
          from: p.dirname(stylesheet.span.sourceUrl.path));
      var basename = p.basenameWithoutExtension(relativePath);
      if (basename.startsWith('_')) basename = basename.substring(1);
      var simplePath = p.relative(p.join(p.dirname(relativePath), basename));
      _additionalUseRules.add(simplePath);
      _namespaces[node.span.sourceUrl] = namespaceForPath(simplePath);
    }
    return _namespaces[node.span.sourceUrl];
  }
}
