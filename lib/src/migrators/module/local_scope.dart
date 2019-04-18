// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/src/utils.dart';

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class LocalScope {
  /// The parent of this scope, or null if this scope is only nested one level
  /// from the root of the file.
  final LocalScope parent;

  /// Variables defined in this scope.
  final variables = normalizedSet();

  /// Mixins defined in this scope.
  final mixins = normalizedSet();

  /// Functions defined in this scope.
  final functions = normalizedSet();

  LocalScope(this.parent);

  /// Returns whether a variable [name] exists somewhere within this scope.
  bool isLocalVariable(String name) =>
      variables.contains(name) || (parent?.isLocalVariable(name) ?? false);

  /// Returns whether a mixin [name] exists somewhere within this scope.
  bool isLocalMixin(String name) =>
      variables.contains(name) || (parent?.isLocalMixin(name) ?? false);

  /// Returns whether a function [name] exists somewhere within this scope.
  bool isLocalFunction(String name) =>
      variables.contains(name) || (parent?.isLocalFunction(name) ?? false);
}
