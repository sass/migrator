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
import 'package:sass_migrator/src/migrators/module/member_declaration.dart';
import 'package:sass_migrator/src/util/node_modules_importer.dart';
import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../utils.dart';

import 'module/built_in_functions.dart';
import 'module/forward_type.dart';
import 'module/member_declaration.dart';
import 'module/references.dart';
import 'module/unreferencable_members.dart';
import 'module/unreferencable_type.dart';

/// Migrates stylesheets to the new module system.
class ModuleMigrator extends Migrator {
  final name = "module";
  final description = "Migrates stylesheets to the new module system.";

  @override
  final argParser = ArgParser()
    ..addOption('remove-prefix',
        abbr: 'p', help: 'Removes the provided prefix from members.')
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

  // Hide this until it's finished and the module system is launched.
  final hidden = true;

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
      var importOnlyUrl = getImportOnlyUrl(stylesheet.span.sourceUrl);
      migrated.removeWhere((url, contents) =>
          url != stylesheet.span.sourceUrl && url != importOnlyUrl);
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
  final _renamedMembers = <MemberDeclaration, String>{};

  /// Tracks declarations that reassigned a variable within another module.
  ///
  /// When a reference to this declaration is encountered, the original
  /// declaration will be used for namespacing instead of this one.
  final _reassignedVariables = <MemberDeclaration<VariableDeclaration>>{};

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
  /// This set contains the full `@use` rule without a semicolon or line break
  /// at the end.
  Set<String> _additionalUseRules;

