// Copyright 2019 Google LLC
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
    Patch lastPatch;
    for (var patch in sortedPatches) {
      // The module migrator generates duplicate patches when renaming two nodes
      // that share the same span (itself a workaround within the parser).
      // It's easier to ignore the duplicate here than work around it within the
      // module migrator.
      if (patch.selection == lastPatch?.selection &&
          patch.replacement == lastPatch?.replacement &&
          patch.selection.length > 0) {
        continue;
      }
      if (patch.selection.start.offset < offset) {
        throw new ArgumentError("Can't apply overlapping patches.");
      }
      buffer.write(file.getText(offset, patch.selection.start.offset));
      buffer.write(patch.replacement);
      offset = patch.selection.end.offset;
      lastPatch = patch;
    }
    buffer.write(file.getText(offset));
    return buffer.toString();
  }
}
