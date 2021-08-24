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
import 'package:sass/src/parse/parser.dart';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

import '../exception.dart';
import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../utils.dart';
import '../util/node_modules_importer.dart';

import 'module/built_in_functions.dart';
import 'module/forward_type.dart';
import 'module/member_declaration.dart';
import 'module/reference_source.dart';
import 'module/references.dart';
import 'module/unreferencable_members.dart';
import 'module/unreferencable_type.dart';

/// Migrates stylesheets to the new module system.
class ModuleMigrator extends Migrator {
  final name = "module";
  final description = "Use the new module system.";

  @override
  final argParser = ArgParser()
    ..addMultiOption('remove-prefix',
        abbr: 'p',
        help: 'Removes PREFIX from all migrated member names.\n'
            'May be set multiple times.',
        valueHelp: 'PREFIX')
    ..addMultiOption('forward',
        allowed: ['all', 'import-only', 'prefixed'],
        allowedHelp: {
          'prefixed':
              'Forwards members that start with the prefix(es) specified for '
                  '--remove-prefix.',
          'all': 'Forwards all members.',
          'import-only':
              'Forwards all members, but only through an import-only file.'
        },
        help: 'Specifies which members from dependencies to forward from the '
            'entrypoint.');

  /// Set of files that declare members that the migrator wants to rename.
  ///
  /// If one of these files would not be migrated, the migrator will error with
  /// a message telling the user to use `--migrate-deps` or add the missing
  /// file to their entrypoints.
  final _filesWithRenamedDeclarations = <Uri>{};

  @override
  Map<Uri, String> run() {
    var results = super.run();
    for (var file in _filesWithRenamedDeclarations) {
      if (!results.containsKey(file)) {
        throw MigrationException(
            'The migrator wants to rename a member in ${p.prettyUri(file)}, '
            'but it is not being migrated. You should re-run the migrator with '
            '--migrate-deps or with ${p.prettyUri(file)} as one of your '
            'entrypoints.');
      }
    }
    return results;
  }

  /// Runs the module migrator on [stylesheet] and its dependencies and returns
  /// a map of migrated contents.
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var forwards = {for (var arg in argResults!['forward']) ForwardType(arg)};
    if (forwards.contains(ForwardType.prefixed) &&
        !argResults!.wasParsed('remove-prefix')) {
      throw MigrationException(
          'You must provide --remove-prefix with --forward=prefixed so we know '
          'which prefixed members to forward.');
    }

    var references = References(importCache, stylesheet, importer);
    var visitor = _ModuleMigrationVisitor(importCache, references,
        globalResults!['load-path'] as List<String>, migrateDependencies,
        prefixesToRemove: (argResults!['remove-prefix'] as List<String>)
            .map((prefix) => prefix.replaceAll('_', '-')),
        forwards: forwards);
    var migrated = visitor.run(stylesheet, importer);
    _filesWithRenamedDeclarations.addAll(
        {for (var member in visitor.renamedMembers.keys) member.sourceUrl});
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
  final renamedMembers = <MemberDeclaration, String>{};

  /// Tracks declarations that reassigned a variable within another module.
  ///
  /// When a reference to this declaration is encountered, the original
  /// declaration will be used for namespacing instead of this one.
  final _reassignedVariables = <MemberDeclaration<VariableDeclaration>>{};

  /// Maps canonical URLs to the original URL and importer from the `@import`
  /// rule that last imported that URL.
  final _originalImports = <Uri, Tuple2<Uri, Importer>>{};

  /// Tracks members that are unreferencable in the current scope.
  var _unreferencable = UnreferencableMembers();

  /// Namespaces of modules used in this stylesheet.
  Map<Uri, String?> get _namespaces =>
      assertInStylesheet(__namespaces, '_namespaces');
  Map<Uri, String?>? __namespaces;

  /// Set of canonical URLs that have a `@forward` rule in the current
  /// stylesheet.
  Set<Uri> get _forwardedUrls =>
      assertInStylesheet(__forwardedUrls, '_forwardedUrls');
  Set<Uri>? __forwardedUrls;

  /// Set of canonical URLs that have a `@use` rule in the current stylesheet.
  ///
  /// This includes rules migrated from `@import` rules, additional rules in the
  /// sets below, and existing `@use` rules in the file prior to migration.
  Set<Uri> get _usedUrls => assertInStylesheet(__usedUrls, '_usedUrls');
  Set<Uri>? __usedUrls;

  /// Set of additional `@use` rules for built-in modules.
  Set<String> get _builtInUseRules =>
      assertInStylesheet(__builtInUseRules, '_builtInUseRules');
  Set<String>? __builtInUseRules;

  /// Set of additional `@use` rules for stylesheets at a load path.
  Set<String> get _additionalLoadPathUseRules => assertInStylesheet(
      __additionalLoadPathUseRules, '_additionalLoadPathUseRules');
  Set<String>? __additionalLoadPathUseRules;

  /// Set of additional `@use` rules for stylesheets relative to the current
  /// one.
  Set<String> get _additionalRelativeUseRules => assertInStylesheet(
      __additionalRelativeUseRules, '_additionalRelativeUseRules');
  Set<String>? __additionalRelativeUseRules;

  /// The first `@import` rule in this stylesheet that was converted to a `@use`
  /// or `@forward` rule, or null if none has been visited yet.
  FileLocation? _beforeFirstImport;

  /// The last `@import` rule in this stylesheet that was converted to a `@use`
  /// or `@forward` rule, or null if none has been visited yet.
  FileLocation? _afterLastImport;

  /// Whether @use and @forward are allowed in the current context.
  var _useAllowed = true;

  /// Whether an import-only stylesheet should be generated.
  ///
  /// This will be set to true if one or more [prefixesToRemove] are removed
  /// from any member visible at the entrypoint.
  var _needsImportOnly = false;

