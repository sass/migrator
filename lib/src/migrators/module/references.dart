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
import 'package:sass/src/importer/utils.dart';
import 'package:sass/src/import_cache.dart';
import 'package:sass/src/visitor/recursive_ast.dart';

import 'package:collection/collection.dart';

import '../../util/bidirectional_map.dart';
import '../../util/unmodifiable_bidirectional_map_view.dart';
import '../../utils.dart';
import 'member_declaration.dart';
import 'scope.dart';

import 'built_in_functions.dart';
import 'reference_source.dart';
import 'scope.dart';

/// A bidirectional mapping between member declarations and references to those
/// members.
///
/// This object is generated during an initial pass. The module migrator then
/// uses the information here during the main migration pass to determine how
/// members are referenced.
class References {
  /// An unmodifiable map between variable references and their declarations.
  ///
  /// Each value in this map must be a [VariableDeclaration] or an [Argument].
  final BidirectionalMap<VariableExpression,
      MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >> variables;

  /// An unmodifiable map between variable reassignments and the original
  /// declaration they override.
  ///
  /// If a variable is reassigned multiple times, all reassignments will map
  /// to the original declaration, not the previous reassignment.
  ///
  /// Each value in this map must be a [VariableDeclaration] or an [Argument].
  final BidirectionalMap<MemberDeclaration<VariableDeclaration>,
          MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>
      variableReassignments;

  /// An unmodifiable map from variable declarations with the `!default` flag to
  /// the declaration they would override were it not for that flag.
  ///
  /// This only includes `!default` declarations for variables that already
  /// exist.
  final Map<MemberDeclaration<VariableDeclaration>,
          MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>
      defaultVariableDeclarations;

  /// An unmodifiable map between mixin references and their declarations.
  final BidirectionalMap<IncludeRule, MemberDeclaration<MixinRule>> mixins;

  /// An unmodifiable map between normal function references and their
  /// declarations.
  ///
  /// This only includes references to user-defined functions.
  final BidirectionalMap<FunctionExpression, MemberDeclaration<FunctionRule>>
      functions;

  /// An unmodifiable map between statically-known function references within
  /// a `get-function` call and their declarations.
  ///
  /// This only includes references to user-defined functions.
  final BidirectionalMap<FunctionExpression, MemberDeclaration<FunctionRule>>
      getFunctionReferences;

  /// An unmodifiable set of all member declarations declared in the global
  /// scope of a stylesheet.
  final Set<MemberDeclaration> globalDeclarations;

  /// A mapping from member references to their source.
  ///
  /// This includes references to built-in functions, but it does not include
  /// functions referenced within `get-function` calls (those nodes instead
  /// map to the [ReferenceSource] for the `sass:meta` module).
  final Map<SassNode, ReferenceSource> sources;

  /// An iterable of all member declarations.
  Iterable<MemberDeclaration> get allDeclarations =>
      variables.values.followedBy(mixins.values).followedBy(functions.values);

  /// Returns true if the member declared by [declaration] is referenced within
  /// another stylesheet.
  bool referencedOutsideDeclaringStylesheet(MemberDeclaration declaration) {
    Iterable<SassNode> references;
    if (declaration is FunctionRule) {
      references = functions
          .keysForValue(declaration)
          .followedBy(getFunctionReferences.keysForValue(declaration));
    } else if (declaration is MixinRule) {
      references = mixins.keysForValue(declaration);
    } else {
      references = variables.keysForValue(declaration);
    }
    return references
        .any((reference) => reference.span.sourceUrl != declaration.sourceUrl);
  }

  /// Finds the original declaration of the variable referenced in [reference].
  ///
  /// The return value always wraps a [VariableDeclaration] or an [Argument].
  MemberDeclaration originalDeclaration(VariableExpression reference) {
    var declaration = variables[reference];
    return variableReassignments[declaration] ?? declaration;
  }

