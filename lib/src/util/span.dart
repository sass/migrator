// Copyright 2025 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

import '../utils.dart';

extension ExtendSpan on FileSpan {
  /// Whether this span covers zero characters.
  bool get isEmpty => start == end;

  /// Extends this span so it encompasses any whitespace on either side of it.
  FileSpan extendThroughWhitespace() {
    var text = file.getText(0);

    var newStart = start.offset - 1;
    for (; newStart >= 0; newStart--) {
      if (!isWhitespace(text.codeUnitAt(newStart))) break;
    }

    var newEnd = end.offset;
    for (; newEnd < text.length; newEnd++) {
      if (!isWhitespace(text.codeUnitAt(newEnd))) break;
    }

    // Add 1 to start because it's guaranteed to end on either -1 or a character
    // that's not whitespace.
    return file.span(newStart + 1, newEnd);
  }

  /// Extends this span forward if it's followed by exactly [pattern].
  ///
  /// If it doesn't match, returns the span as-is.
  FileSpan extendIfMatches(Pattern pattern) {
    var text = file.getText(end.offset);
    var match = pattern.matchAsPrefix(text);
    if (match == null) return this;
    return file.span(start.offset, end.offset + match.end);
  }

  /// Returns true if this span is preceded by exactly [text].
  bool matchesBefore(String text) {
    if (start.offset - text.length < 0) return false;
    return file.getText(start.offset - text.length, start.offset) == text;
  }

  /// Returns a span covering the text after this span and before [other].
  ///
  /// Throws an [ArgumentError] if [other.start] isn't on or after `this.end` in
  /// the same file.
  FileSpan between(FileSpan other) {
    if (sourceUrl != other.sourceUrl) {
      throw ArgumentError("$this and $other are in different files.");
    } else if (end.offset > other.start.offset) {
      throw ArgumentError("$this isn't before $other.");
    }

    return file.span(end.offset, other.start.offset);
  }

  /// Returns a span covering the text from the beginning of this span to the
  /// beginning of [inner].
  ///
  /// Throws an [ArgumentError] if [inner] isn't fully within this span.
  FileSpan before(FileSpan inner) {
    if (sourceUrl != inner.sourceUrl) {
      throw ArgumentError("$this and $inner are in different files.");
    } else if (inner.start.offset < start.offset ||
        inner.end.offset > end.offset) {
      throw ArgumentError("$inner isn't inside $this.");
    }

    return file.span(start.offset, inner.start.offset);
  }

  /// Returns a span covering the text from the end of [inner] to the end of
  /// this span.
  ///
  /// Throws an [ArgumentError] if [inner] isn't fully within this span.
  FileSpan after(FileSpan inner) {
    if (sourceUrl != inner.sourceUrl) {
      throw ArgumentError("$this and $inner are in different files.");
    } else if (inner.start.offset < start.offset ||
        inner.end.offset > end.offset) {
      throw ArgumentError("$inner isn't inside $this.");
    }

    return file.span(inner.end.offset, end.offset);
  }

  /// Return whether this span overlaps with [other].
  ///
  /// Empty spans are considered to overlap only spans that contain characters
  /// both before and after the empty span.
  bool hasOverlap(FileSpan other) =>
      sourceUrl == other.sourceUrl &&
      start.offset < other.end.offset &&
      end.offset > other.start.offset;
}
