// Copyright 2025 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';
import 'package:source_span/source_span.dart';

import '../patch.dart';
import '../utils.dart';

/// Interprets [arguments] as a call to [parameters] and returns the parameters
/// in positional order even if they were passed by name.
///
/// [ParameterList.restParameter] may not be defined.
GetArgumentsResult getArguments(
    ParameterList parameters, ArgumentList arguments) {
  if (parameters.restParameter != null) {
    throw new ArgumentError("parameters.restParameter is not supported");
  } else if (arguments.rest != null) {
    return GetArgumentsNotResolvable._();
  }

  var results = <GetArgumentArgument>[];
  var namedArgs = {...arguments.named};
  for (var i = 0; i < parameters.parameters.length; i++) {
    var parameter = parameters.parameters[i];
    if (arguments.positional.length > i) {
      var arg = arguments.positional[i];
      results.add(
          GetArgumentArgument._(arg, arg.span, GetArgumentType.positional));
    } else if (namedArgs.remove(parameter.name) case var arg?) {
      results.add(GetArgumentArgument._(
          arg, arguments.namedSpans[parameter.name]!, GetArgumentType.named));
    } else if (parameter.defaultValue case var arg?) {
      results.add(GetArgumentArgument._(
          arg, parameter.span, GetArgumentType.defaultArg));
    } else {
      return GetArgumentsInvalidCall._(
          arguments.span, "missing argument \$${parameter.name}");
    }
  }

  if (namedArgs.isNotEmpty) {
    return GetArgumentsInvalidCall._(
        namedArgs.values.first.span, "unused argument");
  } else {
    return GetArgumentsArguments._(results);
  }
}

/// An algebraic type used as the return value of [getArguments].
sealed class GetArgumentsResult {}

/// The call doesn't match the given parameters.
class GetArgumentsInvalidCall extends GetArgumentsResult {
  /// The span of the first invalid argument.
  final FileSpan span;

  /// A description of what's invalid.
  final String description;

  GetArgumentsInvalidCall._(this.span, this.description);
}

/// The call may be valid, but can't be resolved statically (for example because
/// it involves rest arguments).
class GetArgumentsNotResolvable extends GetArgumentsResult {
  GetArgumentsNotResolvable._();
}

/// The call is valid.
class GetArgumentsArguments extends GetArgumentsResult {
  /// The list of arguments in positional order.
  ///
  /// This is guaranteed to be the same length as [ParameterList.parameters].
  final List<GetArgumentArgument> arguments;

  /// Whether the arguments were passed in the canonical, positional order.
  final bool inOrder;

  GetArgumentsArguments._(this.arguments) : inOrder = _isInOrder(arguments);

  /// Returns whether each non-default argument in [arguments] appears in the
  /// normal positional order.
  static bool _isInOrder(List<GetArgumentArgument> arguments) {
    GetArgumentArgument? last;
    for (var argument in arguments) {
      if (argument.type == GetArgumentType.defaultArg) continue;
      if (last != null && last.span.end.offset > argument.span.start.offset) {
        return false;
      }
      last = argument;
    }
    return true;
  }
}

/// The types of argument that a [GetArgumentArgument] can represent.
enum GetArgumentType {
  /// An argument passed by position.
  positional,

  /// An argument passed by name.
  named,

  /// A default argument value.
  defaultArg,
}

/// Metadata about a particular argument returned by [getArgument].
class GetArgumentArgument {
  /// The value of the argument.
  final Expression argument;

  /// The argument's span, _including_ the name if it was passed by name (or is
  /// a default argument).
  final FileSpan span;

  /// The type of argument this represents.
  final GetArgumentType type;

  GetArgumentArgument._(this.argument, this.span, this.type);

  /// If this is a named argument, returns a [Patch] that removes its argument name.
  Patch? patchOutName() => type == GetArgumentType.named
      ? Patch(span.before(argument.span), '')
      : null;
}
