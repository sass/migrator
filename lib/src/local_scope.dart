// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'utils.dart';

class LocalScope {
  /// The parent of this scope, or null if parent is root of file.
  final LocalScope parent;

  /// Variables defined in this scope.
  final Set<String> variables = normalizedSet();

  /// Mixins defined in this scope.
  final Set<String> mixins = normalizedSet();

  /// Functions defined in this scope.
  final Set<String> functions = normalizedSet();

  LocalScope(this.parent);

  bool isLocalVariable(String name) =>
      variables.contains(name) || (parent?.isLocalVariable(name) ?? false);

  bool isLocalMixin(String name) =>
      variables.contains(name) || (parent?.isLocalMixin(name) ?? false);

  bool isLocalFunction(String name) =>
      variables.contains(name) || (parent?.isLocalFunction(name) ?? false);
}
