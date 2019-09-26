// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/importer.dart';
import 'package:sass/src/import_cache.dart';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:sass_migrator/src/util/node_modules_importer.dart';
import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../utils.dart';

import 'module/built_in_functions.dart';
import 'module/forward_type.dart';
import 'module/references.dart';
import 'module/unreferencable_members.dart';
import 'module/unreferencable_type.dart';

/// Migrates stylesheets to the new module system.
class ModuleMigrator extends Migrator {
  final name = "module";
  final description = "Use the new module system.";

  @override
  final argParser = ArgParser()
    ..addOption('remove-prefix',
        abbr: 'p',
        help: 'Removes PREFIX from all migrated member names.',
        valueHelp: 'PREFIX')
    ..addOption('forward',
        allowed: ['all', 'none', 'prefixed'],
        allowedHelp: {
          'none': "Doesn't forward any members.",
          'prefixed':
              'Forwards members that start with the prefix specified for '
                  '--remove-prefix.',
          'all': 'Forwards all members.'
        },
        defaultsTo: 'none',
        help: 'Specifies which members from dependencies to forward from the '
            'entrypoint.');

  /// Runs the module migrator on [stylesheet] and its dependencies and returns
  /// a map of migrated contents.
  ///
  /// If [migrateDependencies] is false, the migrator will still be run on
  /// dependencies, but they will be excluded from the resulting map.
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var forward = ForwardType(argResults['forward']);
    if (forward == ForwardType.prefixed &&
        argResults['remove-prefix'] == null) {
      throw MigrationException(
          'You must provide --remove-prefix with --forward=prefixed so we know '
          'which prefixed members to forward.');
    }
    var references = References(importCache, stylesheet, importer);
    var migrated = _ModuleMigrationVisitor(
            importCache, references, globalResults['load-path'] as List<String>,
            prefixToRemove:
                (argResults['remove-prefix'] as String)?.replaceAll('_', '-'),
            forward: forward)
        .run(stylesheet, importer);
    if (!migrateDependencies) {
      migrated.removeWhere((url, contents) => url != stylesheet.span.sourceUrl);
    }
    return migrated;
  }
}

class _ModuleMigrationVisitor extends MigrationVisitor {
  /// Set of stylesheets currently being migrated.
  ///
  /// Used to ensure that a dependency declaring a variable that an upstream
  /// stylesheet already declared is not treated as reassignment (since that
  /// would cause a circular dependency).
  final _upstreamStylesheets = <Uri>{};

  /// Maps declarations of members that have been renamed to their new names.
  final _renamedMembers = <SassNode, String>{};

  /// Tracks declarations that reassigned a variable within another module.
  ///
  /// When a reference to this declaration is encountered, the original
  /// declaration will be used for namespacing instead of this one.
  final _reassignedVariables = <VariableDeclaration>{};

  /// Maps canonical URLs to the original URL and importer from the `@import`
  /// rule that last imported that URL.
  final _originalImports = <Uri, Tuple2<String, Importer>>{};

  /// Tracks members that are unreferencable in the current scope.
  UnreferencableMembers _unreferencable = UnreferencableMembers();

  /// Namespaces of modules used in this stylesheet.
  Map<Uri, String> _namespaces;

  /// Set of additional `@use` rules necessary for referencing members of
  /// implicit dependencies / built-in modules.
  ///
  /// This set contains the path provided in the `@use` rule, not the canonical
  /// path (e.g. "a" rather than "dir/a.scss").
  Set<String> _additionalUseRules;

  /// Set of variables declared outside the current stylesheet that overrode
  /// `!default` variables within the current stylesheet.
  Set<VariableDeclaration> _configuredVariables;

  /// Whether @use and @forward are allowed in the current context.
  var _useAllowed = true;

  /// The URL of the last stylesheet that was completely migrated.
  Uri _lastUrl;

  /// A mapping between member declarations and references.
  ///
  /// This performs an initial pass to determine how a declaration seen in the
  /// main migration pass is used.
  final References references;

  /// Cache used to load stylesheets.
  final ImportCache importCache;

  /// List of paths that stylesheets can be loaded from.
  final List<String> loadPaths;

  /// The prefix to be removed from any members with it, or null if no prefix
  /// should be removed.
  final String prefixToRemove;

