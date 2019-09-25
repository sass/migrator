// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

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
  /// For un-forwarded members, this is the URL the member was declared in.
  /// For forwarded members, this is the URL of the `@forward` rule.
  final Uri sourceUrl;

  /// The canonical URL forwarded by [forward].
  ///
  /// This is `null` when [forward] is.
  final Uri forwardedUrl;

  /// Constructs a MemberDefinition for [member], which must be a
  /// [VariableDeclaration], [Argument], [MixinRule], or [FunctionRule].
  MemberDeclaration(this.member)
      : name = member is VariableDeclaration
            ? member.name
            : member is Argument
                ? member.name
                : member is MixinRule
                    ? member.name
                    : member is FunctionRule
                        ? member.name
                        : throw ArgumentError("MemberDefinition must contain a "
                            "VariableDeclaration, Argument, MixinRule, or "
                            "FunctionRule"),
        sourceUrl = member.span.sourceUrl,
        forward = null,
        forwardedUrl = null;

  /// Constructs a forwarded MemberDefinition of [forwarding] based on
  /// [forward].
  MemberDeclaration.forward(
      MemberDeclaration forwarding, this.forward, this.forwardedUrl)
      : member = forwarding.member,
        name = '${forward.prefix ?? ""}${forwarding.name}',
        sourceUrl = forward.span.sourceUrl;

  operator ==(other) =>
      other is MemberDeclaration &&
      member == other.member &&
      forward == other.forward;

  int get hashCode => member.hashCode;
}
/*
/// Interface for forwarded members.
abstract class Forwarded<T extends SassNode> extends SassNode {
  /// The member that this is forwarding.
  final T member;

  /// The `@forward` rule that forwarded this member.
  final ForwardRule forwardRule;

  /// The canonical URL of the stylesheet this `@forward` rule loads.
  final Uri sourceUrl;

  /// The `@forward` rule's span is used here to indicate that this member
  /// should be treated as if it was declared in the forwarding stylesheet.
  ///
  /// Use [originalSpan] to find the span of the actual member declaration.
  final FileSpan span;

  /// The original span containing this member declaration.
  ///
  /// This differs from [member.span] when a member is forwarded multiple times.
  final FileSpan originalSpan;

  Forwarded._(this.member, this.forwardRule, this.sourceUrl)
      : span = forwardRule.span,
        originalSpan = member is Forwarded ? member.originalSpan : member.span;

  T accept<T>(StatementVisitor<T> visitor) =>
      throw StateError('Forwarded members should not be visited');

  String toString() => "Forwarded($member, ${forwardRule.span.sourceUrl})";
}

/// Implementation of Forwarded<VariableDeclaration>
class ForwardedVariable extends Forwarded<VariableDeclaration>
    implements VariableDeclaration {
  ForwardedVariable(
      VariableDeclaration member, ForwardRule forwardRule, Uri sourceUrl)
      : super._(member, forwardRule, sourceUrl);

  SilentComment get comment => member.comment;
  void set comment(SilentComment comment) {
    this.comment = comment;
  }

  Expression get expression => member.expression;
  bool get isGlobal => member.isGlobal;
  bool get isGuarded => member.isGuarded;
  String get name => member.name;
  String get namespace => member.namespace;
  String get originalName => member.originalName;
}

/// Implementation of Forwarded<MixinRule>
class ForwardedMixin extends Forwarded<MixinRule> implements MixinRule {
  ForwardedMixin(MixinRule member, ForwardRule forwardRule, Uri sourceUrl)
      : super._(member, forwardRule, sourceUrl);

  ArgumentDeclaration get arguments => member.arguments;
  List<Statement> get children => member.children;
  SilentComment get comment => member.comment;
  bool get hasContent => member.hasContent;
  bool get hasDeclarations => member.hasDeclarations;
  String get name => member.name;
}

/// Implementation of Forwarded<FunctionRule>
class ForwardedFunction extends Forwarded<FunctionRule>
    implements FunctionRule {
  ForwardedFunction(FunctionRule member, ForwardRule forwardRule, Uri sourceUrl)
      : super._(member, forwardRule, sourceUrl);

  ArgumentDeclaration get arguments => member.arguments;
  List<Statement> get children => member.children;
  SilentComment get comment => member.comment;
  bool get hasDeclarations => member.hasDeclarations;
  String get name => member.name;
}
*/