  References._(
      BidirectionalMap<VariableExpression,
              MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>
          variables,
      BidirectionalMap<MemberDeclaration<VariableDeclaration>,
              MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>
          variableReassignments,
      Map<MemberDeclaration<VariableDeclaration>,
              MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>
          defaultVariableDeclarations,
      BidirectionalMap<IncludeRule, MemberDeclaration<MixinRule>> mixins,
      BidirectionalMap<FunctionExpression, MemberDeclaration<FunctionRule>>
          functions,
      BidirectionalMap<FunctionExpression, MemberDeclaration<FunctionRule>>
          getFunctionReferences,
      Set<MemberDeclaration> globalDeclarations,
      Map<SassNode, ReferenceSource> sources)
      : variables = UnmodifiableBidirectionalMapView(variables),
        variableReassignments =
            UnmodifiableBidirectionalMapView(variableReassignments),
        defaultVariableDeclarations =
            UnmodifiableMapView(defaultVariableDeclarations),
        mixins = UnmodifiableBidirectionalMapView(mixins),
        functions = UnmodifiableBidirectionalMapView(functions),
        getFunctionReferences =
            UnmodifiableBidirectionalMapView(getFunctionReferences),
        globalDeclarations = UnmodifiableSetView(globalDeclarations),
        sources = UnmodifiableMapView(sources);

  /// Constructs a new [References] object based on a [stylesheet] (imported by
  /// [importer]) and its dependencies.
  factory References(
          ImportCache importCache, Stylesheet stylesheet, Importer importer) =>
      _ReferenceVisitor(importCache).build(stylesheet, importer);
}

/// A visitor that builds a References object.
class _ReferenceVisitor extends RecursiveAstVisitor {
  final _variables = BidirectionalMap<VariableExpression,
      MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>();
  final _variableReassignments = BidirectionalMap<
      MemberDeclaration<VariableDeclaration>,
      MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>();
  final _defaultVariableDeclarations = <MemberDeclaration<VariableDeclaration>,
      MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>{};
  final _mixins = BidirectionalMap<IncludeRule, MemberDeclaration<MixinRule>>();
  final _functions =
      BidirectionalMap<FunctionExpression, MemberDeclaration<FunctionRule>>();
  final _getFunctionReferences =
      BidirectionalMap<FunctionExpression, MemberDeclaration<FunctionRule>>();
  final _globalDeclarations = <MemberDeclaration>{};
  final _sources = <SassNode, ReferenceSource>{};

  /// The current global scope.
  ///
  /// This persists across imports, but not across module loads.
  Scope _scope;

  /// Mapping from canonical stylesheet URLs to the global scope of the module
  /// contained within it.
  ///
  /// Note: Stylesheets only depended on through imports will not have their
  /// own scope in this map; they will instead share a global scope with the
  /// stylesheet that imported them.
  final _moduleScopes = <Uri, Scope>{};

  /// Maps declarations to their source for the current stylesheet.
  Map<MemberDeclaration, ReferenceSource> _declarationSources;

  /// [_declarationSources] for each module.
  final _moduleSources = <Uri, Map<MemberDeclaration, ReferenceSource>>{};

  /// Mapping between member references for which no definition was found and
  /// the scope the reference was contained in.
  ///
  /// Each key of this map should be a [VariableExpression], an [IncludeRule],
  /// or a [FunctionExpression].
  final _unresolvedReferences =
      <SassNode /*VariableExpression|IncludeRule|FunctionExpression*/, Scope>{};

  /// Namespaces present within the current stylesheet.
  ///
  /// Note: Unlike the similar property in _ModuleMigrationVisitor, this only
  /// includes namespaces for `@use` rules that already exist within the file.
  /// It doesn't include namespaces for to-be-migrated imports.
  Map<String, Uri> _namespaces;

  /// URL of the stylesheet currently being migrated.
  Uri _currentUrl;

  /// The importer that's currently being used to resolve relative imports.
  ///
  /// If this is `null`, relative imports aren't supported in the current
  /// stylesheet.
  Importer _importer;

  /// Cache used to load stylesheets.
  ImportCache importCache;

  _ReferenceVisitor(this.importCache);

