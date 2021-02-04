// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.
import 'package:charcode/charcode.dart';

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
/// the matcher clause, and theoutput clause.
///
/// The key clause specifies which key to match on. If no key is provided,
/// the default key is assumed.
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
/// Each statement can use one of two syntaxes: a sed-style one and a more
/// readable, space-separated one.
///
/// The sed-style syntax looks like `key/matcher/output/`. In place of `/`, you
/// can instead use `=`, `~`, `!`, `@`, "`", `%`, `&`, or `:` as the delimiter.
/// If your chosen delimiter needs to appear within `matcher` or `output`, it
/// must be escaped with `\` (or just choose a different delimiter). If you
/// choose the omit the key clause, you must still include the delimiter after
/// it, so `/matcher/output/` is valid syntax, but `matcher/output/` is not.
///
/// The more readable syntax looks like `key matcher to output`. In place of
/// the `to` keyword, you may instead use `->`. In this syntax, when you omit
/// the key clause, you also omit the trailing space (e.g. `matcher -> output`).
/// Clauses must always be separated by a single space. If you need to include
/// a literal space in `matcher` or `output`, you may escape it as `\ `, or you
/// may opt to just use the sed-style syntax.
class Renamer<T> {
  final String defaultKey;

  final Map<String, String Function(T input)> keys;

  final List<_Statement<T>> _statements;

  Renamer._(this.defaultKey, this.keys, this._statements);

  /// Runs this renamer based on [input].
  String rename(T input) {
    for (var statement in _statements) {
      var result = statement.rename(input);
      if (result != null) return result;
    }
    return null;
  }

  /// Creates a simple Renamer with a single key.
  static Renamer<String> simple(String code, {String keyName = 's'}) {
    return Renamer(code, keyName, {keyName: (input) => input});
  }

  /// Creates a Renamer for a map of strings.
  ///
  /// The first item in [keys] is the default key.
  static Renamer<Map<String, String>> map(String code, List<String> keys) {
    return Renamer(
        code, keys.first, {for (var key in keys) key: (input) => input[key]});
  }

  /// Creates a Renamer based on [code], a [defaultKey], and a map from keys to
  /// functions that take an input and return a string.
  ///
  /// [defaultKey] must be one of the keys in [keys], and all keys must consist
  /// of only lowercase letters.
  factory Renamer(String code, String defaultKey,
      Map<String, String Function(T input)> keys) {
    for (var key in keys.keys) {
      if (!RegExp(r'^[a-z]+$').hasMatch(key)) {
        throw FormatException(
            'Invalid key "$key". Must use only lowercase letters.');
      }
    }
    if (!keys.containsKey(defaultKey)) {
      throw FormatException("Default key not present in keys.");
    }
    // Break code into statements by line breaks or semicolons, but ignore
    // escaped delimiters.
    var statements = <String>[];
    var current = '';
    var i = 0;
    while (true) {
      var nextDelim = code.indexOf(RegExp(r'\n|;'), i);
      if (nextDelim == -1) {
        current += code.substring(i);
        break;
      }
      if (code.codeUnitAt(nextDelim - 1) == $backslash) {
        current += code.substring(i, nextDelim + 1);
      } else {
        current += code.substring(i, nextDelim);
        statements.add(current.trim());
        current = '';
      }
      i = nextDelim + 1;
    }
    if (current.isNotEmpty) statements.add(current.trim());
    return Renamer._(defaultKey, keys, [
      for (var statement in statements)
        if (statement.isNotEmpty) _Statement(statement, defaultKey, keys)
    ]);
  }
}

/// List of delimiters allowed in the sed-style syntax.
const _normalDelimiters = ['/', '=', '~', '!', '@', '`', '%', '&', ':'];

class _Statement<T> {
  /// The key this statement matches on.
  final String Function(T input) key;

  /// The regular expression that matches on key.
  final RegExp matcher;

  /// The output of this statement is constructed from the concatenation of
  /// these components.
  final List<_OutputComponent> output;

  _Statement._(this.key, this.matcher, this.output);

  /// Return the output if this statement matches [input] or null otherwise.
  String rename(T input) {
    var match = matcher.firstMatch(key(input));
    if (match == null) return null;
    return output.map((item) => item.build(match)).join();
  }

  /// Parses a statement based on a line of [code] and the allowed [keys].
  factory _Statement(String code, String defaultKey,
      Map<String, String Function(T input)> keys) {
    // First check for the sed-style syntax for all allowed keys and delimiters.
    var startingMatch =
        RegExp('^(|${keys.keys.join('|')})([${_normalDelimiters.join()}])'
                r'.*\2.*\2')
            .firstMatch(code);
    var key = '';
    String delimiter;
    var cursor = 0;
    if (startingMatch != null) {
      key = startingMatch.group(1);
      delimiter = startingMatch.group(2);
      cursor = key.length + delimiter.length;
    } else {
      // If not sed-style, try the space-separated syntax.
      delimiter = ' ';
      var spaces = ' '.allMatches(code).length - r'\ '.allMatches(code).length;
      // There should be 3 unescaped spaces if a key clause is included or 2
      // if it's not, so anything else should error.
      if (spaces == 3) {
        key = code.substring(0, code.indexOf(' '));
        cursor = key.length + 1;
      } else if (spaces != 2) {
        throw FormatException('Invalid rename "$code"');
      }
    }
    if (key.isEmpty) key = defaultKey;

    // Build the matcher based on all text before the next unescaped delimiter.
    var matcherSrc = '';
    for (; cursor < code.length; cursor++) {
      var char = code[cursor];
      if (char == delimiter) {
        if (code.codeUnitAt(cursor - 1) != $backslash) break;
        matcherSrc = matcherSrc.substring(0, matcherSrc.length - 1);
      }
      matcherSrc += char;
    }
    cursor++;
    var matcher = RegExp('^$matcherSrc\$');

    // The space-separated syntax requires the matcher and output to be
    // separated by `to` or `->`.
    if (delimiter == ' ') {
      if (!code.substring(cursor).startsWith(RegExp('(to|->) '))) {
        throw FormatException(
            'Matcher clause and output clause must be separated by "to" or '
            '"->"');
      }
      cursor += 3;
    }

    // Build the output as a series of literals and backreferences.
    var output = <_OutputComponent>[];
    var current = '';
    var sawBackslash = false;
    for (; cursor < code.length; cursor++) {
      var char = code.codeUnitAt(cursor);
      if (sawBackslash) {
        sawBackslash = false;
        if (char >= $0 && char <= $9) {
          output.add(_Literal(current));
          current = '';
          output.add(_Backreference(char - $0));
        } else {
          current += code[cursor];
        }
      } else if (code[cursor] == delimiter) {
        cursor++;
        break;
      } else if (char == $backslash) {
        sawBackslash = true;
      } else {
        current += code[cursor];
      }
    }
    if (current.isNotEmpty) output.add(_Literal(current));
    if (cursor < code.length) {
      throw FormatException(
          'Extra text "${code.substring(cursor)}" after complete statement');
    }
    return _Statement._(keys[key], matcher, output);
  }
}

abstract class _OutputComponent {
  String build(RegExpMatch match);
}

/// Literal text that's part of a statement's output.
class _Literal extends _OutputComponent {
  final String text;
  _Literal(this.text);

  /// This just returns the literal text of this component.
  String build(match) => text;
}

/// A backreference that's part of a statement's output.
class _Backreference extends _OutputComponent {
  final int number;
  _Backreference(this.number);

  /// Returns the captured group numbered [number] in [match].
  String build(RegExpMatch match) => match.group(number);
}
