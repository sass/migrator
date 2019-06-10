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
import 'package:source_span/source_span.dart';

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
  final _globalVariables = normalizedMap<VariableDeclaration>();

  /// Global mixins defined at any time during the migrator run.
  final _globalMixins = normalizedMap<MixinRule>();

  /// Global functions defined at any time during the migrator run.
  final _globalFunctions = normalizedMap<FunctionRule>();

  /// Stores whether a given VariableDeclaration has been referenced in an
  /// expression after being declared.
  final _referencedVariables = <VariableDeclaration>{};

  /// Namespaces of modules used in this stylesheet.
  Map<Uri, String> _namespaces;

  /// Set of additional use rules necessary for referencing members of
  /// implicit dependencies / built-in modules.
  ///
  /// This set contains the path provided in the use rule, not the canonical
  /// path (e.g. "a" rather than "dir/a.scss").
  Set<String> _additionalUseRules;

  /// Set of variables declared outside the current stylesheet that overrode
  /// `!default` variables within the current stylesheet.
  Set<VariableDeclaration> _configuredVariables;

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

  /// Returns a semicolon unless the current stylesheet uses the indented
  /// syntax, in which case this returns an empty string.
  String get _semicolonIfNotIndented =>
      _currentUrl.path.endsWith('.sass') ? "" : ";";

  /// Returns the migrated contents of this stylesheet, based on [patches] and
  /// [_additionalUseRules], or null if the stylesheet does not change.
  @override
  String getMigratedContents() {
    var results = super.getMigratedContents();
    if (results == null) return null;
    var uses = _additionalUseRules
        .map((use) => '@use "$use"$_semicolonIfNotIndented\n');
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
    _patchNamespaceForFunction(node, node.name.asPlain, (name, namespace) {
      addPatch(Patch(node.name.span, "$namespace.$name"));
    });
    visitArgumentInvocation(node.arguments);

    if (node.name.asPlain == "get-function") {
      var nameArgument =
          node.arguments.named['name'] ?? node.arguments.positional.first;
      if (nameArgument is! StringExpression ||
          (nameArgument as StringExpression).text.asPlain == null) {
        emitWarning("get-function call may require \$module parameter",
            nameArgument.span);
        return;
      }
      var fnName = nameArgument as StringExpression;
      _patchNamespaceForFunction(node, fnName.text.asPlain, (name, namespace) {
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

  /// Calls [patcher] when the function [node] with name [name] requires a
  /// namespace and adds a new use rule if necessary.
  ///
  /// When the function is a color function that's not present in the module
  /// system (like `lighten`), this also migrates its `$amount` argument to the
  /// appropriate `color.adjust` argument.
  ///
  /// [patcher] takes two arguments: the name used to refer to that function
  /// when namespaced, and the namespace itself. The name will match the name
  /// provided to the outer function except for built-in functions whose name
  /// within a module differs from its original name.
  void _patchNamespaceForFunction(FunctionExpression node, String name,
      void patcher(String name, String namespace)) {
    if (name == null) return;
    if (_localScope?.isLocalFunction(name) ?? false) return;

    var namespace = _globalFunctions.containsKey(name)
        ? _namespaceForNode(_globalFunctions[name])
        : null;

    if (namespace == null) {
      if (!builtInFunctionModules.containsKey(name)) return;

      namespace = builtInFunctionModules[name];
      name = builtInFunctionNameChanges[name] ?? name;
      if (namespace == 'color' && removedColorFunctions.containsKey(name)) {
        if (node.arguments.positional.length == 2 &&
            node.arguments.named.isEmpty) {
          _patchRemovedColorFunction(name, node.arguments.positional.last);
          name = 'adjust';
        } else if (node.arguments.named.containsKey('amount')) {
          var arg = node.arguments.named['amount'];
          _patchRemovedColorFunction(name, arg,
              existingArgName: _findArgNameSpan(arg));
          name = 'adjust';
        } else {
          emitWarning("Could not migrate malformed '$name' call", node.span);
          return;
        }
      }
      _additionalUseRules.add("sass:$namespace");
    }
    if (namespace != null) patcher(name, namespace);
  }

  /// Given a named argument [arg], returns a span from the start of the name
  /// to the start of the argument itself (e.g. "$amount: ").
  FileSpan _findArgNameSpan(Expression arg) {
    var start = arg.span.start.offset - 1;
    while (arg.span.file.getText(start, start + 1) != r'$') {
      start--;
    }
    return arg.span.file.span(start, arg.span.start.offset);
  }

  /// Patches the amount argument [arg] for a removed color function
  /// (e.g. `lighten`) to add the appropriate name (such as `$lightness`) and
  /// negate the argument if necessary.
  void _patchRemovedColorFunction(String name, Expression arg,
      {FileSpan existingArgName}) {
    var parameter = removedColorFunctions[name];
    var needsParens =
        parameter.endsWith('-') && arg is BinaryOperationExpression;
    var leftParen = needsParens ? '(' : '';
    if (existingArgName == null) {
      addPatch(patchBefore(arg, '$parameter$leftParen'));
    } else {
      addPatch(Patch(existingArgName, '$parameter$leftParen'));
    }
    if (needsParens) addPatch(patchAfter(arg, ')'));
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

    var oldConfiguredVariables = _configuredVariables;
    _configuredVariables = Set();
    visitDependency(Uri.parse(import.url), _currentUrl);
    _namespaces[_lastUrl] = namespaceForPath(import.url);

    // Pass the variables that were configured by the importing file to `with`,
    // and forward the rest and add them to `oldConfiguredVariables` because
    // they were configured by a further-out import.
    var locallyConfiguredVariables = normalizedMap<VariableDeclaration>();
    var externallyConfiguredVariables = normalizedMap<VariableDeclaration>();
    for (var variable in _configuredVariables) {
      if (variable.span.sourceUrl == _currentUrl) {
        locallyConfiguredVariables[variable.name] = variable;
      } else {
        externallyConfiguredVariables[variable.name] = variable;
        oldConfiguredVariables.add(variable);
      }
    }
    _configuredVariables = oldConfiguredVariables;

    if (externallyConfiguredVariables.isNotEmpty) {
      addPatch(patchBefore(
          node,
          "@forward ${import.span.text} show " +
              externallyConfiguredVariables.keys
                  .map((variable) => "\$$variable")
                  .join(", ") +
              "$_semicolonIfNotIndented\n"));
    }

    var configuration = "";
    var configured = <String>[];
    for (var name in locallyConfiguredVariables.keys) {
      var variable = locallyConfiguredVariables[name];
      if (variable.isGuarded || _referencedVariables.contains(variable)) {
        configured.add("\$$name: \$$name");
      } else {
        // TODO(jathak): Handle the case where the expression of this
        // declaration has already been patched.
        addPatch(patchDelete(variable.span));
        var start = variable.span.end.offset;
        var end = start + _semicolonIfNotIndented.length;
        if (variable.span.file.span(end, end + 1).text == '\n') end++;
        addPatch(patchDelete(variable.span.file.span(start, end)));
        configured.add("\$$name: ${variable.expression}");
      }
    }
    if (configured.length == 1) {
      configuration = " with (" + configured.first + ")";
    } else if (configured.isNotEmpty) {
      configuration = " with (\n  " + configured.join(',\n  ') + "\n)";
    }
    addPatch(Patch(node.span, '@use ${import.span.text}$configuration'));
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
    _referencedVariables.add(_globalVariables[node.name]);
    var namespace = _namespaceForNode(_globalVariables[node.name]);
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
      if (node.isGuarded &&
          _globalVariables.containsKey(node.name) &&
          _globalVariables[node.name].span.sourceUrl != _currentUrl) {
        _configuredVariables.add(_globalVariables[node.name]);
      }
      _globalVariables[node.name] = node;
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
