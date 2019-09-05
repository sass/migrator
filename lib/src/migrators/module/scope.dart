// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'unreferencable_type.dart';

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class Scope {
  /// The parent of this scope, or null if this scope is global.
  final Scope parent;

  /// Variables defined in this scope.
  ///
  /// These are usually VariableDeclarations, but can also be Arguments from
  /// a CallableDeclaration.
  final variables = <String, SassNode /*VariableDeclaration|Argument*/ >{};

  /// Mixins defined in this scope.
  final mixins = <String, MixinRule>{};

  /// Functions defined in this scope.
  final functions = <String, FunctionRule>{};

  /// Members within this scope that cannot be referenced.
  ///
  /// This is used to track local variables from an upstream stylesheet in a
  /// nested import and global variables from the nested import in the upstream
  /// stylesheet.
  final unreferencableMembers = <
      SassNode /*VariableDeclaration|Argument|MixinRule|FunctionRule*/,
      UnreferencableType>{};

  Scope([this.parent]);

  /// The global scope this scope descends from.
  Scope get global => parent?.global ?? this;

  /// Returns true if this scope is global, and false otherwise.
  bool get isGlobal => parent == null;

  /// Returns whether a variable [name] exists in a non-global scope.
  bool isLocalVariable(String name) =>
      parent != null &&
      (variables.containsKey(name) || parent.isLocalVariable(name));

  /// Returns whether a mixin [name] exists in a non-global scope.
  bool isLocalMixin(String name) =>
      parent != null && (mixins.containsKey(name) || parent.isLocalMixin(name));

  /// Returns whether a function [name] exists in a non-global scope.
  bool isLocalFunction(String name) =>
      parent != null &&
      (functions.containsKey(name) || parent.isLocalFunction(name));

  /// Returns the declaration of a variable named [name] if it exists, or null
  /// if it does not.
  SassNode findVariable(String name) =>
      variables[name] ?? parent?.findVariable(name);

  /// Returns the declaration of a mixin named [name] if it exists, or null if
  /// it does not.
  MixinRule findMixin(String name) => mixins[name] ?? parent?.findMixin(name);

  /// Returns the declaration of a function named [name] if it exists, or null
  /// if it does not.
  FunctionRule findFunction(String name) =>
      functions[name] ?? parent?.findFunction(name);

  /// Checks whether a reference to a variable, mixin, or function is invalid,
  /// throwing a MigrationException if it is.
  ///
  /// [findDeclaration] should return the declaration in the current scope for
  /// the reference if it exists, or null if it does not.
  void _checkUnreferencable(
      SassNode reference, SassNode Function(Scope) findDeclaration) {
    var declaration = findDeclaration(this);
    if (declaration == null) {
      parent?._checkUnreferencable(reference, findDeclaration);
      return;
    }
    if (unreferencableMembers.containsKey(declaration)) {
      throw unreferencableMembers[declaration]
          .toException(reference, declaration.span.sourceUrl);
    }
  }

  /// Checks whether [node] is a valid reference, throwing a MigrationException
  /// if it's not.
  void checkUnreferencableVariable(VariableExpression node) {
    _checkUnreferencable(node, (scope) => scope.variables[node.name]);
  }

  /// Checks whether [node] is a valid reference, throwing a MigrationException
  /// if it's not.
  void checkUnreferencableMixin(IncludeRule node) {
    _checkUnreferencable(node, (scope) => scope.mixins[node.name]);
  }

  /// Checks whether [node] is a valid reference, throwing a MigrationException
  /// if it's not.
  void checkUnreferencableFunction(FunctionExpression node) {
    if (node.name.asPlain == null) return;
    _checkUnreferencable(node, (scope) => scope.functions[node.name.asPlain]);
  }

  /// Copys all members (direct and indirect) of this scope to a new, flattened
  /// scope with all local members marked as unreferencable.
  Scope copyForNestedImport() {
    var flattened = Scope();
    var current = this;
    while (current != null) {
      flattened.unreferencableMembers.addAll(current.unreferencableMembers);
      flattened.addAllMembers(current,
          unreferencable: current.parent == null
              ? null
              : UnreferencableType.localFromImporter);
      current = current.parent;
    }
    return flattened;
  }

  /// Adds all direct members of [other] into this scope.
  ///
  /// If [unreferencable] is passed, this also adds these members to
  /// [unreferencableMembers] with this type.
  void addAllMembers(Scope other, {UnreferencableType unreferencable}) {
    variables.addAll(other.variables);
    mixins.addAll(other.mixins);
    functions.addAll(other.functions);
    if (unreferencable != null) {
      unreferencableMembers.addAll({
        for (var variable in other.variables.values) variable: unreferencable,
        for (var mixinRule in other.mixins.values) mixinRule: unreferencable,
        for (var function in other.functions.values) function: unreferencable
      });
    }
  }
}