  /// Set of variables declared outside the current stylesheet that overrode
  /// `!default` variables within the current stylesheet.
  Set<MemberDeclaration<VariableDeclaration>> get _configuredVariables =>
      __configuredVariables ??
      (throw StateError(
          "Can't access _configuredVariables when not visiting a dependency."));
  Set<MemberDeclaration<VariableDeclaration>>? __configuredVariables;

  /// A mapping between member declarations and references.
  ///
  /// This performs an initial pass to determine how a declaration seen in the
  /// main migration pass is used.
  final References references;

  /// Cache used to load stylesheets.
  final ImportCache importCache;

  /// List of paths that stylesheets can be loaded from.
  final List<String> loadPaths;

  /// Prefixes to be removed from any members with them, or empty if no prefixes
  /// should be removed.
  final Set<String> prefixesToRemove;

  /// The values of the --forward flag.
  final Set<ForwardType> forwards;

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
  _ModuleMigrationVisitor(this.importCache, this.references,
      List<String> loadPaths, bool migrateDependencies,
      {Iterable<String> prefixesToRemove = const [], this.forwards = const {}})
      : loadPaths = List.unmodifiable(
            loadPaths.map((path) => p.toUri(p.absolute(path)).path)),
        prefixesToRemove = UnmodifiableSetView(prefixesToRemove.toSet()),
        super(importCache, migrateDependencies);

  /// Checks which global declarations need to be renamed, then runs the
  /// migrator.
  @override
  Map<Uri, String> run(Stylesheet stylesheet, Importer importer) {
    references.globalDeclarations.forEach(_renameDeclaration);
    var migrated = super.run(stylesheet, importer);

    if (forwards.contains(ForwardType.importOnly) || _needsImportOnly) {
      var url = stylesheet.span.sourceUrl!;
      var importOnlyUrl = getImportOnlyUrl(url);
      var results = _generateImportOnly(url, importOnlyUrl);
      if (results != null) migrated[importOnlyUrl] = results;
    }
    return migrated;
  }

  /// Generates an import-only file for [entrypoint].
  ///
  /// If a prefix was removed from any members, this will add that prefix back
  /// for the import-only file. If `--forward=import-only` was passed, this will
  /// also add `@forward` rules for members in dependencies that aren't already
  /// forwarded through the entrypoint itself.
  ///
  /// If there are no previously-prefixed members or members from dependencies
  /// to forward, this returns null.
  String? _generateImportOnly(Uri entrypoint, Uri importOnlyUrl) {
    // Sort all members based on the URL they should be forwarded from and the
    // prefix they require (if any).
    var forwardsByUrl = <Uri, Map<String, Set<MemberDeclaration>>>{};
    var hiddenByUrl = <Uri, Set<MemberDeclaration>>{};
    for (var declaration in references.globalDeclarations) {
      var private = declaration.name.startsWith('-');

      // Whether this member will be exposed by the regular entrypoint.
      var visibleAtEntrypoint = !private &&
          (declaration.sourceUrl == entrypoint ||
              _shouldForward(declaration.name));
      // Whether this member should be exposed by the import-only file for the
      // entrypoint.
      var shouldBeVisible =
          _shouldForward(declaration.name, forImportOnly: true) && !private;
      if (!visibleAtEntrypoint && !shouldBeVisible) continue;

      Uri url;
      if (visibleAtEntrypoint) {
        url = entrypoint;
      } else if (declaration is ImportOnlyMemberDeclaration) {
        url = declaration.importOnlyUrl;
      } else {
        url = declaration.sourceUrl;
      }

      var prefix = '';
      if (declaration is ImportOnlyMemberDeclaration &&
          url == declaration.sourceUrl) {
        prefix = declaration.importOnlyPrefix;
      } else {
        var newName = renamedMembers[declaration];
        if (newName != null) {
          assert(declaration.name.endsWith(newName));
          prefix = declaration.name
              .substring(0, declaration.name.length - newName.length);
        } else if (visibleAtEntrypoint) {
          prefix = _prefixFor(declaration.name) ?? '';
        }
      }
      forwardsByUrl
          .putIfAbsent(url, () => {})
          .putIfAbsent(prefix, () => {})
          .add(declaration);

      // Ensures that members already forwarded through the entrypoint aren't
      // also forwarded directly from their source.
      if (visibleAtEntrypoint && declaration.sourceUrl != entrypoint) {
        hiddenByUrl
            .putIfAbsent(declaration.sourceUrl, () => {})
            .add(declaration);
      }
    }

    // If there are no members to forward, or if the only members are forwarded
    // through the entrypoint and don't require a prefix, return null, as no
    // import-only file is necessary.
    if (forwardsByUrl.isEmpty ||
        (forwardsByUrl.length == 1 &&
            forwardsByUrl[entrypoint]?.keys.join() == '')) {
      return null;
    }

    // If entrypoint exposes no members, it should still be forwarded to ensure
    // that the import-only file still includes its CSS.
    var dependency =
        _absoluteUrlToDependency(entrypoint, relativeTo: importOnlyUrl).item1;
    var forwards = forwardsByUrl.remove(entrypoint);
    var entrypointForwards = forwards != null
        ? _forwardRulesForShown(entrypoint, '"$dependency"', forwards, {})
        : ['@forward "$dependency"'];
    var tuples = [
      for (var entry in forwardsByUrl.entries)
        Tuple3(
            entry.key,
            _absoluteUrlToDependency(entry.key, relativeTo: importOnlyUrl)
                .item1,
            entry.value)
    ];
    var forwardLines = [
      for (var tuple in tuples)
        ..._forwardRulesForShown(tuple.item1, '"${tuple.item2}"', tuple.item3,
            hiddenByUrl[tuple.item1] ?? {}),
      ...entrypointForwards
    ];
    var semicolon = entrypoint.path.endsWith('.sass') ? '' : ';';
    return forwardLines.join('$semicolon\n') + '$semicolon\n';
  }

