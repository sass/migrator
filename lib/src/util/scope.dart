// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';

import 'member_declaration.dart';

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class Scope {
  /// The parent of this scope, or null if this scope is global.
  final Scope? parent;

  /// Variables defined in this scope.
  ///
  /// These are usually VariableDeclarations, but can also be Arguments from
  /// a CallableDeclaration.
  final variables = <String, MemberDeclaration>{};

  /// Mixins defined in this scope.
  final mixins = <String, MemberDeclaration<MixinRule>>{};

  /// Functions defined in this scope.
  final functions = <String, MemberDeclaration<FunctionRule>>{};

  Scope([this.parent]);

  /// The global scope this scope descends from.
  Scope get global => parent?.global ?? this;

  /// Returns true if this scope is global, and false otherwise.
  bool get isGlobal => parent == null;

  /// The set of all variable names defined in this scope or its ancestors.
  Set<String> get allVariableNames =>
      {...variables.keys, ...?parent?.allVariableNames};

  /// The set of all mixin names defined in this scope or its ancestors.
  Set<String> get allMixinNames => {...mixins.keys, ...?parent?.allMixinNames};

  /// The set of all function names defined in this scope or its ancestors.
  Set<String> get allFunctionNames =>
      {...functions.keys, ...?parent?.allFunctionNames};

  /// Returns true if this scope is [ancestor] or one of its descendents.
  bool isDescendentOf(Scope ancestor) =>
      this == ancestor || (parent?.isDescendentOf(ancestor) ?? false);

  /// Returns the declaration of a variable named [name] if it exists, or null
  /// if it does not.
  MemberDeclaration? findVariable(String name) =>
      variables[name] ?? parent?.findVariable(name);

  /// Returns the declaration of a mixin named [name] if it exists, or null if
  /// it does not.
  MemberDeclaration<MixinRule>? findMixin(String name) =>
      mixins[name] ?? parent?.findMixin(name);

  /// Returns the declaration of a function named [name] if it exists, or null
  /// if it does not.
  MemberDeclaration<FunctionRule>? findFunction(String name) =>
      functions[name] ?? parent?.findFunction(name);
}
