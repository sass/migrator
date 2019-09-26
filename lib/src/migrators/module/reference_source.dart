// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass_migrator/src/utils.dart';

/// A [ReferenceSource] is used to track where a referenced member came from.
///
/// There are four types of sources:
///
/// - import: For references to members loaded by an `@import` rule.
/// - use: For references to members loaded by a `@use` rule.
/// - built-in: For references to built-in functions that are now part of a
///   built-in module.
/// - current: For references to members declared in the same stylesheet.
class ReferenceSource {
  /// The canonical URL that contains the declaration being referenced.
  final Uri url;

  /// For import sources, the import that loaded the member being referenced.
  ///
  /// Note: This is the import that directly loaded the stylesheet defining
  /// the referenced member, not the immediate import within the referencing
  /// stylesheet.
  ///
  /// For example, if A imports B and B imports C, and a member of C is
  /// referenced in A, than that reference's source should be the import in B
  /// that imports C, not the import in A that imports B.
  final DynamicImport import;

  /// For use sources, the `@use` rule that made the referenced member available
  /// in the referencing stylesheet.
  ///
  /// Note: This is the opposite of how import sources work. If A uses B, and B
  /// imports or forwards C, and a member originally defined in C is referenced
  /// in A, than that reference's source should be the `@use` rule in A that
  /// loads B, not the import or `@forward` rule in B that loads C.
  final UseRule use;

  /// For built-in sources, the name of the built-in module containing the
  /// referenced member.
  ///
  /// This does not include the scheme, so if, for example, the `hue` function
  /// is referenced, this should be `color` and not `sass:color`.
  final String builtIn;

  ReferenceSource._(this.url, {this.import, this.use, this.builtIn});

  /// Constructs a new import source.
  ReferenceSource.import(Uri url, DynamicImport import)
      : this._(url, import: import);

  /// Constructs a new use source.
  ReferenceSource.use(Uri url, UseRule use) : this._(url, use: use);

  /// Constructs a new built-in source.
  ReferenceSource.builtIn(Uri url, String builtIn)
      : this._(url, builtIn: builtIn);

  /// Constructs a new current source.
  ReferenceSource.current(Uri url) : this._(url);

  /// Returns true if this is an import source.
  bool get isImport => import != null;

  /// Returns true if this is a use source.
  bool get isUse => use != null;

  /// Returns true if this is a built-in source.
  bool get isBuiltIn => builtIn != null;

  /// Returns true if this is a current source.
  bool get isCurrent => !isImport && !isUse && !isBuiltIn;

  /// Returns the default namespace for this source, or null if the source
  /// doesn't have a namespace.
  String get defaultNamespace {
    if (builtIn != null) return builtIn;
    if (use != null) return use.namespace;
    if (import != null) return namespaceForPath(import.url);
    return null;
  }

  operator ==(other) =>
      other is ReferenceSource &&
      url == other.url &&
      import == other.import &&
      use == other.use &&
      builtIn == other.builtIn;

  int get hashCode =>
      import?.hashCode ?? use?.hashCode ?? builtIn?.hashCode ?? url.hashCode;
}