  /// If [declaration] should be renamed, adds it to [renamedMembers].
  ///
  /// Members are renamed if they start with [prefixesToRemove] or if they start
  /// with `-` or `_` and are referenced outside the stylesheet they were
  /// declared in.
  void _renameDeclaration(MemberDeclaration declaration) {
    if (declaration.isForwarded) return;

    var name = declaration.name;
    if (name.startsWith('-') &&
        references.referencedOutsideDeclaringStylesheet(declaration)) {
      // Remove leading `-` since private members can't be accessed outside
      // the module they're declared in.
      name = name.substring(1);
    }
    name = _unprefix(name);
    if (name != declaration.name) {
      renamedMembers[declaration] = name;
      if (_upstreamStylesheets.isEmpty) _needsImportOnly = true;
    }
  }

  /// Returns whether the member named [name] should be forwarded in the
  /// entrypoint.
  ///
  /// [name] should be the original name of that member, even if it started with
  /// [prefixesToRemove].
  bool _shouldForward(String name, {bool forImportOnly = false}) {
    if (forwards.contains(ForwardType.all)) return true;
    if (forImportOnly && forwards.contains(ForwardType.importOnly)) return true;
    return forwards.contains(ForwardType.prefixed) && _prefixFor(name) != null;
  }

  /// If the current stylesheet is the entrypoint, return a string of additional
  /// `@forward` rules not already added by [_migrateImport].
  String _getAdditionalForwardRules() {
    if (_upstreamStylesheets.isNotEmpty) return '';

    var loadPathForwards = <String>[];
    var relativeForwards = <String>[];
    for (var url in references.globalDeclarations
        .map((declaration) => declaration.sourceUrl)
        .toSet()) {
      if (url == currentUrl || _forwardedUrls.contains(url)) continue;
      var forwards =
          _makeForwardRules(url, '"${_absoluteUrlToDependency(url).item1}"');
      if (forwards == null) continue;
      var isRelative = _absoluteUrlToDependency(url).item2;
      (isRelative ? relativeForwards : loadPathForwards)
          .addAll([for (var rule in forwards) '$rule$semicolon\n']);
    }
    var forwards = [...loadPathForwards..sort(), ...relativeForwards..sort()];
    return forwards.isEmpty ? '' : '\n' + forwards.join('');
  }

  /// Stores per-file state and determines namespaces for this stylesheet before
  /// visiting it and restores the per-file state afterwards.
  @override
  void visitStylesheet(Stylesheet node) {
    var oldNamespaces = __namespaces;
    var oldForwardedUrls = __forwardedUrls;
    var oldUsedUrls = __usedUrls;
    var oldBuiltInUseRules = __builtInUseRules;
    var oldLoadPathUseRules = __additionalLoadPathUseRules;
    var oldRelativeUseRules = __additionalRelativeUseRules;
    var oldBeforeFirstImport = _beforeFirstImport;
    var oldAfterLastImport = _afterLastImport;
    var oldUseAllowed = _useAllowed;
    __namespaces = {
      for (var rule in node.uses)
        importCache
                .canonicalize(rule.url,
                    baseImporter: importer, baseUrl: node.span.sourceUrl)
                ?.item2 ??
            rule.url: rule.namespace
    };
    _determineNamespaces(node.span.sourceUrl!, _namespaces);
    __usedUrls = {};
    __forwardedUrls = {};
    __builtInUseRules = {};
    __additionalLoadPathUseRules = {};
    __additionalRelativeUseRules = {};
    _beforeFirstImport = null;
    _afterLastImport = null;
    _useAllowed = true;
    super.visitStylesheet(node);
    __namespaces = oldNamespaces;
    __forwardedUrls = oldForwardedUrls;
    __usedUrls = oldUsedUrls;
    __builtInUseRules = oldBuiltInUseRules;
    __additionalLoadPathUseRules = oldLoadPathUseRules;
    __additionalRelativeUseRules = oldRelativeUseRules;
    _beforeFirstImport = oldBeforeFirstImport;
    _afterLastImport = oldAfterLastImport;
    _useAllowed = oldUseAllowed;
  }

  /// Adds additional patches for extra `@use` and `@forward` rules.
  @override
  void beforePatch(Stylesheet node) {
    useRulesToString(Set<String> useRules) =>
        (useRules.toList()..sort()).map((use) => '$use$semicolon\n').join();

    if (_builtInUseRules.isNotEmpty) {
      // This is added before existing patches to ensure that this patch is
      // inserted before a patch converting an existing `@import` rule to a
      // `@use` rule.
      addPatch(
          Patch.insert(_beforeFirstImport ?? node.span.start,
              useRulesToString(_builtInUseRules)),
          beforeExisting: true);
    }
    var extras = useRulesToString(_additionalLoadPathUseRules) +
        useRulesToString(_additionalRelativeUseRules) +
        _getAdditionalForwardRules();
    if (extras == '') return;
    var insertionPoint = _afterLastImport ?? node.span.start;
    // If the insertion point is in the middle of a line, add a line break
    // before the extra rules.
    if (insertionPoint.column != 0) {
      extras = '\n$extras';
    }
    // Add a line break after the extra rules if there's not already a blank
    // line after the insertion point.
    var whitespace = insertionPoint.pointSpan().extendThroughWhitespace();
    if (!whitespace.text.contains('\n\n') && whitespace.end != node.span.end) {
      extras = '$extras\n'; //extras.substring(0, extras.length - 1);
    }
    addPatch(Patch.insert(insertionPoint, extras));
  }

