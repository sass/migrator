// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.
import 'package:charcode/charcode.dart';
import 'package:string_scanner/string_scanner.dart';

/// Renamer is a small DSL for renaming things.
///
/// To create a Renamer, you provide a piece of code and a map of keys to
/// functions that return some string for each key based on an input.
///
/// To rename, you pass some input to Renamer. It will return a string with the
/// new name if the code provided a match, or null if no match was found for
/// that input.
///
/// The language itself consists of a series of statements separated by
/// semicolons or line breaks. Each statement has 3 clauses: the key clause,
/// the matcher clause, and the output clause.
///
/// The key clause specifies which key to match on. This can be empty to refer
/// to a key that's just the empty string.
///
/// The matcher clause is a regular expression that should match the entirety of
/// the value of that key.
///
/// The output clause is the text that should be returned when the matcher
/// succeeds and may contain references to captured groups in the matcher's
/// regular expression.
///
/// For an input, statements are evaluated in order until a match is found. Once
/// a match is found, its output is returned immediately, bypassing any
/// subsequent statements.
///
/// These clauses are combined as `<key> <matcher> to <output>`. If the key in
/// question is the empty string, you omit that clause, so you get
/// `<matcher> to <output>`.
///
/// If you wish to include a semicolon or space in the matcher or output clause,
/// you can either escape it with `\` or wrap the entire clause in single or
/// double quotes.
class Renamer<T> {
  /// A map from keys to functions that take an input and return the value of
  /// that key for that input.
  final Map<String, String Function(T input)> keys;

  /// The list of statements that are evaluated in order by this renamer.
  final List<_Statement<T>> _statements;

  Renamer._(this.keys, this._statements);

  /// Creates a simple Renamer from [code] that only uses an empty key.
  static Renamer<String> simple(String code) {
    return Renamer(code, {'': (input) => input});
  }

  /// Creates a Renamer from [code] that takes a map from keys to string values
  /// as input.
  ///
  /// [keys] is the list of keys that can be referenced in [code] and must
  /// all appear in every input map.
  static Renamer<Map<String, String>> map(String code, List<String> keys) {
    return Renamer(code, {for (var key in keys) key: (input) => input[key]});
  }

  /// Creates a Renamer based on [code] and a map from keys to functions that
  /// take an input and return a string.
  ///
  /// All keys must consist of only lowercase letters, underscores, and hyphens.
  ///
  /// If provided, [sourceUrl] will appear in parsing errors. It can be
  /// a [String] or a [Uri].
  factory Renamer(String code, Map<String, String Function(T input)> keys,
      {dynamic sourceUrl}) {
    for (var key in keys.keys) {
      if (!RegExp(r'^[a-z_-]*$').hasMatch(key)) {
        throw ArgumentError(
            'Invalid key "$key". Must use only lowercase letters, '
            'underscores, and hyphens.');
      }
    }
    var scanner = StringScanner(code, sourceUrl: sourceUrl);
    var statements = <_Statement<T>>[];
    scanner.scan(_statementDelimiter);
    while (!scanner.isDone) {
      statements.add(_readStatement(scanner, keys));
    }
    return Renamer._(keys, statements);
  }

  /// Reads the next statement (and the trailing delimiter, if any) from
  /// [scanner].
  static _Statement<T> _readStatement<T>(
      StringScanner scanner, Map<String, String Function(T input)> keys) {
    var start = scanner.position;
    FormatException lastException;
    // Tries each key in succession until one is successfully returned.
    for (var entry in keys.entries) {
      try {
        scanner.position = start;
        var statement = _tryKey(scanner, entry.key, entry.value);
        if (statement != null) return statement;
      } on FormatException catch (e) {
        lastException = e;
      }
    }
    if (lastException == null) {
      scanner.error('invalid key');
    }
    throw lastException;
  }

