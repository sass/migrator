// Copyright 2018 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

class Patch {
  /// Selection to be replaced
  final FileSpan selection;

  /// Text to replace the selection with.
  final String replacement;

  final PatchType type;

  /// Constructs a normal patch that replaces [selection] with [replacement].
  const Patch(this.selection, this.replacement) : type = PatchType.normal;

  const Patch.prepend(this.replacement)
      : type = PatchType.prepend,
        selection = null;

  const Patch.append(this.replacement)
      : type = PatchType.append,
        selection = null;

  /// Applies a series of non-overlapping patches to the text of a file.
  static String applyAll(SourceFile file, List<Patch> patches) {
    var normalPatches =
        patches.where((p) => p.type == PatchType.normal).toList();
    normalPatches.sort((a, b) => a.selection.compareTo(b.selection));
    var buffer = StringBuffer();
    int offset = 0;
    patches
        .where((p) => p.type == PatchType.prepend)
        .map((p) => p.replacement)
        .forEach(buffer.write);
    for (var patch in normalPatches) {
      if (patch.selection.start.offset < offset) {
        throw new Exception("Can't apply overlapping patches.");
      }
      buffer.write(file.getText(offset, patch.selection.start.offset));
      buffer.write(patch.replacement);
      offset = patch.selection.end.offset;
    }
    buffer.write(file.getText(offset));
    patches
        .where((p) => p.type == PatchType.append)
        .map((p) => p.replacement)
        .forEach(buffer.write);
    return buffer.toString();
  }
}

enum PatchType { normal, prepend, append }