  /// Constructs a new References object based on a [stylesheet] (imported by
  /// [importer]) and its dependencies.
  References build(Stylesheet stylesheet, Importer importer) {
    _importer = importer;
    _scope = Scope();
    _moduleScopes[stylesheet.span.sourceUrl] = _scope;
    _declarationSources = {};
    _moduleSources[stylesheet.span.sourceUrl] = _declarationSources;
    visitStylesheet(stylesheet);
    _checkUnresolvedReferences(_scope);
    _resolveBuiltInFunctionReferences();
    return References._(
        _variables,
        _variableReassignments,
        _defaultVariableDeclarations,
        _mixins,
        _functions,
        _getFunctionReferences,
        _globalDeclarations,
        _sources);
  }

  /// Checks any remaining [_unresolvedReferences] to see if they match a
  /// built-in function, and adds them to [_sources] if they do.
  void _resolveBuiltInFunctionReferences() {
    var functions = _unresolvedReferences.keys.whereType<FunctionExpression>();
    for (var function in functions) {
      if (_isCssCompatibilityOverload(function)) continue;
      if (function.name.asPlain == null) continue;
      var name = function.name.asPlain;
      var module = builtInFunctionModules[name];
      if (module != null) _sources[function] = BuiltInSource(module);
    }
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

  /// Visits a stylesheet with an empty [_namespaces], storing it in
  /// [_references].
  @override
  void visitStylesheet(Stylesheet node) {
    var oldNamespaces = _namespaces;
    var oldUrl = _currentUrl;
    _namespaces = {};
    _currentUrl = node.span.sourceUrl;
    super.visitStylesheet(node);
    _namespaces = oldNamespaces;
    _currentUrl = oldUrl;
  }

  /// Visits the stylesheet this `@import` rule points to using the existing global
  /// scope.
  @override
  void visitImportRule(ImportRule node) {
    super.visitImportRule(node);
    for (var import in node.imports) {
      if (import is DynamicImport) {
        var result =
            importCache.import(Uri.parse(import.url), _importer, _currentUrl);
        if (result != null) {
          var oldImporter = _importer;
          _importer = result.item1;
          visitStylesheet(result.item2);
          var url = result.item2.span.sourceUrl;
          var currentSource = CurrentSource(url);
          var importSource = ImportSource(url, import);
          for (var declaration in _declarationSources.keys.toList()) {
            if (_declarationSources[declaration] == currentSource) {
              _declarationSources[declaration] = importSource;
            }
          }
          _importer = oldImporter;
        }
      }
    }
  }

  /// Visits the stylesheet this `@use` rule points to using a new global scope
  /// for this module.
  @override
  void visitUseRule(UseRule node) {
    super.visitUseRule(node);
    var canonicalUrl = _loadUseOrForward(node.url);
    _namespaces[node.namespace] = canonicalUrl;

    var moduleSources = _moduleSources[canonicalUrl];
    var currentSource = CurrentSource(canonicalUrl);
    var useSource = UseSource(canonicalUrl, node);
    for (var declaration in moduleSources.keys) {
      if (moduleSources[declaration] == currentSource) {
        _declarationSources[declaration] = useSource;
      }
    }
  }

  /// Given a URL from a `@use` or `@forward` rule, loads and visits the
  /// stylesheet it points to and returns its canonical URL.
  Uri _loadUseOrForward(Uri ruleUrl) {
    var result =
        inUseRule(() => importCache.import(ruleUrl, _importer, _currentUrl));
    if (result == null) return null;
    var stylesheet = result.item2;
    var canonicalUrl = stylesheet.span.sourceUrl;
    if (!_moduleScopes.containsKey(canonicalUrl)) {
      var oldScope = _scope;
      _scope = Scope();
      _moduleScopes[canonicalUrl] = _scope;
      var oldSources = _declarationSources;
      _declarationSources = {};
      _moduleSources[canonicalUrl] = _declarationSources;
      var oldImporter = _importer;
      _importer = result.item1;
      visitStylesheet(stylesheet);
      _checkUnresolvedReferences(_scope);
      _importer = oldImporter;
      _scope = oldScope;
      _declarationSources = oldSources;
    }
    return canonicalUrl;
  }

  /// Visits the stylesheet this `@forward` rule points to using a new global
  /// scope, then copies members from it into the current scope.
  @override
  void visitForwardRule(ForwardRule node) {
    super.visitForwardRule(node);
    var canonicalUrl = _loadUseOrForward(node.url);
    var moduleScope = _moduleScopes[canonicalUrl];
    var prefix = node.prefix ?? '';
    for (var name in moduleScope.variables.keys) {
      var member = moduleScope.variables[name];
      if (member.member is! VariableDeclaration) {
        throw StateError(
            "Arguments should not be present in a module's global scope");
      }
      if (_visibleThroughForward(
          name, node.shownVariables, node.hiddenVariables)) {
        _scope.variables['$prefix$name'] =
            MemberDeclaration.forward(member, node, canonicalUrl);
      }
    }
    for (var name in moduleScope.mixins.keys) {
      if (_visibleThroughForward(
          name, node.shownMixinsAndFunctions, node.hiddenMixinsAndFunctions)) {
        _scope.mixins['$prefix$name'] = MemberDeclaration.forward(
            moduleScope.mixins[name], node, canonicalUrl);
      }
    }
    for (var name in moduleScope.functions.keys) {
      if (_visibleThroughForward(
          name, node.shownMixinsAndFunctions, node.hiddenMixinsAndFunctions)) {
        _scope.functions['$prefix$name'] = MemberDeclaration.forward(
            moduleScope.functions[name], node, canonicalUrl);
      }
    }
  }

  bool _visibleThroughForward(
          String name, Set<String> shown, Set<String> hidden) =>
      (shown?.contains(name) ?? true) && !(hidden?.contains(name) ?? false);

  /// Visits each of [node]'s expressions and children.
  ///
  /// All of [node]'s arguments are declared as local variables in a new scope.
  @override
  void visitCallableDeclaration(CallableDeclaration node) {
    _scope = Scope(_scope);
    for (var argument in node.arguments.arguments) {
      _scope.variables[argument.name] = MemberDeclaration(argument);
      if (argument.defaultValue != null) visitExpression(argument.defaultValue);
    }
    super.visitChildren(node);
    _checkUnresolvedReferences(_scope);
    _scope = _scope.parent;
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
    _scope = Scope(_scope);
    super.visitChildren(node);
    _checkUnresolvedReferences(_scope);
    _scope = _scope.parent;
  }

  /// Finds any declarations in [scope] that match one of the references in
  /// [_unresolvedReferences].
  ///
  /// This should be called on a scope immediately before it ends.
  void _checkUnresolvedReferences(Scope scope) {
    for (var reference in _unresolvedReferences.keys.toList()) {
      var refScope = _unresolvedReferences[reference];
      if (!refScope.isDescendentOf(scope)) continue;
      if (reference is VariableExpression) {
        _linkUnresolvedReference(
            reference, reference.name, scope.variables, _variables);
      } else if (reference is IncludeRule) {
        _linkUnresolvedReference(
            reference, reference.name, scope.mixins, _mixins);
      } else if (reference is FunctionExpression) {
        var name = reference.name.asPlain?.replaceAll('_', '-');
        if (name == null) continue;
        if (name == 'get-function') {
          var nameExpression = getStaticNameForGetFunctionCall(reference);
          var staticName = nameExpression.text.replaceAll('_', '-');
          _linkUnresolvedReference(
              reference, staticName, scope.functions, _getFunctionReferences,
              trackSources: false);
        } else {
          _linkUnresolvedReference(
              reference, name, scope.functions, _functions);
        }
      }
    }
  }

  /// If [declarations] contains [name], links [reference] to that declaration
  /// in [references] and removes it from [_unresolvedReferences].
  ///
  /// If [trackSources] is true, this also adds [reference] to [_sources].
  void _linkUnresolvedReference<T extends SassNode>(
      T reference,
      String name,
      Map<String, MemberDeclaration> declarations,
      BidirectionalMap<T, MemberDeclaration> references,
      {bool trackSources = true}) {
    var declaration = declarations[name];
    if (declaration == null) return;
    references[reference] = declaration;
    if (trackSources) _sources[reference] = _declarationSources[declaration];
    _unresolvedReferences.remove(reference);
  }

  /// Returns the scope for a given [namespace].
  ///
  /// If [namespace] is null or does not exist within this stylesheet, this
  /// returns the current stylesheet's scope.
  Scope _scopeForNamespace(String namespace) =>
      _moduleScopes[_namespaces[namespace]] ?? _scope;

  /// Declares a variable in the current scope.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    super.visitVariableDeclaration(node);
    var member = MemberDeclaration(node);
    _declarationSources[member] = CurrentSource(_currentUrl);

    var scope = _scopeForNamespace(node.namespace);
    if (node.isGlobal) scope = scope.global;

    if (node.isGuarded) {
      var existing = scope.findVariable(node.name);
      if (existing != null && existing.sourceUrl != member.sourceUrl) {
        _defaultVariableDeclarations[member] = existing;
      }
    }
    var previous = scope.variables[node.name];
    if (previous == node) return;
    scope.variables[node.name] = member;
    if (scope.isGlobal) _globalDeclarations.add(member);
    var original = _variableReassignments[previous] ?? previous;
    _variableReassignments[member] = original;
  }