  /// Adds namespaces for the `@use` rules added to [url] by the migration.
  ///
  /// [namespaces] should contain any existing namespaces prior to migration
  /// (i.e. from existing `@use` rules).
  void _determineNamespaces(Uri url, Map<Uri, String?> namespaces) {
    var sourcesByNamespace = <String, Set<ReferenceSource>>{};
    references.sources.forEach((reference, source) {
      if (reference.span.sourceUrl != url) return;
      if (source is UseSource) return;
      if (namespaces.containsKey(source.url)) return;
      var namespace = source.preferredNamespace;
      if (namespace == null) return;
      sourcesByNamespace.putIfAbsent(namespace, () => {}).add(source);
    });
    // First assign namespaces to module URLs without conflicts.
    var conflictingNamespaces = <String, Set<ReferenceSource>>{};
    sourcesByNamespace.forEach((namespace, sources) {
      if (sources.length == 1 && !namespaces.containsValue(namespace)) {
        namespaces[sources.first.url] = namespace;
      } else {
        conflictingNamespaces[namespace] = sources;
      }
    });

    // Then resolve conflicts where they exist.
    conflictingNamespaces.forEach((namespace, sources) {
      _resolveNamespaceConflict(namespace, sources, namespaces, url);
    });
  }

  /// Resolves a conflict between a set of sources with the same default
  /// namespace, adding namespaces for all of them to [namespaces].
  ///
  /// [currentUrl] is the canonical URL of the file that contains all of the
  /// references in [sources].
  void _resolveNamespaceConflict(String namespace, Set<ReferenceSource> sources,
      Map<Uri, String?> namespaces, Uri currentUrl) {
    // Give first priority to a built-in module.
    var builtIns = sources.whereType<BuiltInSource>();
    if (builtIns.isNotEmpty) {
      namespaces[builtIns.first.url] =
          _resolveBuiltInNamespace(namespace, namespaces);
    }
    var ruleUrlsForSources = {
      for (var source in sources.whereType<ImportSource>())
        source: source.originalRuleUrl ??
            _absoluteUrlToDependency(source.url, relativeTo: currentUrl).item1
    };
    // Then handle `@import` rules, in order of path segment count.
    for (var sources in _orderSources(ruleUrlsForSources)) {
      // We remove the last segment since it's already present in the
      // namespace and any segments with dots since they're not valid in a
      // namespace.
      var paths = {
        for (var source in sources)
          source: ruleUrlsForSources[source]!.pathSegments.toList()
            ..removeLast()
            ..removeWhere((segment) => segment.contains('.'))
      };
      // Start each rule's namespace at the default.
      var aliases = {for (var source in sources) source: namespace};

      // While multiple rules have the same namespace or any rule's
      // namespace is already present, add the next path segment to all
      // namespaces at once.
      while (!valuesAreUnique(aliases) ||
          aliases.values.any(namespaces.containsValue)) {
        // If any of the rules runs out of path segments, fallback to just
        // adding numerical suffixes.
        if (paths.values.any((segments) => segments.isEmpty)) {
          for (var source in sources) {
            namespaces[source.url] =
                _incrementUntilAvailable(namespace, namespaces);
          }
          return;
        }
        aliases = {
          for (var source in sources)
            source: '${paths[source]!.removeLast()}-${aliases[source]}'
        };
      }
      for (var source in sources) {
        namespaces[source.url] = aliases[source];
      }
    }
  }

  /// If [module] is not already a value in [existingNamespaces], returns it.
  /// If it is, but "sass-$module" is not, returns that. Otherwise, returns it
  /// with the lowest available number appended to the end.
  String _resolveBuiltInNamespace(
      String module, Map<Uri, String?> existingNamespaces) {
    return existingNamespaces.containsValue(module) &&
            !existingNamespaces.containsValue('sass-$module')
        ? 'sass-$module'
        : _incrementUntilAvailable(module, existingNamespaces);
  }

  /// If [defaultNamespace] has not already been used in this
  /// [existingNamespaces], returns it. Otherwise, returns it with the lowest
  /// available number appended to the end.
  String _incrementUntilAvailable(
      String defaultNamespace, Map<Uri, String?> existingNamespaces) {
    var count = 1;
    var namespace = defaultNamespace;
    while (existingNamespaces.containsValue(namespace)) {
      namespace = '$defaultNamespace${++count}';
    }
    return namespace;
  }

  /// Given a set of import sources, groups them by the number of path segments
  /// and sorts those groups from fewer to more segments.
  List<Set<ImportSource>> _orderSources(
      Map<ImportSource, Uri> ruleUrlsForSources) {
    var byPathLength = <int, Set<ImportSource>>{};
    for (var entry in ruleUrlsForSources.entries) {
      var pathSegments = entry.value.pathSegments;
      byPathLength.putIfAbsent(pathSegments.length, () => {}).add(entry.key);
    }
    return [
      for (var entry in byPathLength.entries.sorted((a, b) => a.key - b.key))
        entry.value
    ];
  }

  /// Visits [children] with a new scope for tracking unreferencable members.
  @override
  void visitChildren(List<Statement> children) {
    var oldUnreferencable = _unreferencable;
    _unreferencable = UnreferencableMembers(_unreferencable);
    super.visitChildren(children);
    _unreferencable = oldUnreferencable;
  }

