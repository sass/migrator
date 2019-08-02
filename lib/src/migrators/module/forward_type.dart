// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';

/// An enum of values for the --forward option.
@sealed
class ForwardType {
  /// Forward all members from the entrypoint
  static const all = ForwardType._('all');

  /// Forward all members from the entrypoint
  static const none = ForwardType._('none');

  /// Forward all members from the entrypoint
  static const prefixed = ForwardType._('prefixed');

  /// Identifier for this value.
  final String id;

  const ForwardType._(this.id);

  factory ForwardType(String option) {
    switch (option) {
      case 'all':
        return ForwardType.all;
      case 'none':
        return ForwardType.none;
      case 'prefixed':
        return ForwardType.prefixed;
      default:
        throw StateError('Invalid value "${option}" for --forward option.');
    }
  }
}
