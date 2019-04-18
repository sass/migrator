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

  /// Runs the module migrator on [entrypoint] and its dependencies and returns
  /// a map of migrated contents.
  ///
  /// If [migrateDependencies] is false, the migrator will still be run on
  /// dependencies, but they will be excluded from the resulting map.
  Map<Uri, String> migrateFile(Uri entrypoint) {
    var migrated = _ModuleMigrationVisitor().run(entrypoint);
    if (!migrateDependencies) {
      migrated.removeWhere((url, contents) => url != entrypoint);
    }
    return migrated;
  }
}

class _ModuleMigrationVisitor extends MigrationVisitor {
  /// Global variables defined at any time during the migrator run.
  ///
  /// We store all declarations instead of just the most recent one for use in
  /// detecting configurable variables.
  final _globalVariables = normalizedMap<List<VariableDeclaration>>();

  /// Global mixins defined at any time during the migrator run.
  final _globalMixins = normalizedMap<MixinRule>();

  /// Global functions defined at any time during the migrator run.
  final _globalFunctions = normalizedMap<FunctionRule>();

  /// Namespaces of modules used in this stylesheet.
  Map<Uri, String> _namespaces;

  /// Set of additional use rules necessary for referencing members of
  /// implicit dependencies / built-in modules.
  ///
  /// This set contains the path provided in the use rule, not the canonical
  /// path (e.g. "a" rather than "dir/a.scss").
  Set<String> _additionalUseRules;

  /// The URL of the current stylesheet.
  Uri _currentUrl;

  /// The URL of the last stylesheet that was completely migrated.
  Uri _lastUrl;

  /// Local variables, mixins, and functions for this migration.
  ///
  /// When at the top level of the stylesheet, this will be null.
  LocalScope _localScope;

  /// Constructs a new module migration visitor.
  ///
  /// Note: We always set [migratedDependencies] to true since the module
  /// migrator needs to always run on dependencies. The `migrateFile` method of
  /// the module migrator will filter out the dependencies' migration results.
  _ModuleMigrationVisitor() : super(migrateDependencies: true);

  /// Returns the migrated contents of this stylesheet, based on [patches] and
  /// [_additionalUseRules], or null if the stylesheet does not change.
  @override
  String getMigratedContents() {
    var results = super.getMigratedContents();
    if (results == null) return null;
    var semicolon = _currentUrl.path.endsWith('.sass') ? "" : ";";
    var uses = _additionalUseRules.map((use) => '@use "$use"$semicolon\n');
    return uses.join() + results;
  }

