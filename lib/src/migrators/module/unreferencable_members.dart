// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';

import '../../util/member_declaration.dart';
import 'unreferencable_type.dart';

/// Tracks members that are unreferencable in the current scope.
class UnreferencableMembers {
  /// The parent scope of this instance.
  final UnreferencableMembers? parent;

  /// The members marked as unreferencable in this scope directly.
  final _unreferencable = <MemberDeclaration, UnreferencableType>{};

  UnreferencableMembers([this.parent]);

  /// Marks [declaration] as unreferencable with the given [type].
  void add(MemberDeclaration declaration, UnreferencableType type) {
    _unreferencable[declaration] = type;
  }

  /// Checks whether [declaration] is marked as unreferencable within this
  /// scope or any ancestor scope and throws an appropriate exception if it is.
  void check(MemberDeclaration declaration, SassNode reference) {
    var type = _unreferencable[declaration];
    if (type != null) throw type.toException(reference, declaration.sourceUrl);
    parent?.check(declaration, reference);
  }
}
