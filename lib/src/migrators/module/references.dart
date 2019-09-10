// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/import_cache.dart';
import 'package:sass/src/visitor/recursive_ast.dart';

import 'package:collection/collection.dart';

import '../../util/bidirectional_map.dart';
import '../../util/unmodifiable_bidirectional_map_view.dart';
import 'scope.dart';
import '../../utils.dart';

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
  final UnmodifiableBidirectionalMapView<VariableExpression,
      SassNode /*VariableDeclaration|Argument*/ > variables;

  /// An unmodifiable map between variable reassignments and the original
  /// declaration they override.
  ///
  /// If a variable is reassigned multiple times, all reassignments will map
  /// to the original declaration, not the previous reassignment.
  ///
  /// Each value in this map must be a [VariableDeclaration] or an [Argument].
  final UnmodifiableBidirectionalMapView<VariableDeclaration,
      SassNode /*VariableDeclaration|Argument*/ > variableReassignments;

  /// An unmodifiable map between mixin references and their declarations.
  final UnmodifiableBidirectionalMapView<IncludeRule, MixinRule> mixins;

  /// An unmodifiable map between normal function references and their
  /// declarations.
  ///
  /// This only includes references to user-defined functions.
  final UnmodifiableBidirectionalMapView<FunctionExpression, FunctionRule>
      functions;

  /// An unmodifiable map between statically-known function references within
  /// a `get-function` call and their declarations.
  ///
  /// This only includes references to user-defined functions.
  final UnmodifiableBidirectionalMapView<FunctionExpression, FunctionRule>
      getFunctionReferences;

  /// Returns true if the member declared by [declaration] is referenced within
  /// another stylesheet.
  bool referencedOutsideDeclaringStylesheet(SassNode declaration) {
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
    return references.any(
        (reference) => reference.span.sourceUrl != declaration.span.sourceUrl);
  }

  /// Finds the original declaration of the variable referenced in [reference].
  ///
  /// This always returns [VariableDeclaration] or an [Argument], or null if the
  /// declaration cannot be found.
  SassNode /*VariableDeclaration|Argument*/ originalDeclaration(
      VariableExpression reference) {
    var declaration = variables[reference];
    return variableReassignments[declaration] ?? declaration;
  }

  References._(this.variables, this.variableReassignments, this.mixins,
      this.functions, this.getFunctionReferences);

  /// Constructs a new [References] object based on the stylesheet at
  /// [entrypoint] and its dependencies.
  factory References(ImportCache importCache, Uri entrypoint) =>
      _ReferenceVisitor(importCache).build(entrypoint);
}

/// A visitor that builds a References object.
class _ReferenceVisitor extends RecursiveAstVisitor {
  final _variables = BidirectionalMap<VariableExpression,
      SassNode /*VariableDeclaration|Argument*/ >();
  final _variableReassignments = BidirectionalMap<VariableDeclaration,
      SassNode /*VariableDeclaration|Argument*/ >();
  final _mixins = BidirectionalMap<IncludeRule, MixinRule>();
  final _functions = BidirectionalMap<FunctionExpression, FunctionRule>();
  final _getFunctionReferences =
      BidirectionalMap<FunctionExpression, FunctionRule>();

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

  /// Namespaces present within the current stylesheet.
  ///
  /// Note: Unlike the similar property in _ModuleMigrationVisitor, this only
  /// includes namespaces for `@use` rules that already exist within the file.
  /// It doesn't include namespaces for to-be-migrated imports.
  Map<String, Uri> _namespaces;

  ImportCache importCache;

  _ReferenceVisitor(this.importCache);

  /// Constructs a new References object based on the stylesheet at [entrypoint]
  /// and its dependencies.
  References build(Uri entrypoint) {
    var stylesheet = getStylesheet(entrypoint);
    _scope = Scope();
    _moduleScopes[stylesheet.span.sourceUrl] = _scope;
    visitStylesheet(stylesheet);
    return References._(
        UnmodifiableBidirectionalMapView(_variables),
        UnmodifiableBidirectionalMapView(_variableReassignments),
        UnmodifiableBidirectionalMapView(_mixins),
        UnmodifiableBidirectionalMapView(_functions),
        UnmodifiableBidirectionalMapView(_getFunctionReferences));
  }

