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

  /// The name of this member, including all prefixes from `@forward` rules.
  ///
  /// For variables, this does not include the `$`.
  final String name;

  /// The canonical URL of the nearest non-import-only module from which this
  /// member was loaded.
  ///
  /// * For a member that wasn't forwarded, this is the URL the member was
  ///   declared in.
  ///
  /// * For a member forwarded from a non-import-only module, this is that
  ///   module's URL.
  ///
  /// * For a member loaded from an import-only module, this is the URL of the
  ///   first non-import-only module in its chain of forwards.
  final Uri sourceUrl;

  /// Whether this member declaration was loaded through a `@forward` rule,
  /// including via an import-only file.
  bool get isForwarded => sourceUrl != member.span.sourceUrl;

  /// Creates a MemberDefinition for a [member] that was loaded from the same
  /// module it was defined.
  ///
  /// The [member] must be a [VariableDeclaration], [Argument], [MixinRule], or
  /// [FunctionRule].
  MemberDeclaration(T member)
      : this._(member, () {
          if (member is VariableDeclaration) return member.name;
          if (member is Argument) return member.name;
          if (member is MixinRule) return member.name;
          if (member is FunctionRule) return member.name;
          throw ArgumentError(
              "MemberDefinition must contain a VariableDeclaration, Argument, "
              "MixinRule, or FunctionRule");
        }(), member.span.sourceUrl);

  /// Creates a MemberDefinition for a member that was forwarded through at
  /// least one non-import-only module.
  ///
  /// The [forwarded] member is the member loaded by [forward].
  ///
  /// The [member] must be a [VariableDeclaration], [Argument], [MixinRule], or
  /// [FunctionRule].
  ///
  /// If [forward] comes from an import-only file, this returns an
  /// [ImportOnlyMemberDeclaration].
  factory MemberDeclaration.forward(
          MemberDeclaration<T> forwarded, ForwardRule forward) =>
      isImportOnlyFile(forward.span.sourceUrl)
          ? ImportOnlyMemberDeclaration._(forwarded, forward)
          : MemberDeclaration._(
              forwarded.member,
              '${forward.prefix ?? ""}${forwarded.name}',
              forward.span.sourceUrl);

  MemberDeclaration._(this.member, this.name, this.sourceUrl);

  operator ==(other) =>
      other is MemberDeclaration &&
      member == other.member &&
      name == other.name &&
      sourceUrl == other.sourceUrl;

  int get hashCode => member.hashCode ^ name.hashCode ^ sourceUrl.hashCode;

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
    return buffer.toString();
  }
}

/// A declaration for a member forwarded through an import-only file.
class ImportOnlyMemberDeclaration<T extends SassNode>
    extends MemberDeclaration<T> {
  /// The prefix added to [name] by forwards through import-only files.
  final String importOnlyPrefix;

  /// The canonical URL of the outermost import-only module that forwarded this
  /// member.
  final Uri importOnlyUrl;

  bool get isForwarded => true;

  /// Constructs a forwarded MemberDefinition of [forwarding] based on
  /// [forward].
  ImportOnlyMemberDeclaration._(
      MemberDeclaration<T> forwarded, ForwardRule forward)
      : importOnlyPrefix = (forward.prefix ?? "") +
            (forwarded is ImportOnlyMemberDeclaration<T>
                ? forwarded.importOnlyPrefix
                : ""),
        importOnlyUrl = forward.span.sourceUrl,
        super._(forwarded.member, '${forward.prefix ?? ""}${forwarded.name}',
            forwarded.sourceUrl) {
    assert(isImportOnlyFile(forward.span.sourceUrl));
  }

  String toString() =>
      "${super.toString()} through ${p.prettyUri(importOnlyUrl)}";
}