  /// The value of the --forward flag.
  final ForwardType forward;

  /// Constructs a new module migration visitor.
  ///
  /// [importCache] must be the same one used by [references].
  ///
  /// [loadPaths] should be the same list used to create [importCache].
  ///
  /// Note: We always set [migratedDependencies] to true since the module
  /// migrator needs to always run on dependencies. The `migrateFile` method of
  /// the module migrator will filter out the dependencies' migration results.
  ///
  /// This converts the OS-specific relative [loadPaths] to absolute URL paths.
  _ModuleMigrationVisitor(
      this.importCache, this.references, List<String> loadPaths,
      {this.prefixToRemove, this.forward})
      : loadPaths =
            loadPaths.map((path) => p.toUri(p.absolute(path)).path).toList(),
        super(importCache, migrateDependencies: true);

  /// Checks which global declarations need to be renamed, then runs the
  /// migrator.
  @override
  Map<Uri, String> run(Stylesheet stylesheet, Importer importer) {
    references.globalDeclarations.forEach(_renameDeclaration);
    return super.run(stylesheet, importer);
  }

  /// If [node] should be renamed, adds it to [_renamedMembers].
  ///
  /// Members are renamed if they start with [prefixToRemove] or if they start
  /// with `-` or `_` and are referenced outside the stylesheet they were
  /// declared in.
  void _renameDeclaration(SassNode node) {
    String originalName;
    if (node is VariableDeclaration) {
      originalName = node.name;
    } else if (node is MixinRule) {
      originalName = node.name;
    } else if (node is FunctionRule) {
      originalName = node.name;
    } else {
      throw StateError(
          "Global declarations should not be of type ${node.runtimeType}");
    }

    var name = originalName;
    if (name.startsWith('-') &&
        references.referencedOutsideDeclaringStylesheet(node)) {
      // Remove leading `-` since private members can't be accessed outside
      // the module they're declared in.
      name = name.substring(1);
    }
    name = _unprefix(name);
    if (name != originalName) _renamedMembers[node] = name;
  }

  /// Returns a semicolon unless the current stylesheet uses the indented
  /// syntax, in which case this returns an empty string.
  String get _semicolonIfNotIndented =>
      currentUrl.path.endsWith('.sass') ? "" : ";";

  /// Returns the migrated contents of this stylesheet, based on [patches] and
  /// [_additionalUseRules], or null if the stylesheet does not change.
  @override
  String getMigratedContents() {
    var results = super.getMigratedContents();
    if (results == null) return null;
    var uses = _additionalUseRules
        .map((use) => '@use "$use"$_semicolonIfNotIndented\n');
    return _getEntrypointForwards() + uses.join() + results;
  }

  /// Returns whether the member named [name] should be forwarded in the
  /// entrypoint.
  ///
  /// [name] should be the original name of that member, even if it started with
  /// [prefixToRemove].
  bool _shouldForward(String name) {
    switch (forward) {
      case ForwardType.all:
        return true;
      case ForwardType.none:
        return false;
      case ForwardType.prefixed:
        return name.startsWith(prefixToRemove);
      default:
        throw StateError('--forward should not allow invalid values');
    }
  }