  /// Stores per-file state before visiting [node] and restores it afterwards.
  @override
  void visitStylesheet(Stylesheet node) {
    var oldNamespaces = _namespaces;
    var oldAdditionalUseRules = _additionalUseRules;
    var oldUrl = _currentUrl;
    _namespaces = {};
    _additionalUseRules = Set();
    _currentUrl = node.span.sourceUrl;
    super.visitStylesheet(node);
    _namespaces = oldNamespaces;
    _additionalUseRules = oldAdditionalUseRules;
    _lastUrl = _currentUrl;
    _currentUrl = oldUrl;
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

  /// Adds a namespace to any function call that requires it.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    _patchNamespaceForFunction(node.name.asPlain, (name, namespace) {
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
      _patchNamespaceForFunction(fnName.text.asPlain, (name, namespace) {
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
  void _patchNamespaceForFunction(
      String name, void patcher(String name, String namespace)) {
    if (name == null) return;
    if (_localScope?.isLocalFunction(name) ?? false) return;

    var namespace = _globalFunctions.containsKey(name)
        ? _namespaceForNode(_globalFunctions[name])
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
    _declareFunction(node);
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

    visitDependency(Uri.parse(import.url), _currentUrl);
    _namespaces[_lastUrl] = namespaceForPath(import.url);

    var configured = _findConfiguredVariables(node, import);
    var config = "";
    if (configured.isNotEmpty) {
      config = " with (\n  " + configured.join(',\n  ') + "\n)";
    }
    addPatch(Patch(node.span, '@use ${import.span.text}$config'));
  }

  /// Finds all configured variables from the given import.
  ///
  /// This returns a list of "$var: <expression>" strings that can be used to
  /// construct the configuration for a use rule.
  ///
  /// If a variable was configured in a downstream stylesheet, this will instead
  /// add a forward rule to make it accessible.
  List<String> _findConfiguredVariables(ImportRule node, Import import) {
    var configured = <String>[];
    for (var name in _globalVariables.keys) {
      var declarations = _globalVariables[name];
      VariableDeclaration lastNonDefault = declarations[0];
      for (var i = 1; i < declarations.length; i++) {
        var declaration = declarations[i];
        if (!declaration.isGuarded) {
          lastNonDefault = declaration;
        } else if (declaration.span.sourceUrl == _lastUrl) {
          if (lastNonDefault.span.sourceUrl == _currentUrl) {
            configured.add("\$$name: ${lastNonDefault.expression}");
          } else if (lastNonDefault.span.sourceUrl != _lastUrl) {
            // A downstream stylesheet configures this variable, so forward it.
            var semicolon = _currentUrl.path.endsWith('.sass') ? '' : ';';
            addPatch(patchBefore(
                node, '@forward ${import.span.text} show \$$name$semicolon\n'));
            // Add a fake variable declaration so that downstream stylesheets
            // configure this module instead of the one we forwarded.
            declarations.insert(i + 1,
                VariableDeclaration(name, null, node.span, guarded: true));
          }
        }
      }
    }
    return configured;
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    super.visitIncludeRule(node);
    if (_localScope?.isLocalMixin(node.name) ?? false) return;
    if (!_globalMixins.containsKey(node.name)) return;
    var namespace = _namespaceForNode(_globalMixins[node.name]);
    if (namespace == null) return;
    var endName = node.arguments.span.start.offset;
    var startName = endName - node.name.length;
    var nameSpan = node.span.file.span(startName, endName);
    addPatch(Patch(nameSpan, "$namespace.${node.name}"));
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
    throw UnsupportedError(
        "Migrating files with existing @use rules is not yet supported");
  }

  /// Adds a namespace to any variable that requires it.
  @override
  visitVariableExpression(VariableExpression node) {
    if (_localScope?.isLocalVariable(node.name) ?? false) {
      return;
    }
    if (!_globalVariables.containsKey(node.name)) return;

    /// Declarations where the expression is null are fake ones used to track
    /// configured variables within indirect dependencies.
    /// See [_findConfiguredVariables].
    var lastRealDeclaration = _globalVariables[node.name]
        .lastWhere((node) => node.expression != null);
    var namespace = _namespaceForNode(lastRealDeclaration);
    if (namespace == null) return;
    addPatch(Patch(node.span, "\$$namespace.${node.name}"));
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
      _globalVariables.putIfAbsent(node.name, () => []);
      _globalVariables[node.name].add(node);
    } else {
      _localScope.variables.add(node.name);
    }
  }

  /// Declares a mixin within this stylesheet, in the current local scope if
  /// it exists, or as a global mixin otherwise.
  void _declareMixin(MixinRule node) {
    if (_localScope == null) {
      _globalMixins[node.name] = node;
    } else {
      _localScope.mixins.add(node.name);
    }
  }

  /// Declares a function within this stylesheet, in the current local scope if
  /// it exists, or as a global function otherwise.
  void _declareFunction(FunctionRule node) {
    if (_localScope == null) {
      _globalFunctions[node.name] = node;
    } else {
      _localScope.functions.add(node.name);
    }
  }

  /// Finds the namespace for the stylesheet containing [node], adding a new use
  /// rule if necessary.
  String _namespaceForNode(SassNode node) {
    if (node.span.sourceUrl == _currentUrl) return null;
    if (!_namespaces.containsKey(node.span.sourceUrl)) {
      /// Add new use rule for indirect dependency
      var relativePath = p.relative(node.span.sourceUrl.path,
          from: p.dirname(_currentUrl.path));
      var basename = p.basenameWithoutExtension(relativePath);
      if (basename.startsWith('_')) basename = basename.substring(1);
      var simplePath = p.relative(p.join(p.dirname(relativePath), basename));
      _additionalUseRules.add(simplePath);
      _namespaces[node.span.sourceUrl] = namespaceForPath(simplePath);
    }
    return _namespaces[node.span.sourceUrl];
  }
}
