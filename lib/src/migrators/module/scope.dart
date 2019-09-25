// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'member_declaration.dart';

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class Scope {
  /// The parent of this scope, or null if this scope is global.
  final Scope parent;

  /// Variables defined in this scope.
  ///
  /// These are usually VariableDeclarations, but can also be Arguments from
  /// a CallableDeclaration.
  final variables =
      <String, MemberDeclaration<SassNode /*VariableDeclaration|Argument*/ >>{};

  /// Mixins defined in this scope.
  final mixins = <String, MemberDeclaration<MixinRule>>{};

  /// Functions defined in this scope.
  final functions = <String, MemberDeclaration<FunctionRule>>{};

  Scope([this.parent]);

  /// The global scope this scope descends from.
  Scope get global => parent?.global ?? this;

  /// Returns true if this scope is global, and false otherwise.
  bool get isGlobal => parent == null;

  /// Returns true if this scope is [ancestor] or one of its descendents.
  bool isDescendentOf(Scope ancestor) =>
      this == ancestor || (parent?.isDescendentOf(ancestor) ?? false);

  /// Returns the declaration of a variable named [name] if it exists, or null
  /// if it does not.
  MemberDeclaration findVariable(String name) =>
      variables[name] ?? parent?.findVariable(name);

  /// Returns the declaration of a mixin named [name] if it exists, or null if
  /// it does not.
  MemberDeclaration<MixinRule> findMixin(String name) =>
      mixins[name] ?? parent?.findMixin(name);

  /// Returns the declaration of a function named [name] if it exists, or null
  /// if it does not.
  MemberDeclaration<FunctionRule> findFunction(String name) =>
      functions[name] ?? parent?.findFunction(name);
}