  /// Visits the variable reference in [node], storing it.
  @override
  void visitVariableExpression(VariableExpression node) {
    super.visitVariableExpression(node);
    var declaration =
        _scopeForNamespace(node.namespace).findVariable(node.name);
    if (declaration != null) {
      _variables[node] = declaration;
      if (declaration.member is VariableDeclaration) {
        _sources[node] = _declarationSources[declaration];
      }
    } else if (node.namespace == null) {
      _unresolvedReferences[node] = _scope;
    }
  }

  /// Declares a mixin in the current scope.
  @override
  void visitMixinRule(MixinRule node) {
    super.visitMixinRule(node);
    var member = MemberDeclaration(node);
    _declarationSources[member] = CurrentSource(_currentUrl);
    _scope.mixins[node.name] = member;
    if (_scope.isGlobal) _globalDeclarations.add(member);
  }

  /// Visits an `@include` rule, storing the mixin reference.
  @override
  void visitIncludeRule(IncludeRule node) {
    super.visitIncludeRule(node);
    var declaration = _scopeForNamespace(node.namespace).findMixin(node.name);
    if (declaration != null) {
      _mixins[node] = declaration;
      _sources[node] = _declarationSources[declaration];
    } else if (node.namespace == null) {
      _unresolvedReferences[node] = _scope;
    }
  }