  /// Tries to read a statement for [key] from [scanner].
  ///
  /// If [key] is non-null and the next text in [scanner] is not that key, this
  /// returns null immediately, since the parse error would not be useful.
  ///
  /// Otherwise, after consuming the key clause (if any), attempts to read
  /// the matcher and output clauses, throwing if it's unable to.
  static _Statement<T> _tryKey<T>(
      StringScanner scanner, String key, String Function(T input) keyFunction) {
    if (key.isNotEmpty && !scanner.scan('$key ')) return null;
    var matcher = _readMatcher(scanner);
    scanner.expect(' to ');
    var output = _readOutput(scanner);
    return _Statement(keyFunction, matcher, output);
  }

  /// Reads a matcher clause and its trailing space from [scanner].
  static RegExp _readMatcher(StringScanner scanner) {
    int quote;
    if ({$single_quote, $double_quote}.contains(scanner.peekChar())) {
      quote = scanner.readChar();
    }
    var src = StringBuffer();
    while (true) {
      var char = scanner.peekChar();
      if (quote == null) {
        if (char == $space) break;
        if (char == $semicolon || char == $lf) {
          scanner.error('statement ended unexpectedly');
        }
      }
      scanner.readChar();
      if (char == quote) break;
      if (char == $backslash) {
        var next = scanner.readChar();
        if (next == quote ||
            (quote == null && (next == $semicolon || next == $space))) {
          src.writeCharCode(next);
        } else {
          // If we don't capture the escape here, let regex parser handle it.
          src.writeCharCode($backslash);
          src.writeCharCode(next);
        }
      } else {
        src.writeCharCode(char);
      }
    }
    return RegExp('^$src\$');
  }

  /// Reads an output clause and the statement's trailing delimiter (if any).
  static List<_OutputComponent> _readOutput(StringScanner scanner) {
    int quote;
    if ({$single_quote, $double_quote}.contains(scanner.peekChar())) {
      quote = scanner.readChar();
    }
    var components = <_OutputComponent>[];
    var buffer = StringBuffer();
    while (true) {
      var char = scanner.peekChar();
      if (quote == null && {null, $space, $semicolon, $lf}.contains(char)) {
        break;
      }
      scanner.readChar();
      if (quote != null && char == quote) break;
      if (char == $backslash) {
        var next = scanner.readChar();
        if (next >= $0 && next <= $9) {
          if (buffer.isNotEmpty) components.add(_Literal(buffer.toString()));
          components.add(_Backreference(next - $0));
          buffer.clear();
        } else {
          buffer.writeCharCode(next);
        }
      } else {
        buffer.writeCharCode(char);
      }
    }
    if (buffer.isNotEmpty) components.add(_Literal(buffer.toString()));
    if (!scanner.isDone) {
      scanner.expect(_statementDelimiter, name: 'end of statement');
    }
    return components;
  }

  /// Runs this renamer based on [input].
  String rename(T input) {
    for (var statement in _statements) {
      var result = statement.rename(input);
      if (result != null) return result;
    }
    return null;
  }
}

// Regex that matches at least one line break or semicolon as well as any
// number of spaces in any order.
final _statementDelimiter = RegExp(r' *((\n|;) *)+');

/// A Renamer statement, which defines a single key and regex to match on and
/// the output to return if an input is successfully matched.
class _Statement<T> {
  /// The key this statement matches on.
  final String Function(T input) key;

  /// The regular expression that matches on key.
  final RegExp matcher;

  /// The output of this statement is constructed from the concatenation of
  /// these components.
  final List<_OutputComponent> output;

  _Statement(this.key, this.matcher, this.output);

  /// Return the output if this statement matches [input] or null otherwise.
  String rename(T input) {
    var match = matcher.firstMatch(key(input));
    if (match == null) return null;
    return output.map((item) => item.build(match)).join();
  }
}

/// A component of an output clause.
abstract class _OutputComponent {
  /// When constructing the output, this will be called with the match that
  /// the matcher clause found.
  String build(RegExpMatch match);
}

/// Literal text that's part of a statement's output.
class _Literal extends _OutputComponent {
  final String text;
  _Literal(this.text);

  /// This just returns the literal text of this component.
  String build(RegExpMatch match) => text;
}

/// A backreference that's part of a statement's output.
class _Backreference extends _OutputComponent {
  final int number;
  _Backreference(this.number);

  /// Returns the captured group numbered [number] in [match].
  String build(RegExpMatch match) => match.group(number);
}
