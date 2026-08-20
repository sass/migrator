// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';

/// An enum of values for the --forward option.
@sealed
class const ForwardType._(
  /// Identifier for this value.
  final String id,
) {
  /// Forward all members through the entrypoint
  static const all = ForwardType._('all');

  /// Forward formerly prefixed members through the entrypoint
  static const prefixed = ForwardType._('prefixed');

  /// Forward all members through the entrypoint's import-only file.
  static const importOnly = ForwardType._('import-only');

  factory(String option) {
    switch (option) {
      case 'all':
        return ForwardType.all;
      case 'import-only':
        return ForwardType.importOnly;
      case 'prefixed':
        return ForwardType.prefixed;
      default:
        throw StateError('Invalid value "$option" for --forward option.');
    }
  }
}
