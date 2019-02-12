// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

class Patch {
  /// Selection to be replaced
  final FileSpan selection;

  /// Text to replace the selection with.
  final String replacement;

  /// Constructs a patch that replaces [selection] with [replacement].
  const Patch(this.selection, this.replacement);

  /// Applies a series of non-overlapping patches to the text of a file.
  static String applyAll(SourceFile file, List<Patch> patches) {
    var sortedPatches = patches.toList()
      ..sort((a, b) => a.selection.compareTo(b.selection));
    var buffer = StringBuffer();
    int offset = 0;
    for (var patch in sortedPatches) {
      if (patch.selection.start.offset < offset) {
        throw new ArgumentError("Can't apply overlapping patches.");
      }
      buffer.write(file.getText(offset, patch.selection.start.offset));
      buffer.write(patch.replacement);
      offset = patch.selection.end.offset;
    }
    buffer.write(file.getText(offset));
    return buffer.toString();
  }
}
