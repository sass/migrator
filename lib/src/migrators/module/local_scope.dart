// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/src/utils.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class LocalScope {
  /// The parent of this scope, or null if this scope is only nested one level
  /// from the root of the file.
  final LocalScope parent;

  /// Variables defined in this scope.
  final variables = normalizedMap<VariableDeclaration>();

  /// Mixins defined in this scope.
  final mixins = normalizedMap<MixinRule>();

  /// Functions defined in this scope.
  final functions = normalizedMap<FunctionRule>();

  LocalScope(this.parent);

  /// Returns whether a variable [name] exists somewhere within this scope.
  bool isLocalVariable(String name) =>
      variables.containsKey(name) || (parent?.isLocalVariable(name) ?? false);

  /// Returns whether a mixin [name] exists somewhere within this scope.
  bool isLocalMixin(String name) =>
      variables.containsKey(name) || (parent?.isLocalMixin(name) ?? false);

  /// Returns whether a function [name] exists somewhere within this scope.
  bool isLocalFunction(String name) =>
      variables.containsKey(name) || (parent?.isLocalFunction(name) ?? false);
}
