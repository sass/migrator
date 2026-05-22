// Copyright 2026 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:charcode/charcode.dart';
import 'package:sass_api/sass_api.dart';

/// A utility for serializing Sass expressions while adding or changing
/// namespaces of Sass references.
class NamespacedSerializer {
  /// Called on every [SassReference] encountered during serialization, this
  /// should return the namespace that should be used for this reference, or
  /// null if the reference should be unnamespaced.
  final String? Function(SassReference reference) namespacer;

  NamespacedSerializer(this.namespacer);

  /// Serializes an expression.
  String serialize(Expression expression) {
    var namespacePrefix = '';
    if (expression case SassReference ref) {
      var namespace = namespacer(ref);
      if (namespace != null) namespacePrefix = '$namespace.';
    }
    return namespacePrefix +
        switch (expression) {
          BinaryOperationExpression(:var left, :var operator, :var right) =>
            _serializeBinaryOperation(left, operator, right),
          FunctionExpression(:var name, :var arguments) =>
            '$name(${serializeArgumentList(arguments)})',
          IfExpression(:var branches) => _serializeIfExpression(branches),
          InterpolatedFunctionExpression(:var name, :var arguments) =>
            '${serializeInterpolation(name)}'
                '(${serializeArgumentList(arguments)})',
          LegacyIfExpression(:var arguments) =>
            'if(${serializeArgumentList(arguments)})',
          ListExpression(:var contents, :var hasBrackets, :var separator) =>
            (hasBrackets ? '[' : '') +
                [for (var item in contents) serialize(item)].join(
                  switch (separator) {
                    .comma => ', ',
                    .space => ' ',
                    .slash => ' / ',
                    .undecided => ' ',
                  },
                ) +
                (hasBrackets ? ']' : ''),
          VariableExpression(:var name) => '\$$name',
          MapExpression(:var pairs) =>
            '(' +
                [
                  for (var (key, value) in pairs)
                    '${serialize(key)}: ${serialize(value)}',
                ].join(', ') +
                ')',
          ParenthesizedExpression(:var expression) =>
            '(${serialize(expression)})',
          StringExpression(:var text, hasQuotes: false) =>
            serializeInterpolation(text),
          StringExpression(:var text, hasQuotes: true) =>
            '"${serializeInterpolation(text)}"',
          UnaryOperationExpression(:var operator, :var operand) =>
            _serializeUnaryOperation(operator, operand),
          _ => expression.toString(),
        };
  }

  /// Serializes a binary operation, copying the logic for when parentheses
  /// are needed from `BinaryOperationExpression.toString()`.
  String _serializeBinaryOperation(
    Expression left,
    BinaryOperator operator,
    Expression right,
  ) {
    var buffer = StringBuffer();
    var leftNeedsParens = switch (left) {
      BinaryOperationExpression(operator: BinaryOperator(:var precedence)) =>
        precedence < operator.precedence,
      ListExpression(hasBrackets: false, contents: [_, _, ...]) => true,
      _ => false,
    };
    if (leftNeedsParens) buffer.writeCharCode($lparen);
    buffer.write(serialize(left));
    if (leftNeedsParens) buffer.writeCharCode($rparen);

    buffer.writeCharCode($space);
    buffer.write(operator.operator);
    buffer.writeCharCode($space);

    var rightNeedsParens = switch (right) {
      BinaryOperationExpression(operator: var rightOperator) =>
        rightOperator.precedence <= operator.precedence &&
            !(rightOperator == operator && rightOperator.isAssociative),
      ListExpression(hasBrackets: false, contents: [_, _, ...]) => true,
      _ => false,
    };
    if (rightNeedsParens) buffer.writeCharCode($lparen);
    buffer.write(serialize(right));
    if (rightNeedsParens) buffer.writeCharCode($rparen);

    return buffer.toString();
  }

  /// Serializes a unary operation, copying the logic for when parentheses
  /// are needed from `UnaryOperationExpression.toString()`.
  String _serializeUnaryOperation(UnaryOperator operator, Expression operand) {
    var buffer = StringBuffer(operator.operator);
    if (operator == UnaryOperator.not) buffer.writeCharCode($space);
    var needsParens = switch (operand) {
      BinaryOperationExpression() ||
      UnaryOperationExpression() ||
      ListExpression(hasBrackets: false, contents: [_, _, ...]) => true,
      _ => false,
    };
    if (needsParens) buffer.write($lparen);
    buffer.write(serialize(operand));
    if (needsParens) buffer.write($rparen);
    return buffer.toString();
  }

  /// Serializes an if expression, copying the logic from
  /// `IfExpression.toString()`.
  String _serializeIfExpression(
    List<(IfConditionExpression?, Expression)> branches,
  ) {
    var buffer = StringBuffer("if(");
    var first = true;
    for (var (condition, expression) in branches) {
      if (first) {
        first = false;
      } else {
        buffer.write("; ");
      }
      buffer.write(_serializeIfCondition(condition));
      buffer.write(": ");
      buffer.write(serialize(expression));
    }
    buffer.writeCharCode($rparen);
    return buffer.toString();
  }

  /// Serializes a single if condition.
  String _serializeIfCondition(
    IfConditionExpression? condition,
  ) => switch (condition) {
    null => 'else',
    IfConditionParenthesized(:var expression) =>
      '(${_serializeIfCondition(expression)})',
    IfConditionNegation(:var expression) =>
      'not ${_serializeIfCondition(expression)}',
    IfConditionOperation(:var expressions, :var op) =>
      expressions.map(_serializeIfCondition).join(' $op '),
    IfConditionFunction(:var name, :var arguments) =>
      '${serializeInterpolation(name)}(${serializeInterpolation(arguments)})',
    IfConditionSass(:var expression) => 'sass(${serialize(expression)})',
    IfConditionRaw(:var text) => serializeInterpolation(text),
  };

  /// Serializes an interpolation.
  String serializeInterpolation(Interpolation interpolation) => [
    for (var item in interpolation.contents)
      switch (item) {
        Expression expr => '#{${serialize(expr)}}',
        _ => item.toString(),
      },
  ].join();

  /// Serializes an argument list.
  String serializeArgumentList(ArgumentList arguments) => [
    for (var arg in arguments.positional) _parenthesizeArgument(arg),
    for (var MapEntry(key: parameter, value: arg) in arguments.named.entries)
      '\$$parameter: ${_parenthesizeArgument(arg)}',
    if (arguments.rest case var rest?) "${_parenthesizeArgument(rest)}...",
    if (arguments.keywordRest case var keywordRest?)
      "${_parenthesizeArgument(keywordRest)}...",
  ].join(', ');

  /// Wraps [argument] in parentheses if necessary.
  ///
  /// Copied from [ArgumentList].
  String _parenthesizeArgument(Expression argument) => switch (argument) {
    ListExpression(
      separator: ListSeparator.comma,
      hasBrackets: false,
      contents: [_, _, ...],
    ) =>
      "(${serialize(argument)})",
    _ => serialize(argument),
  };
}
