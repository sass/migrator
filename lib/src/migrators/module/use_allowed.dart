// Copyright 2025 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';

/// An enum of potential states for whether unnested `@import`s at the current
/// point in the file can be migrated.
@sealed
class UseAllowed {
  /// Status when `@use` and `@forward` are allowed at this point in the file.
  static const allowed = UseAllowed._('allowed');

  /// Status when `@use` and `@forward` are not allowed at this point in the
  /// file, but they can be safely hoisted to the top of the file because the
  /// only rules encountered so far are dependency rules (including plain CSS
  /// `@import` rules) and designated safe at rules.
  static const requiresHoist = UseAllowed._('requiresHoist');

  /// Status when `@use` and `@forward` are not allowed at this point in the
  /// file and cannot necessarily be safely hoisted to the top of the file.
  ///
  /// Migrated `@import`s may still be hoisted at this point if they do not
  /// emit any CSS themselves or if `--unsafe-hoist` is passed.
  static const notAllowed = UseAllowed._('notAllowed');

  /// Identifier for this status
  final String id;

  const UseAllowed._(this.id);

  /// Returns [requiresHoist] unless [this] is already [notAllowed], in which
  /// case it should remain [notAllowed].
  UseAllowed lowerToRequiresHoist() =>
      switch (this) { notAllowed => notAllowed, _ => requiresHoist };

  /// Returns true when `@import` rules can be migrated in place in this state.
  bool get canMigrateInPlace => this == allowed;

  /// Returns true when all `@import` rules can be safely hoisted in this state.
  bool get canAlwaysSafelyHoist => this != notAllowed;
}