  /// Adds a namespace to any function call that requires it.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.namespace != null) {
      super.visitFunctionExpression(node);
      return;
    }
    if (references.sources.containsKey(node)) {
      var declaration = references.functions[node];
      var fnNameSpan = nameSpan(node);
      if (declaration != null) {
        _unreferencable.check(declaration, node);
        _renameReference(fnNameSpan, declaration);
      }
      _patchNamespaceForFunction(node, declaration, (namespace) {
        addPatch(Patch.insert(fnNameSpan.start, '$namespace.'));
      });
    }

    if (node.name == "get-function") {
      var declaration = references.getFunctionReferences[node];
      if (declaration != null) {
        _unreferencable.check(declaration, node);
        var span = getStaticNameForGetFunctionCall(node);
        if (span != null) _renameReference(span, declaration);
      }

      // Ignore get-function calls that already have a module argument.
      var moduleArg = node.arguments.named['module'];
      if (moduleArg == null && node.arguments.positional.length > 2) {
        moduleArg = node.arguments.positional[2];
      }
      if (moduleArg != null) return;

      // Warn for get-function calls without a static name.
      var nameArg =
          node.arguments.named['name'] ?? node.arguments.positional.first;
      if (nameArg is! StringExpression || nameArg.text.asPlain == null) {
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
    super.visitFunctionExpression(node);
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
      MemberDeclaration<FunctionRule>? declaration,
      void patchNamespace(String namespace),
      {bool getFunctionCall = false}) {
    var span = getFunctionCall
        ? getStaticNameForGetFunctionCall(node)
        : nameSpan(node);
    if (span == null) return;
    var name = span.text.replaceAll('_', '-');

    var namespace = declaration.andThen(_namespaceForDeclaration);
    if (namespace != null) {
      patchNamespace(namespace);
      return;
    }

    namespace = builtInFunctionModules[name];
    if (namespace == null) return;

    name = builtInFunctionNameChanges[name] ?? name;
    var parameter = removedColorFunctions[name];
    var amountArg = node.arguments.named['amount'];
    if (namespace == 'color' && parameter != null) {
      if (getFunctionCall) {
        emitWarning(
            "$name is not available in the module system and should be "
            "manually migrated to color.adjust",
            span);
        return;
      } else if (node.arguments.positional.length == 2 &&
          node.arguments.named.isEmpty) {
        _patchRemovedColorFunction(parameter, node.arguments.positional.last);
        name = 'adjust';
      } else if (amountArg != null) {
        _patchRemovedColorFunction(parameter, amountArg,
            existingArgName: _findArgNameSpan(amountArg));
        name = 'adjust';
      } else {
        emitWarning("Could not migrate malformed '$name' call", node.span);
        return;
      }
    }
    namespace = _findOrAddBuiltInNamespace(namespace);
    if (namespace != null) patchNamespace(namespace);
    if (name != span.text.replaceAll('_', '-')) addPatch(Patch(span, name));
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
  void _patchRemovedColorFunction(String parameter, Expression arg,
      {FileSpan? existingArgName}) {
    // Surround the argument in parens if negated to avoid `-` being parsed
    // as part of the namespace.
    var needsParens = parameter.endsWith('-') &&
        (arg is BinaryOperationExpression ||
            arg is FunctionExpression ||
            (arg is VariableExpression &&
                references.variables[arg]?.sourceUrl != currentUrl));
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

  /// Visits an `@import` rule, migrating it to one or more `@use`, `@forward`,
  /// `meta.load-css`, or static `@import` rules
  @override
  void visitImportRule(ImportRule node) {
    var imports =
        partitionOnType<Import, StaticImport, DynamicImport>(node.imports);
    var staticImports = imports.item1;
    var dynamicImports = imports.item2;
    if (dynamicImports.isEmpty) {
      _useAllowed = false;
      return;
    }
    String rulesText;

    var migratedRules = <String>[];

    var indent = ' ' * node.span.start.column;

    for (var import in dynamicImports) {
      Uri? ruleUrl = import.url;
      var tuple = importCache.canonicalize(ruleUrl,
          baseImporter: importer, baseUrl: currentUrl, forImport: true);
      var canonicalImport = tuple?.item2;
      if (canonicalImport != null &&
          references.orphanImportOnlyFiles.containsKey(canonicalImport)) {
        ruleUrl = null;
        var url = references.orphanImportOnlyFiles[canonicalImport]?.url;
        if (url != null && tuple != null) {
          var canonicalRedirect = importCache
              .canonicalize(url,
                  baseImporter: tuple.item1, baseUrl: canonicalImport)!
              .item2;
          ruleUrl = _absoluteUrlToDependency(canonicalRedirect).item1;
        }
      }

      if (ruleUrl != null) {
        if (_useAllowed) {
          migratedRules.addAll(_migrateImportToRules(ruleUrl, import.span));
        } else {
          migratedRules.add(_migrateImportToLoadCss(ruleUrl, import.span)
              .replaceAll('\n', '\n$indent'));
        }
      }
    }

    rulesText = migratedRules.join('$semicolon\n$indent');
    if (rulesText.isEmpty) {
      var span = node.span.extendIfMatches(RegExp(' *$semicolon\n?'));
      addPatch(patchDelete(span));
    } else {
      addPatch(Patch(node.span, rulesText));
    }
    if (_useAllowed) {
      _beforeFirstImport ??= node.span.start;
      _afterLastImport = afterImport(node,
          shouldHaveSemicolon: !currentUrl.path.endsWith('.sass'));
    }

    if (staticImports.isNotEmpty) {
      _useAllowed = false;
      addPatch(Patch.insert(
          _afterLastImport ?? node.span.file.location(0),
          '$indent@import ' +
              staticImports.map((import) => import.span.text).join(', ') +
              '$semicolon\n'));
    }
  }

  /// Migrates an import to a list of `@use` and/or `@forward` rules.
  ///
  /// [ruleUrl] is the non-canonicalized URL for the stylesheet being loaded
  /// while [context] is the span for the import, including the quotes.
  ///
  /// These usually match (so [ruleUrl] is the contents of [context] excluding
  /// quotes), but [ruleUrl] is sometimes replaced with the URL from a
  /// `@forward` rule from an import-only file that does not forward its
  /// corresponding regular file. This allows imports of import-only files that
  /// redirect to a different path to be migrated in-place.
  List<String> _migrateImportToRules(Uri ruleUrl, FileSpan context) {
    var tuple = _migrateImportCommon(ruleUrl, context);
    var canonicalUrl = tuple.item1;
    var config = tuple.item2;
    var forwardForConfig = tuple.item3;

    var asClause = '';
    var defaultNamespace = namespaceForPath(ruleUrl.path);
    // If a member from this dependency is actually referenced, it should
    // already have a namespace from [_determineNamespaces], so we just use
    // a simple number suffix to resolve conflicts at this point.
    var namespace = _namespaces.putIfAbsent(canonicalUrl,
        () => _incrementUntilAvailable(defaultNamespace, _namespaces));
    if (namespace != defaultNamespace) asClause = ' as $namespace';

    var quote = context.text.startsWith("'") ? "'" : '"';
    var quotedUrl = '$quote$ruleUrl$quote';
    var withClause = config == null ? '' : ' with $config';
    var rules = <String>[];
    if (forwardForConfig != null) {
      rules.add('@forward $quotedUrl show $forwardForConfig$withClause');
      // We consume the `with` clause if it exists so that it doesn't get
      // duplicated on the `@use` rule.
      withClause = '';
    }
    var normalForwardRules = _upstreamStylesheets.isEmpty
        ? _makeForwardRules(canonicalUrl, quotedUrl)
        : null;
    if ((rules.isEmpty && normalForwardRules == null) ||
        withClause.isNotEmpty ||
        references.anyMemberReferenced(canonicalUrl, currentUrl)) {
      _usedUrls.add(canonicalUrl);
      rules.add('@use $quotedUrl$asClause$withClause');
    }
    if (normalForwardRules != null) rules.addAll(normalForwardRules);
    return rules;
  }

  /// Similar to [_migrateImportToRules], but instead migrates an import to a
  /// single `meta.load-css` call, or errors if this isn't allowed.
  ///
  /// This is used for migrating `@import` rules that are nested or appear after
  /// some other rules.
  String _migrateImportToLoadCss(Uri ruleUrl, FileSpan context) {
    var oldUnreferencable = _unreferencable;
    _unreferencable = UnreferencableMembers(_unreferencable);
    for (var declaration in references.allDeclarations) {
      if (declaration.sourceUrl != currentUrl) continue;
      _unreferencable.add(declaration, UnreferencableType.fromImporter);
    }

    var tuple = _migrateImportCommon(ruleUrl, context);
    var canonicalUrl = tuple.item1;
    var config = tuple.item2;
    if (tuple.item3 != null) {
      throw MigrationSourceSpanException(
          "This declaration attempts to override a default value in an "
          "indirect, nested import of ${p.prettyUri(canonicalUrl)}, which is "
          "not possible in the module system.",
          _configuredVariables.last.member.span);
    }

    _unreferencable = oldUnreferencable;
    for (var declaration in references.allDeclarations) {
      if (declaration.sourceUrl != canonicalUrl) continue;
      _unreferencable.add(declaration, UnreferencableType.fromNestedImport);
    }

    var meta = _findOrAddBuiltInNamespace('meta');
    var configuration = config == null ? '' : ', \$with: $config';
    var quote = context.text.startsWith("'") ? "'" : '"';
    var quotedUrl = '$quote$ruleUrl$quote';
    return '@include $meta.load-css($quotedUrl$configuration)';
  }

  /// Common logic for migrating imports shared by both the normal migration to
  /// `@use`/`@forward` rules and the migration to `meta.load-css`.
  ///
  /// This returns 3 values. The first is the canonical URL referred to by
  /// [ruleUrl]. The second is a configuration that can be added to the `with`
  /// clause of a `@use` or `@forward` rule or the `$with` parameter of
  /// `meta.load-css`. The third is a string of variables that should be added
  /// to a `show` clause of a `@forward` rule so that they can be configured by
  /// an upstream file.
  Tuple3<Uri, String?, String?> _migrateImportCommon(
      Uri ruleUrl, FileSpan context) {
    var oldConfiguredVariables = __configuredVariables;
    __configuredVariables = {};
    _upstreamStylesheets.add(currentUrl);
    if (migrateDependencies) visitDependency(ruleUrl, context);
    _upstreamStylesheets.remove(currentUrl);

    var tuple = importCache.canonicalize(ruleUrl,
        baseImporter: importer, baseUrl: currentUrl);

    if (tuple == null) {
      throw MigrationSourceSpanException(
          "Could not find Sass file at '${p.prettyUri(ruleUrl)}'.", context);
    }

    // Associate the importer for this URL with the resolved URL so that we can
    // re-use this import URL later on.
    var canonicalUrl = tuple.item2;
    _originalImports.putIfAbsent(
        canonicalUrl, () => Tuple2(ruleUrl, tuple.item1));

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
      } else if (_upstreamStylesheets.contains(variable.sourceUrl)) {
        externallyConfiguredVariables[variable.name] = variable;
        // `oldConfiguredVariables` must be non-null here because
        // `_upstreamStylesheets` is not empty.
        oldConfiguredVariables!.add(variable);
      }
    }
    __configuredVariables = oldConfiguredVariables;

    String? extraForward;
    if (externallyConfiguredVariables.isNotEmpty) {
      extraForward = externallyConfiguredVariables.keys
          .map((variable) => "\$$variable")
          .join(", ");
    }

    String? normalConfig;
    var configured = <String>[];
    locallyConfiguredVariables.forEach((name, variable) {
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
        var end = start + semicolon.length;
        if (span.file.span(end, end + 1).text == '\n') end++;
        addPatch(patchDelete(span.file.span(start, end)));
        var nameFormat = _useAllowed ? '\$$name' : '"$name"';
        configured.add("$nameFormat: ${variable.member.expression}");
      }
    });
    if (configured.length == 1) {
      normalConfig = "(" + configured.first + ")";
    } else if (configured.isNotEmpty) {
      normalConfig = "(\n  " + configured.join(',\n  ') + "\n)";
    }
    return Tuple3(canonicalUrl, normalConfig, extraForward);
  }

  /// If [url] contains any member declarations that should be forwarded from
  /// the entrypoint, returns a list of `@forward` rule(s) to do so.
  ///
  /// If nothing from [url] should be forwarded, returns null.
  List<String>? _makeForwardRules(Uri url, String quotedUrl) {
    var shownByPrefix = <String, Set<MemberDeclaration>>{};
    var hidden = <MemberDeclaration>{};

    // Divide all global members from dependencies into sets based on their
    // subprefix (if any) and whether they should be forwarded or not.
    for (var declaration in references.globalDeclarations) {
      if (declaration.sourceUrl != url) continue;

      var newName = renamedMembers[declaration] ?? declaration.name;
      String? importOnlyPrefix;
      if (declaration is ImportOnlyMemberDeclaration) {
        importOnlyPrefix = declaration.importOnlyPrefix;
        newName = declaration.name.substring(importOnlyPrefix.length);
      }

      if (_shouldForward(declaration.name) &&
          !declaration.name.startsWith('-')) {
        var subprefix = "";
        if (importOnlyPrefix != null) {
          var prefix = _prefixFor(declaration.name);
          if (prefix != null) {
            subprefix = importOnlyPrefix.substring(prefix.length);
          }
        }
        if (declaration.name != newName) _needsImportOnly = true;
        shownByPrefix.putIfAbsent(subprefix, () => {}).add(declaration);
      } else if (!newName.startsWith('-')) {
        hidden.add(declaration);
      }
    }
    if (shownByPrefix.isEmpty) return null;
    _forwardedUrls.add(url);
    return _forwardRulesForShown(url, quotedUrl, shownByPrefix, hidden);
  }

  /// Returns a list of `@forward` rules for [url].
  ///
  /// [quotedUrl] is the form of [url] that should actually be used in the
  /// generated `@forward` rules (including quotes).
  ///
  /// [shownByPrefix] contains all members that should be forwarded, categorized
  /// based on the prefix they should be forwarded with (this will be an empty
  /// string for members without a prefix).
  ///
  /// [hidden] contains members that need to be explicitly hidden from all
  /// `@forward` rules. Members that are already private should not be included
  /// in this set.
  List<String> _forwardRulesForShown(
      Uri url,
      String quotedUrl,
      Map<String, Set<MemberDeclaration>> shownByPrefix,
      Set<MemberDeclaration> hidden) {
    var forwards = <String>[];
    var forwardBase = '@forward $quotedUrl';
    for (var subprefix in shownByPrefix.keys.toList()..sort()) {
      var hiddenMembers = {
        ...hidden,
        for (var entry in shownByPrefix.entries)
          if (entry.key != subprefix) ...entry.value
      };
      var allHidden = <String>{};
      for (var declaration in hiddenMembers) {
        var name = declaration.name;
        if (declaration is ImportOnlyMemberDeclaration) {
          name = name.substring(declaration.importOnlyPrefix.length);
        }
        if (name.startsWith('-')) name = name.substring(1);
        name = _unprefix(name);
        if (subprefix.isNotEmpty) name = '$subprefix$name';
        if (declaration.member is VariableDeclaration) name = '\$$name';
        allHidden.add(name);
      }
      var forward = forwardBase + (subprefix.isEmpty ? '' : ' as $subprefix*');
      if (allHidden.isNotEmpty) {
        var sorted = allHidden.toList()..sort();
        forward += ' hide ${sorted.join(", ")}';
      }
      forwards.add(forward);
    }
    return forwards;
  }

  /// Adds a namespace to any mixin include that requires it.
  @override
  void visitIncludeRule(IncludeRule node) {
    _useAllowed = false;
    super.visitIncludeRule(node);
    if (node.namespace != null) return;

    var declaration = references.mixins[node];
    if (declaration == null) {
      // TODO(jathak): Error here as part of fixing #182.
      return;
    }
    _unreferencable.check(declaration, node);
    _renameReference(nameSpan(node), declaration);
    var namespace = _namespaceForDeclaration(declaration);
    if (namespace != null) {
      addPatch(Patch.insert(nameSpan(node).start, '$namespace.'));
    }
  }

  /// Visits a `@mixin` rule, renaming it if necessary.
  @override
  void visitMixinRule(MixinRule node) {
    _useAllowed = false;
    _renameReference(nameSpan(node), MemberDeclaration(node));
    super.visitMixinRule(node);
  }

  /// Don't visit `@use` rules.
  ///
  /// The migrator will use the information from [references] to migrate
  /// references to members of these dependencies.
  void visitUseRule(UseRule node) {
    _usedUrls.add(importCache
            .canonicalize(node.url, baseImporter: importer, baseUrl: currentUrl)
            ?.item2 ??
        node.url);
  }

  /// Similar to `@use` rules, don't visit `@forward` rules.
  ///
  /// The migrator will use the information from [references] to migrate
  /// references to members of these dependencies.
  void visitForwardRule(ForwardRule node) {
    _forwardedUrls.add(importCache
            .canonicalize(node.url, baseImporter: importer, baseUrl: currentUrl)
            ?.item2 ??
        node.url);
  }

  /// Adds a namespace to any variable that requires it.
  @override
  void visitVariableExpression(VariableExpression node) {
    if (node.namespace != null) return;
    var declaration = references.variables[node];
    if (declaration == null) {
      // TODO(jathak): Error here as part of fixing #182.
      return;
    }
    _unreferencable.check(declaration, node);
    if (_reassignedVariables.contains(declaration)) {
      declaration =
          references.variableReassignments[declaration] ?? declaration;
    }
    _renameReference(nameSpan(node), declaration);
    var namespace = _namespaceForDeclaration(declaration);
    if (namespace != null) {
      // Surround the variable in parens if negated to avoid `-` being parsed
      // as part of the namespace.
      var negated = node.span.matchesBefore('-');
      if (negated) addPatch(patchBefore(node, '('));
      addPatch(patchBefore(node, '$namespace.'));
      if (negated) addPatch(patchAfter(node, ')'));
    }
  }

  /// Visits the variable declaration, tracking configured variables and
  /// renaming or namespacing if necessary.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    var declaration = MemberDeclaration(node);
    var defaultDeclaration =
        references.defaultVariableDeclarations[declaration];
    if (defaultDeclaration is MemberDeclaration<VariableDeclaration>) {
      _configuredVariables.add(defaultDeclaration);
    }

    var existingNode = references.variableReassignments[declaration];
    _renameReference(nameSpan(node), existingNode ?? declaration);

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
    var newName = renamedMembers[declaration];
    if (newName != null) {
      if (newName.startsWith('-') &&
          declaration.name.endsWith(newName.substring(1))) {
        addPatch(patchDelete(span,
            start: 1, end: declaration.name.length - newName.length + 1));
      } else if (declaration.name.endsWith(newName)) {
        addPatch(
            patchDelete(span, end: declaration.name.length - newName.length));
      } else {
        addPatch(Patch(span, newName));
      }
      return;
    }

    if (declaration is ImportOnlyMemberDeclaration) {
      addPatch(patchDelete(span, end: declaration.importOnlyPrefix.length));
    }
  }

  /// If [name] starts with any of [prefixesToRemove], returns it with the
  /// longest matching prefix removed.
  ///
  /// Otherwise, returns [name] unaltered.
  String _unprefix(String name) {
    var isPrivate = name.startsWith('-');
    var unprivateName = isPrivate ? name.substring(1) : name;
    var prefix = _prefixFor(unprivateName);
    if (prefix == null) return name;
    return (isPrivate ? '-' : '') + unprivateName.substring(prefix.length);
  }

  /// Returns the namespace that built-in module [module] is loaded under.
  ///
  /// This adds an additional `@use` rule if [module] has not been loaded yet.
  String? _findOrAddBuiltInNamespace(String module) {
    var url = Uri.parse("sass:$module");
    _namespaces.putIfAbsent(
        url, () => _resolveBuiltInNamespace(module, _namespaces));
    var namespace = _namespaces[url];
    if (!_usedUrls.contains(url)) {
      _usedUrls.add(url);
      var asClause = namespace == module ? '' : ' as $namespace';
      _builtInUseRules.add('@use "sass:$module"$asClause');
    }
    return namespace;
  }

  /// Finds the namespace for the stylesheet containing [declaration], adding a
  /// new `@use` rule if necessary.
  String? _namespaceForDeclaration(MemberDeclaration declaration) {
    var url = declaration.sourceUrl;
    if (url == currentUrl) return null;

    // If we can load [declaration] from a library entrypoint URL, do so. Choose
    // the shortest one if there are multiple options.
    var libraryUrls = references.libraries[declaration];
    if (libraryUrls != null && libraryUrls.isNotEmpty) {
      var minUrl =
          minBy<Uri, int>(libraryUrls, (url) => url.pathSegments.length);
      url = minUrl ?? url;
    }
    if (!_usedUrls.contains(url)) {
      // Add new `@use` rule for indirect dependency
      var tuple = _absoluteUrlToDependency(url);
      var defaultNamespace = namespaceForPath(tuple.item1.path);
      // There are a few edge cases where the reference in [declaration] wasn't
      // tracked by [references.sources], so we add a namespace with simple
      // conflict resolution if one for this URL doesn't already exist.
      _namespaces.putIfAbsent(
          url, () => _incrementUntilAvailable(defaultNamespace, _namespaces));
      var namespace = _namespaces[url];
      var asClause = defaultNamespace == namespace ? '' : ' as $namespace';
      _usedUrls.add(url);
      (tuple.item2 ? _additionalRelativeUseRules : _additionalLoadPathUseRules)
          .add('@use "${tuple.item1}"$asClause');
    }
    return _namespaces[url];
  }

  /// Converts an absolute URL for a stylesheet into the simplest string that
  /// could be used to depend on that stylesheet from the current one in a
  /// `@use`, `@forward`, or `@import` rule.
  ///
  /// The first item of the returned tuple is the dependency, the second item
  /// is true when this dependency is resolved relative to the current URL and
  /// false when it's resolved relative to a load path.
  Tuple2<Uri, bool> _absoluteUrlToDependency(Uri url, {Uri? relativeTo}) {
    relativeTo ??= currentUrl;
    var tuple = _originalImports[url];
    if (tuple != null && tuple.item2 is NodeModulesImporter) {
      return Tuple2(tuple.item1, false);
    }

    var basename = p.url.basenameWithoutExtension(url.path);
    if ((basename == 'index' || basename == '_index') &&
        !isImportOnlyFile(relativeTo)) {
      // Don't directly depend on an index file, since it won't produce a good
      // namespace.
      url = url.replace(path: p.url.dirname(url.path));
      basename = p.url.basename(url.path);
    } else if (basename.startsWith('_')) {
      basename = basename.substring(1);
    }

    var potentialUrls = [
      p.url.relative(url.path, from: p.url.dirname(relativeTo.path)),
      for (var loadPath in loadPaths)
        if (p.url.isWithin(loadPath, url.path))
          p.url.relative(url.path, from: loadPath)
    ];
    var relativePath = minBy<String, int>(potentialUrls, (url) => url.length)!;
    var isRelative = relativePath == potentialUrls.first;
    return Tuple2(
        Uri(
            path: p.url
                .relative(p.url.join(p.url.dirname(relativePath), basename))),
        isRelative);
  }

  /// Returns the longest prefix in [prefixesToRemove] such that [identifier]
  /// starts with it and the remainder is a valid Sass identifier.
  ///
  /// If there is no such prefix, returns `null`.
  String? _prefixFor(String identifier) => maxBy(
      prefixesToRemove.where((prefix) =>
          prefix.length < identifier.length &&
          identifier.startsWith(prefix) &&
          Parser.isIdentifier(identifier.substring(prefix.length))),
      (prefix) => prefix!.length);

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