  /// If the current stylesheet is the entrypoint, return a string of `@forward`
  /// rules to forward all members for which [_shouldForward] returns true.
  String _getEntrypointForwards() {
    if (_upstreamStylesheets.isNotEmpty) return '';
    var shown = <Uri, Set<String>>{};
    var hidden = <Uri, Set<String>>{};

    /// Adds the member declared in [declaration] to [shown], [hidden], or
    /// neither depending on whether it originally started with `-` or `_`
    /// (indicating package-privacy) and whether it should be forwarded.
    ///
    /// [originalName] is the name of the member prior to migration. For
    /// variables, it does not include the $.
    ///
    /// [newName] is the name of the member after migration. For variables, it
    /// includes the $.
    categorizeMember(
        SassNode declaration, String originalName, String newName) {
      var url = declaration.span.sourceUrl;
      if (url == currentUrl) return;
      if (_shouldForward(originalName) && !originalName.startsWith('-')) {
        shown[url] ??= {};
        shown[url].add(newName);
      } else if (!newName.startsWith('-') && !newName.startsWith(r'$-')) {
        hidden[url] ??= {};
        hidden[url].add(newName);
      }
    }

    // Divide all global members from dependencies into sets based on whether
    // they should be forwarded or not.
    for (var node in references.globalDeclarations) {
      if (node is VariableDeclaration) {
        categorizeMember(
            node, node.name, '\$${_renamedMembers[node] ?? node.name}');
      } else if (node is MixinRule) {
        categorizeMember(node, node.name, _renamedMembers[node] ?? node.name);
      } else if (node is FunctionRule) {
        categorizeMember(node, node.name, _renamedMembers[node] ?? node.name);
      }
    }

    // Create a `@forward` rule for each dependency that has members that should
    // be forwarded.
    var forwards = <String>[];
    for (var url in shown.keys) {
      var hiddenCount = hidden[url]?.length ?? 0;
      var forward = '@forward "${_absoluteUrlToDependency(url)}"';

      // When not all members from a dependency should be forwarded, use a
      // `hide` clause to hide the ones that shouldn't.
      if (hiddenCount > 0) {
        var hiddenMembers = hidden[url].toList()..sort();
        forward += ' hide ${hiddenMembers.join(", ")}';
      }
      forward += '$_semicolonIfNotIndented\n';
      forwards.add(forward);
    }
    forwards.sort();
    return forwards.join('');
  }

  /// Immediately throw a [MigrationException] when a missing dependency is
  /// encountered, as the module migrator needs to traverse all dependencies.
  @override
  void handleMissingDependency(Uri dependency, FileSpan context) {
    throw MigrationException(
        "Error: Could not find Sass file at '${p.prettyUri(dependency)}'.",
        span: context);
  }

  /// Stores per-file state before visiting [node] and restores it afterwards.
  @override
  void visitStylesheet(Stylesheet node) {
    var oldNamespaces = _namespaces;
    var oldAdditionalUseRules = _additionalUseRules;
    var oldUseAllowed = _useAllowed;
    _namespaces = {};
    _additionalUseRules = Set();
    _useAllowed = true;
    super.visitStylesheet(node);
    _namespaces = oldNamespaces;
    _additionalUseRules = oldAdditionalUseRules;
    _lastUrl = node.span.sourceUrl;
    _useAllowed = oldUseAllowed;
  }

  /// Visits the children of [node] with a new scope for tracking unreferencable
  /// members.
  @override
  void visitChildren(ParentStatement node) {
    _unreferencable = UnreferencableMembers(_unreferencable);
    super.visitChildren(node);
    _unreferencable = _unreferencable.parent;
  }

  /// Adds a namespace to any function call that requires it.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    if (_isCssCompatibilityOverload(node)) return;

    var declaration = references.functions[node];
    _unreferencable.check(declaration, node);
    _renameReference(nameSpan(node), declaration);
    _patchNamespaceForFunction(node, declaration, (namespace) {
      addPatch(patchBefore(node.name, '$namespace.'));
    });
    visitArgumentInvocation(node.arguments);

