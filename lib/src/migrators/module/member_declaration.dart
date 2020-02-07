// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:path/path.dart' as p;

import '../../utils.dart';

/// A wrapper class for nodes that declare a variable, function, or mixin.
///
/// The member this class wraps will always be a [VariableDeclaration],
/// an [Argument], a [MixinRule], or a [FunctionRule].
class MemberDeclaration<T extends SassNode> {
  /// The original definition of the member, after all `@forward` rules have
  /// been resolved.
  final T member;

  /// The outermost `@forward` rule through which this member was loaded, or
  /// `null` if it wasn't forwarded.
  final ForwardRule forward;

  /// The name of this member, including all prefixes from `@forward` rules.
  ///
  /// For variables, this does not include the `$`.
  final String name;

  /// The URL this member came from.
  ///
  /// For un-forwarded members, this is the URL the member was declared in. For
  /// members forwarded through an import-only file, this is the [sourceUrl] of
  /// the member prior to that forward. For other forwarded members, this is the
  /// URL of the `@forward` rule.
  final Uri sourceUrl;

  /// The canonical URL forwarded by [forward].
  ///
  /// This is `null` when [forward] is.
  final Uri forwardedUrl;

  /// The canonical URL of the import-only stylesheet in which this member was
  /// forwarded.
  ///
  /// This is `null` when this member wasn't loaded through an import-only
  /// stylesheet.
  final Uri importOnlyUrl;

  /// True if this declaration is the result of a `@forward` rule within an
  /// import-only stylesheet.
  bool get isImportOnly => importOnlyUrl != null;

  /// Constructs a MemberDefinition for [member], which must be a
  /// [VariableDeclaration], [Argument], [MixinRule], or [FunctionRule].
  MemberDeclaration(this.member)
      : name = (() {
          if (member is VariableDeclaration) return member.name;
          if (member is Argument) return member.name;
          if (member is MixinRule) return member.name;
          if (member is FunctionRule) return member.name;
          throw ArgumentError(
              "MemberDefinition must contain a VariableDeclaration, Argument, "
              "MixinRule, or FunctionRule");
        })(),
        sourceUrl = member.span.sourceUrl,
        forward = null,
        forwardedUrl = null,
        importOnlyUrl = null;

  /// Constructs a forwarded MemberDefinition of [forwarding] based on
  /// [forward].
  MemberDeclaration.forward(
      MemberDeclaration forwarding, this.forward, this.forwardedUrl)
      : member = forwarding.member,
        name = '${forward.prefix ?? ""}${forwarding.name}',
        sourceUrl = isImportOnlyFile(forward.span.sourceUrl)
            ? forwarding.sourceUrl
            : forward.span.sourceUrl,
        importOnlyUrl = isImportOnlyFile(forward.span.sourceUrl)
            ? forward.span.sourceUrl
            : null;

  operator ==(other) =>
      other is MemberDeclaration &&
      member == other.member &&
      forward == other.forward;

  int get hashCode => member.hashCode;

  String toString() {
    var buffer = StringBuffer();
    if (member is MixinRule) {
      buffer.write("@mixin ");
    } else if (member is FunctionRule) {
      buffer.write("@function ");
    } else {
      buffer.write("\$");
    }
    buffer.write("$name from ${p.prettyUri(sourceUrl)}");

    if (forwardedUrl != null) {
      buffer.write(" forwarded from ${p.prettyUri(forwardedUrl)}");
    } else if (isImportOnly) {
      buffer.write(" forwarded in import-only");
    }
    return buffer.toString();
  }
}
