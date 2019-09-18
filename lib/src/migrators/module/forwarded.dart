// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/visitor/interface/statement.dart';

import 'package:source_span/src/file.dart';

/// Interface for forwarded members.
abstract class Forwarded<T extends SassNode> extends SassNode {
  /// The member that this is forwarding.
  final T member;

  /// The `@forward` rule that forwarded this member.
  final ForwardRule forwardRule;

  /// The `@forward` rule's span is used here to indicate that this member
  /// should be treated as if it was declared in the forwarding stylesheet.
  ///
  /// Use [originalSpan] to find the span of the actual member declaration.
  final FileSpan span;

  /// The original span containing this member declaration.
  ///
  /// This differs from [member.span] when a member is forwarded multiple times.
  final FileSpan originalSpan;

  Forwarded._(this.member, this.forwardRule)
      : span = forwardRule.span,
        originalSpan = member is Forwarded ? member.originalSpan : member.span;

  T accept<T>(StatementVisitor<T> visitor) =>
      throw StateError('Forwarded members should not be visited');

  String toString() => "Forwarded($member, ${forwardRule.span.sourceUrl})";
}

/// Implementation of Forwarded<VariableDeclaration>
class ForwardedVariable extends Forwarded<VariableDeclaration>
    implements VariableDeclaration {
  ForwardedVariable(VariableDeclaration member, ForwardRule forwardRule)
      : super._(member, forwardRule);

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
  ForwardedMixin(MixinRule member, ForwardRule forwardRule)
      : super._(member, forwardRule);

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
  ForwardedFunction(FunctionRule member, ForwardRule forwardRule)
      : super._(member, forwardRule);

  ArgumentDeclaration get arguments => member.arguments;
  List<Statement> get children => member.children;
  SilentComment get comment => member.comment;
  bool get hasDeclarations => member.hasDeclarations;
  String get name => member.name;
}
