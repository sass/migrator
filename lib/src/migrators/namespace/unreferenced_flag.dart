// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';

/// An enum of values for the --unreferenced option.
@sealed
class UnreferencedFlag {
  /// Rename only conflicting unreferenced `@use` rules to `_unreferenced#`.
  static const conflicting = UnreferencedFlag._('conflicting');

  /// Rename all unreferenced `@use` rules to `_unreferenced#`.
  static const all = UnreferencedFlag._('all');

  /// Handle unreferenced `@use` rules the same as referenced `@use` rules.
  static const none = UnreferencedFlag._('none');

  /// Identifier for this value.
  final String id;

  const UnreferencedFlag._(this.id);

  factory UnreferencedFlag(String option) {
    switch (option) {
      case 'conflicting':
        return UnreferencedFlag.conflicting;
      case 'all':
        return UnreferencedFlag.all;
      case 'none':
        return UnreferencedFlag.none;
      default:
        throw StateError(
            'Invalid value "${option}" for --unreferenced option.');
    }
  }
}
