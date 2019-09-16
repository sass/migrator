// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'package:sass_migrator/src/utils.dart';
import 'unreferencable_type.dart';

/// Tracks members that are unreferencable in the current scope.
class UnreferencableMembers {
  final UnreferencableMembers parent;
  final _unreferencable = <SassNode, UnreferencableType>{};

  UnreferencableMembers([this.parent]);

  /// Marks [declaration] as unreferencable with the given [type].
  markUnreferencable(SassNode declaration, UnreferencableType type) {
    _unreferencable[declaration] = type;
  }

  /// Checks whether [declaration] is marked as unreferencable within this
  /// scope or any ancestor scope and throws an appropriate exception if it is.
  checkUnreferencable(SassNode declaration, SassNode reference) {
    if (_unreferencable.containsKey(declaration)) {
      throw _unreferencable[declaration]
          .toException(reference, declaration.span.sourceUrl);
    }
    parent?.checkUnreferencable(declaration, reference);
  }
}