    if (node.name.asPlain == "get-function") {
      declaration = references.getFunctionReferences[node];
      _unreferencable.check(declaration, node);
      _renameReference(getStaticNameForGetFunctionCall(node), declaration);

      // Ignore get-function calls that already have a module argument.
      var moduleArg = node.arguments.named['module'];
      if (moduleArg == null && node.arguments.positional.length > 2) {
        moduleArg = node.arguments.positional[2];
      }
      if (moduleArg != null) return;

      // Warn for get-function calls without a static name.
      var nameArg =
          node.arguments.named['name'] ?? node.arguments.positional.first;
      if (nameArg is! StringExpression ||
          (nameArg as StringExpression).text.asPlain == null) {
        emitWarning(
            "get-function call may require \$module parameter", nameArg.span);
        return;
      }

      _patchNamespaceForFunction(node, declaration, (namespace) {
        var beforeParen = node.span.end.offset - 1;
        addPatch(Patch(node.span.file.span(beforeParen, beforeParen),
            ', \$module: "$namespace"'));
      }, getFunctionCall: true);
    }
  }

  /// Calls [patchNamespace] when the function [node] requires a namespace.
  ///
  /// This also patches the name for any built-in functions whose names change
  /// in the module system.
  ///
  /// When the function is a color function that's not present in the module
  /// system (like `lighten`), this also migrates its `$amount` argument to the
  /// appropriate `color.adjust` argument.
  ///
  /// If [node] is a get-function call, [getFunctionCall] should be true.
  void _patchNamespaceForFunction(FunctionExpression node,
      FunctionRule declaration, void patchNamespace(String namespace),
      {bool getFunctionCall = false}) {
    var span = getFunctionCall
        ? getStaticNameForGetFunctionCall(node)
        : nameSpan(node);
    if (span == null) return;
    var name = span.text.replaceAll('_', '-');

    var namespace = _namespaceForNode(declaration);
    if (namespace != null) {
      patchNamespace(namespace);
      return;
    }

    if (!builtInFunctionModules.containsKey(name)) return;

    namespace = builtInFunctionModules[name];
    name = builtInFunctionNameChanges[name] ?? name;
    if (namespace == 'color' && removedColorFunctions.containsKey(name)) {
      if (getFunctionCall) {
        emitWarning(
            "$name is not available in the module system and should be "
            "manually migrated to color.adjust",
            span);
        return;
      } else if (node.arguments.positional.length == 2 &&
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
    patchNamespace(namespace);
    if (name != span.text.replaceAll('_', '-')) addPatch(Patch(span, name));
  }

  /// Returns true if [node] is a function overload that exists to provide
  /// compatiblity with plain CSS function calls, and should therefore not be
  /// migrated to the module version.
  bool _isCssCompatibilityOverload(FunctionExpression node) {
    var argument = getOnlyArgument(node.arguments);
    switch (node.name.asPlain) {
      case 'grayscale':
      case 'invert':
      case 'opacity':
        return argument is NumberExpression;
      case 'saturate':
        return argument != null;
      case 'alpha':
        var totalArgs =
            node.arguments.positional.length + node.arguments.named.length;
        if (totalArgs > 1) return true;
        return argument is BinaryOperationExpression &&
            argument.operator == BinaryOperator.singleEquals;
      default:
        return false;
    }
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

  /// Visits a `@function` rule, renaming if necessary.
  @override
  void visitFunctionRule(FunctionRule node) {
    _useAllowed = false;
    _renameReference(nameSpan(node), node);
    super.visitFunctionRule(node);
  }

  /// Migrates an `@import` rule to a `@use` rule after migrating the imported
  /// file.
  @override
  void visitImportRule(ImportRule node) {
    if (node.imports.first is StaticImport) {
      _useAllowed = false;
      super.visitImportRule(node);
      return;
    }
    if (node.imports.length > 1) {
      throw UnimplementedError(
          "Migration of @import rule with multiple imports not supported.");
    }
    var import = node.imports.first as DynamicImport;

    var oldConfiguredVariables = _configuredVariables;
    _configuredVariables = {};
    _upstreamStylesheets.add(currentUrl);
    if (!_useAllowed) {
      _unreferencable = UnreferencableMembers(_unreferencable);
      for (var declaration in references.allDeclarations) {
        if (declaration.span.sourceUrl != currentUrl) continue;
        if (references.globalDeclarations.contains(declaration)) continue;
        _unreferencable.add(declaration, UnreferencableType.localFromImporter);
      }
    }
    visitDependency(Uri.parse(import.url), import.span);
    _upstreamStylesheets.remove(currentUrl);
    _originalImports[_lastUrl] = Tuple2(import.url, importer);
    if (!_useAllowed) {
      _unreferencable = _unreferencable.parent;
      for (var declaration in references.allDeclarations) {
        if (declaration.span.sourceUrl != _lastUrl) continue;
        _unreferencable.add(
            declaration, UnreferencableType.globalFromNestedImport);
      }
    } else {
      _namespaces[_lastUrl] = namespaceForPath(import.url);
    }

    // Pass the variables that were configured by the importing file to `with`,
    // and forward the rest and add them to `oldConfiguredVariables` because
    // they were configured by a further-out import.
    var locallyConfiguredVariables = <String, VariableDeclaration>{};
    var externallyConfiguredVariables = <String, VariableDeclaration>{};
    for (var variable in _configuredVariables) {
      if (variable.span.sourceUrl == currentUrl) {
        locallyConfiguredVariables[variable.name] = variable;
      } else {
        externallyConfiguredVariables[variable.name] = variable;
        oldConfiguredVariables.add(variable);
      }
    }
    _configuredVariables = oldConfiguredVariables;

    if (externallyConfiguredVariables.isNotEmpty) {
      if (!_useAllowed) {
        var firstConfig = externallyConfiguredVariables.values.first;
        throw MigrationException(
            "This declaration attempts to override a default value in an "
            "indirect, nested import of ${p.prettyUri(_lastUrl)}, which is "
            "not possible in the module system.",
            span: firstConfig.span);
      }
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
      if (variable.isGuarded || references.variables.containsValue(variable)) {
        configured.add("\$$name: \$$name");
      } else {
        // TODO(jathak): Handle the case where the expression of this
        // declaration has already been patched.
        var before = variable.span.start.offset;
        var beforeDeclaration = variable.span.file
            .span(before - variable.span.start.column, before);
        if (beforeDeclaration.text.trim() == '') {
          addPatch(patchDelete(beforeDeclaration));
        }
        addPatch(patchDelete(variable.span));
        var start = variable.span.end.offset;
        var end = start + _semicolonIfNotIndented.length;
        if (variable.span.file.span(end, end + 1).text == '\n') end++;
        addPatch(patchDelete(variable.span.file.span(start, end)));
        var nameFormat = _useAllowed ? '\$$name' : '"$name"';
        configured.add("$nameFormat: ${variable.expression}");
      }
    }
    if (configured.length == 1) {
      configuration = " with (" + configured.first + ")";
    } else if (configured.isNotEmpty) {
      var indent = ' ' * node.span.start.column;
      configuration =
          " with (\n$indent  " + configured.join(',\n$indent  ') + "\n$indent)";
    }
    if (!_useAllowed) {
      _additionalUseRules.add('sass:meta');
      configuration = configuration.replaceFirst(' with', r', $with:');
      addPatch(Patch(node.span,
          '@include meta.load-css(${import.span.text}$configuration)'));
    } else {
      addPatch(Patch(node.span, '@use ${import.span.text}$configuration'));
    }
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    _useAllowed = false;
    super.visitIncludeRule(node);

    var declaration = references.mixins[node];
    _unreferencable.check(declaration, node);
    _renameReference(nameSpan(node), declaration);
    var namespace = _namespaceForNode(declaration);
    if (namespace != null) {
      addPatch(Patch(subspan(nameSpan(node), end: 0), '$namespace.'));
    }
  }

  /// Visits a `@mixin` rule, renaming it if necessary.
  @override
  void visitMixinRule(MixinRule node) {
    _useAllowed = false;
    _renameReference(nameSpan(node), node);
    super.visitMixinRule(node);
  }

  @override
  void visitUseRule(UseRule node) {
    // TODO(jathak): Handle existing `@use` rules.
    throw UnsupportedError(
        "Migrating files with existing @use rules is not yet supported");
  }

  /// Adds a namespace to any variable that requires it.
  @override
  void visitVariableExpression(VariableExpression node) {
    var declaration = references.variables[node];
    _unreferencable.check(declaration, node);
    if (_reassignedVariables.contains(declaration)) {
      declaration = references.variableReassignments[declaration];
    }
    _renameReference(nameSpan(node), declaration);
    var namespace = _namespaceForNode(declaration);
    if (namespace != null) {
      addPatch(patchBefore(node, '$namespace.'));
    }
  }

  /// Visits the variable declaration, tracking configured variables and
  /// renaming or namespacing if necessary.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (references.defaultVariableDeclarations.containsKey(node)) {
      _configuredVariables.add(references.defaultVariableDeclarations[node]);
    }
    _renameReference(nameSpan(node), node);

    var existingNode = references.variableReassignments[node];
    var originalUrl = existingNode?.span?.sourceUrl;
    if (existingNode != null &&
        originalUrl != currentUrl &&
        !node.isGuarded &&
        !_upstreamStylesheets.contains(originalUrl)) {
      var namespace = _namespaceForNode(existingNode);
      addPatch(patchBefore(node, '$namespace.'));
      _reassignedVariables.add(node);
    }

    super.visitVariableDeclaration(node);
  }

  /// If [declaration] was renamed, patches [span] to use the same name.
  void _renameReference(FileSpan span, SassNode declaration) {
    if (!_renamedMembers.containsKey(declaration)) return;
    addPatch(Patch(span, _renamedMembers[declaration]));
  }

  /// Returns [name] with [prefixToRemove] removed.
  String _unprefix(String name) {
    if (prefixToRemove == null || prefixToRemove.length > name.length) {
      return name;
    }
    var startOfName = name.substring(0, prefixToRemove.length);
    if (prefixToRemove != startOfName) return name;
    return name.substring(prefixToRemove.length);
  }

  /// Finds the namespace for the stylesheet containing [node], adding a new
  /// `@use` rule if necessary.
  String _namespaceForNode(SassNode node) {
    if (node == null) return null;
    if (node.span.sourceUrl == currentUrl) return null;
    if (!_namespaces.containsKey(node.span.sourceUrl)) {
      // Add new `@use` rule for indirect dependency
      var simplePath = _absoluteUrlToDependency(node.span.sourceUrl);
      _additionalUseRules.add(simplePath);
      _namespaces[node.span.sourceUrl] = namespaceForPath(simplePath);
    }
    return _namespaces[node.span.sourceUrl];
  }

  /// Converts an absolute URL for a stylesheet into the simplest string that
  /// could be used to depend on that stylesheet from the current one in a
  /// `@use`, `@forward`, or `@import` rule.
  String _absoluteUrlToDependency(Uri url) {
    var tuple = _originalImports[url];
    if (tuple?.item2 is NodeModulesImporter) return tuple.item1;

    var loadPathUrls = loadPaths.map((path) => p.toUri(p.absolute(path)));
    var potentialUrls = [
      p.url.relative(url.path, from: p.url.dirname(currentUrl.path)),
      for (var loadPath in loadPathUrls)
        if (p.url.isWithin(loadPath.path, url.path))
          p.url.relative(url.path, from: loadPath.path)
    ];
    var relativePath = minBy(potentialUrls, (url) => url.length);

    var basename = p.url.basenameWithoutExtension(relativePath);
    if (basename.startsWith('_')) basename = basename.substring(1);
    return p.url.relative(p.url.join(p.url.dirname(relativePath), basename));
  }

  /// Disallows `@use` after `@at-root` rules.
  @override
  void visitAtRootRule(AtRootRule node) {
    _useAllowed = false;
    super.visitAtRootRule(node);
  }

  /// Disallows `@use` after at-rules.
  @override
  void visitAtRule(AtRule node) {
    _useAllowed = false;
    super.visitAtRule(node);
  }

  /// Disallows `@use` after `@debug` rules.
  @override
  void visitDebugRule(DebugRule node) {
    _useAllowed = false;
    super.visitDebugRule(node);
  }

  /// Disallows `@use` after `@each` rules.
  @override
  void visitEachRule(EachRule node) {
    _useAllowed = false;
    super.visitEachRule(node);
  }

  /// Disallows `@use` after `@error` rules.
  @override
  void visitErrorRule(ErrorRule node) {
    _useAllowed = false;
    super.visitErrorRule(node);
  }

  /// Disallows `@use` after `@for` rules.
  @override
  void visitForRule(ForRule node) {
    _useAllowed = false;
    super.visitForRule(node);
  }

  /// Disallows `@use` after `@if` rules.
  @override
  void visitIfRule(IfRule node) {
    _useAllowed = false;
    super.visitIfRule(node);
  }

  /// Disallows `@use` after `@media` rules.
  @override
  void visitMediaRule(MediaRule node) {
    _useAllowed = false;
    super.visitMediaRule(node);
  }

  /// Disallows `@use` after style rules.
  @override
  void visitStyleRule(StyleRule node) {
    _useAllowed = false;
    super.visitStyleRule(node);
  }

  /// Disallows `@use` after `@supports` rules.
  @override
  void visitSupportsRule(SupportsRule node) {
    _useAllowed = false;
    super.visitSupportsRule(node);
  }

  /// Disallows `@use` after `@warn` rules.
  @override
  void visitWarnRule(WarnRule node) {
    _useAllowed = false;
    super.visitWarnRule(node);
  }

  /// Disallows `@use` after `@while` rules.
  @override
  void visitWhileRule(WhileRule node) {
    _useAllowed = false;
    super.visitWhileRule(node);
  }
}