  /// Returns the stylesheet at [url].
  ///
  /// This reuses the stylesheet if it's already been parsed.
  Stylesheet getStylesheet(Uri url) => importCache.import(url)?.item2;

  /// Visits a stylesheet with an empty [_namespaces], storing it in
  /// [_references].
  @override
  void visitStylesheet(Stylesheet node) {
    var _oldNamespaces = _namespaces;
    _namespaces = {};
    super.visitStylesheet(node);
    _namespaces = _oldNamespaces;
  }

  /// Visits the stylesheet this `@import` rule points to using the existing global
  /// scope.
  @override
  void visitImportRule(ImportRule node) {
    super.visitImportRule(node);
    for (var import in node.imports) {
      if (import is DynamicImport) {
        var url = node.span.sourceUrl.resolveUri(Uri.parse(import.url));
        var stylesheet = getStylesheet(url);
        if (stylesheet != null) visitStylesheet(stylesheet);
      }
    }
  }

  /// Visits the stylesheet this `@use` rule points to using a new global scope
  /// for this module.
  @override
  void visitUseRule(UseRule node) {
    super.visitUseRule(node);
    var url = node.span.sourceUrl.resolveUri(node.url);
    var stylesheet = getStylesheet(url);
    if (stylesheet == null) return;
    var canonicalUrl = stylesheet.span.sourceUrl;
    if (!_moduleScopes.containsKey(canonicalUrl)) {
      _scope = Scope();
      _moduleScopes[canonicalUrl] = _scope;
      visitStylesheet(stylesheet);
    }
    var namespace = namespaceForPath(node.url.path);
    _namespaces[namespace] = canonicalUrl;
  }

  /// Visits each of [node]'s expressions and children.
  ///
  /// All of [node]'s arguments are declared as local variables in a new scope.
  @override
  void visitCallableDeclaration(CallableDeclaration node) {
    _scope = Scope(_scope);
    for (var argument in node.arguments.arguments) {
      _scope.variables[argument.name] = argument;
      if (argument.defaultValue != null) visitExpression(argument.defaultValue);
    }
    super.visitChildren(node);
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
    _scope = _scope.parent;
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
    var scope = _scopeForNamespace(node.namespace);
    var previous = scope.variables[node.name];
    scope.variables[node.name] = node;
    var original = _variableReassignments[previous] ?? previous;
    _variableReassignments[node] = original;
    super.visitVariableDeclaration(node);
  }

  /// Visits the variable reference in [node], storing it.
  @override
  void visitVariableExpression(VariableExpression node) {
    var declaration =
        _scopeForNamespace(node.namespace).findVariable(node.name);
    if (declaration != null) {
      _variables[node] = declaration;
    }
    super.visitVariableExpression(node);
  }

  /// Declares a mixin in the current scope.
  @override
  void visitMixinRule(MixinRule node) {
    _scope.mixins[node.name] = node;
    super.visitMixinRule(node);
  }

  /// Visits an `@include` rule, storing the mixin reference.
  @override
  void visitIncludeRule(IncludeRule node) {
    var declaration = _scopeForNamespace(node.namespace).findMixin(node.name);
    if (declaration != null) {
      _mixins[node] = declaration;
      super.visitIncludeRule(node);
    }
  }

  /// Declares a function in the current scope.
  @override
  void visitFunctionRule(FunctionRule node) {
    _scope.functions[node.name] = node;
    super.visitFunctionRule(node);
  }

  /// Visits a function call, storing it if it is a user-defined function.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.name.asPlain == null) return;

    var declaration =
        _scopeForNamespace(node.namespace).findFunction(node.name.asPlain);
    if (declaration != null) {
      _functions[node] = declaration;
      return;
    }

    /// Check for static reference within a get-function call.
    var nameExpression = getStaticNameForGetFunctionCall(node);
    if (nameExpression == null) return;
    var moduleExpression = getStaticModuleForGetFunctionCall(node);
    var namespace = moduleExpression?.text;
    declaration =
        _scopeForNamespace(namespace).findFunction(nameExpression.text);
    if (declaration != null) {
      _getFunctionReferences[node] = declaration;
    }
  }
}