  /// Declares a function in the current scope.
  @override
  void visitFunctionRule(FunctionRule node) {
    super.visitFunctionRule(node);
    var member = MemberDeclaration(node);
    _declarationSources[member] = CurrentSource(_currentUrl);
    _scope.functions[node.name] = member;
    if (_scope.isGlobal) _globalDeclarations.add(member);
  }

  /// Visits a function call, storing it if it is a user-defined function.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    super.visitFunctionExpression(node);
    if (node.name.asPlain == null) return;
    var name = node.name.asPlain.replaceAll('_', '-');

    var declaration = _scopeForNamespace(node.namespace).findFunction(name);
    if (declaration != null) {
      _functions[node] = declaration;
      _sources[node] = _declarationSources[declaration];
      return;
    } else if (node.namespace == null) {
      if (name == 'get-function') {
        _sources[node] = BuiltInSource("meta");
      } else {
        _unresolvedReferences[node] = _scope;
        return;
      }
    }

    /// Check for static reference within a get-function call.
    var nameExpression = getStaticNameForGetFunctionCall(node);
    if (nameExpression == null) return;
    var moduleExpression = getStaticModuleForGetFunctionCall(node);
    var namespace = moduleExpression?.text;
    name = nameExpression.text.replaceAll('_', '-');
    declaration = _scopeForNamespace(namespace).findFunction(name);
    if (declaration != null) {
      _getFunctionReferences[node] = declaration;
    } else if (namespace == null) {
      _unresolvedReferences[node] = _scope;
    }
  }
}