  /// Set of variables declared outside the current stylesheet that overrode
  /// `!default` variables within the current stylesheet.
  Set<MemberDeclaration<VariableDeclaration>> _configuredVariables;

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
    var migrated = super.run(stylesheet, importer);
    if (prefixToRemove != null && _renamedMembers.isNotEmpty) {
      var semicolon = _lastUrl.path.endsWith('.sass') ? '' : ';';
      var importOnlyUrl = getImportOnlyUrl(_lastUrl);
      var dependency =
          _absoluteUrlToDependency(_lastUrl, relativeTo: importOnlyUrl);
      migrated[importOnlyUrl] =
          '@forward "$dependency" as $prefixToRemove*$semicolon\n';
    }
    return migrated;
  }

  /// If [declaration] should be renamed, adds it to [_renamedMembers].
  ///
  /// Members are renamed if they start with [prefixToRemove] or if they start
  /// with `-` or `_` and are referenced outside the stylesheet they were
  /// declared in.
  void _renameDeclaration(MemberDeclaration declaration) {
    var name = declaration.name;
    if (name.startsWith('-') &&
        references.referencedOutsideDeclaringStylesheet(declaration)) {
      // Remove leading `-` since private members can't be accessed outside
      // the module they're declared in.
      name = name.substring(1);
    }
    name = _unprefix(name);
    if (name != declaration.name) _renamedMembers[declaration] = name;
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
    var uses = {
      for (var use in _additionalUseRules) "$use$_semicolonIfNotIndented\n"
    };
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
    /// [newName] is the name of the member after migration. For variables, it
    /// includes the $.
    categorizeMember(MemberDeclaration declaration, String newName) {
      if (declaration.sourceUrl == currentUrl) return;
      if (_shouldForward(declaration.name) &&
          !declaration.name.startsWith('-')) {
        shown[declaration.sourceUrl] ??= {};
        shown[declaration.sourceUrl].add(newName);
      } else if (!newName.startsWith('-') && !newName.startsWith(r'$-')) {
        hidden[declaration.sourceUrl] ??= {};
        hidden[declaration.sourceUrl].add(newName);
      }
    }

    // Divide all global members from dependencies into sets based on whether
    // they should be forwarded or not.
    for (var declaration in references.globalDeclarations) {
      if (declaration.member is VariableDeclaration) {
        categorizeMember(declaration,
            '\$${_renamedMembers[declaration] ?? declaration.name}');
      } else {
        categorizeMember(
            declaration, _renamedMembers[declaration] ?? declaration.name);
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
    super.visitFunctionExpression(node);
    if (node.namespace != null) return;
    if (_isCssCompatibilityOverload(node)) return;

    var declaration = references.functions[node];
    _unreferencable.check(declaration, node);
    _renameReference(nameSpan(node), declaration);
    _patchNamespaceForFunction(node, declaration, (namespace) {
      addPatch(patchBefore(node.name, '$namespace.'));
    });

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
  void _patchNamespaceForFunction(
      FunctionExpression node,
      MemberDeclaration<FunctionRule> declaration,
      void patchNamespace(String namespace),
      {bool getFunctionCall = false}) {
    var span = getFunctionCall
        ? getStaticNameForGetFunctionCall(node)
        : nameSpan(node);
    if (span == null) return;
    var name = span.text.replaceAll('_', '-');

    var namespace = _namespaceForDeclaration(declaration);
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
    patchNamespace(_findBuiltInNamespace(namespace));
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
    _renameReference(nameSpan(node), MemberDeclaration(node));
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
        if (declaration.sourceUrl != currentUrl) continue;
        if (references.globalDeclarations.contains(declaration)) continue;
        _unreferencable.add(declaration, UnreferencableType.localFromImporter);
      }
    }
    visitDependency(Uri.parse(import.url), import.span);
    _upstreamStylesheets.remove(currentUrl);
    _originalImports[_lastUrl] = Tuple2(import.url, importer);
    var asClause = '';
    if (!_useAllowed) {
      _unreferencable = _unreferencable.parent;
      for (var declaration in references.allDeclarations) {
        if (declaration.sourceUrl != _lastUrl) continue;
        _unreferencable.add(
            declaration, UnreferencableType.globalFromNestedImport);
      }
    } else if (!_addNamespace(_lastUrl, import.url)) {
      asClause = ' as ${_namespaces[_lastUrl]}';
    }

    // Pass the variables that were configured by the importing file to `with`,
    // and forward the rest and add them to `oldConfiguredVariables` because
    // they were configured by a further-out import.
    var locallyConfiguredVariables =
        <String, MemberDeclaration<VariableDeclaration>>{};
    var externallyConfiguredVariables =
        <String, MemberDeclaration<VariableDeclaration>>{};
    for (var variable in _configuredVariables) {
      if (variable.sourceUrl == currentUrl) {
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
            span: firstConfig.member.span);
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
      if (variable.member.isGuarded ||
          references.variables.containsValue(variable)) {
        configured.add("\$$name: \$$name");
      } else {
        // TODO(jathak): Handle the case where the expression of this
        // declaration has already been patched.
        var span = variable.member.span;
        var before = span.start.offset;
        var beforeDeclaration =
            span.file.span(before - span.start.column, before);
        if (beforeDeclaration.text.trim() == '') {
          addPatch(patchDelete(beforeDeclaration));
        }
        addPatch(patchDelete(span));
        var start = span.end.offset;
        var end = start + _semicolonIfNotIndented.length;
        if (span.file.span(end, end + 1).text == '\n') end++;
        addPatch(patchDelete(span.file.span(start, end)));
        var nameFormat = _useAllowed ? '\$$name' : '"$name"';
        configured.add("$nameFormat: ${variable.member.expression}");
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
      var namespace = _findBuiltInNamespace('meta');
      configuration = configuration.replaceFirst(' with', r', $with:');
      addPatch(Patch(node.span,
          '@include $namespace.load-css(${import.span.text}$configuration)'));
    } else {
      addPatch(
          Patch(node.span, '@use ${import.span.text}$asClause$configuration'));
    }
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    _useAllowed = false;
    super.visitIncludeRule(node);
    if (node.namespace != null) return;

    var declaration = references.mixins[node];
    _unreferencable.check(declaration, node);
    _renameReference(nameSpan(node), declaration);
    var namespace = _namespaceForDeclaration(declaration);
    if (namespace != null) {
      addPatch(Patch(subspan(nameSpan(node), end: 0), '$namespace.'));
    }
  }

  /// Visits a `@mixin` rule, renaming it if necessary.
  @override
  void visitMixinRule(MixinRule node) {
    _useAllowed = false;
    _renameReference(nameSpan(node), MemberDeclaration(node));
    super.visitMixinRule(node);
  }

  /// Don't visit `@use` or `@forward` rules here, as we'll assume that any
  /// stylesheet depended on this way has already been migrated.
  ///
  /// The migrator will use the information from [references] to migrate
  /// references to members of these dependencies.
  void visitUseRule(UseRule node) {}
  void visitForwardRule(ForwardRule node) {}

  /// Adds a namespace to any variable that requires it.
  @override
  void visitVariableExpression(VariableExpression node) {
    if (node.namespace != null) return;
    var declaration = references.variables[node];
    _unreferencable.check(declaration, node);
    if (_reassignedVariables.contains(declaration)) {
      declaration = references.variableReassignments[declaration];
    }
    _renameReference(nameSpan(node), declaration);
    var namespace = _namespaceForDeclaration(declaration);
    if (namespace != null) {
      addPatch(patchBefore(node, '$namespace.'));
    }
  }

  /// Visits the variable declaration, tracking configured variables and
  /// renaming or namespacing if necessary.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    var declaration = MemberDeclaration(node);
    if (references.defaultVariableDeclarations.containsKey(declaration)) {
      _configuredVariables
          .add(references.defaultVariableDeclarations[declaration]);
    }
    _renameReference(nameSpan(node), declaration);

    var existingNode = references.variableReassignments[declaration];
    var originalUrl = existingNode?.sourceUrl;
    if (existingNode != null &&
        originalUrl != currentUrl &&
        !node.isGuarded &&
        !_upstreamStylesheets.contains(originalUrl)) {
      var namespace = _namespaceForDeclaration(existingNode);
      addPatch(patchBefore(node, '$namespace.'));
      _reassignedVariables.add(declaration);
    }

    super.visitVariableDeclaration(node);
  }

  /// If [declaration] was renamed, patches [span] to use the same name.
  void _renameReference(FileSpan span, MemberDeclaration declaration) {
    if (declaration == null) return;
    if (_renamedMembers.containsKey(declaration)) {
      addPatch(Patch(span, _renamedMembers[declaration]));
      return;
    }
    if (_isPrefixedImportOnly(declaration)) {
      addPatch(patchDelete(span, end: declaration.forward.prefix.length));
    }
  }

  /// Returns true if [declaration] was forwarded from a regular stylesheet by
  /// an import-only stylesheet of the same name.
  bool _isPrefixedImportOnly(MemberDeclaration declaration) {
    if (declaration.forward?.prefix == null) return false;
    var containingUrl = declaration.sourceUrl;
    var forwardedUrl = declaration.forwardedUrl;
    var containingFile = containingUrl.pathSegments.last;
    var forwardedFile = forwardedUrl.pathSegments.last;
    var forwardedBasename = forwardedFile.substring(
        0, forwardedFile.length - forwardedFile.split('.').last.length - 1);
    var containingExtension = containingFile.split('.').last;
    return containingUrl.resolve('.') == forwardedUrl.resolve('.') &&
        containingFile == "$forwardedBasename.import.$containingExtension";
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

  /// Adds a new namespace where the URL of the `@use` rule is [useRuleUrl] and
  /// the canonical URL is [canonicalUrl].
  ///
  /// This returns true if the default namespace for [useRuleUrl] is used and
  /// false if an alternate namespace was used.
  bool _addNamespace(Uri canonicalUrl, String useRuleUrl) {
    var defaultNamespace = namespaceForPath(useRuleUrl);
    var namespace = defaultNamespace;
    var count = 1;
    while (_namespaces.containsValue(namespace)) {
      namespace = '$defaultNamespace${++count}';
    }
    _namespaces[canonicalUrl] = namespace;
    return namespace == defaultNamespace;
  }

  /// Returns the namespace that built-in module [module] is loaded under.
  ///
  /// This adds an additional `@use` rule if [module] has not been loaded yet.
  String _findBuiltInNamespace(String module) {
    var url = builtInModuleUrls[module];
    if (_namespaces.containsKey(url)) {
      return _namespaces[url];
    } else if (_addNamespace(url, module)) {
      _additionalUseRules.add('@use "sass:$module"');
      return module;
    } else {
      var namespace = _namespaces[url];
      _additionalUseRules.add('@use "sass:$module" as $namespace');
      return namespace;
    }
  }

  /// Finds the namespace for the stylesheet containing [declaration], adding a
  /// new `@use` rule if necessary.
  String _namespaceForDeclaration(MemberDeclaration declaration) {
    if (declaration == null) return null;
    if (declaration.sourceUrl == currentUrl) return null;
    if (!_namespaces.containsKey(declaration.sourceUrl)) {
      // Add new `@use` rule for indirect dependency
      var simplePath = _absoluteUrlToDependency(declaration.sourceUrl);
      var asClause = _addNamespace(declaration.sourceUrl, simplePath)
          ? ''
          : ' as ${_namespaces[declaration.sourceUrl]}';
      _additionalUseRules.add('@use "$simplePath"$asClause');
    }
    return _namespaces[declaration.sourceUrl];
  }

  /// Converts an absolute URL for a stylesheet into the simplest string that
  /// could be used to depend on that stylesheet from the current one in a
  /// `@use`, `@forward`, or `@import` rule.
  String _absoluteUrlToDependency(Uri url, {Uri relativeTo}) {
    relativeTo ??= currentUrl;
    var tuple = _originalImports[url];
    if (tuple?.item2 is NodeModulesImporter) return tuple.item1;

    var loadPathUrls = loadPaths.map((path) => p.toUri(p.absolute(path)));
    var potentialUrls = [
      p.url.relative(url.path, from: p.url.dirname(relativeTo.path)),
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
