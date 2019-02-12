// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_module_migrator/src/patch.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

void main() {
  test("single patch applied", () {
    var file = SourceFile.fromString("abcde");
    var patch = Patch(file.span(2, 4), "fgh");
    expect(Patch.applyAll(file, [patch]), equals("abfghe"));
  });
  test("multiple patches applied", () {
    var file = SourceFile.fromString("abcde");
    var patch1 = Patch(file.span(0, 2), "xyz");
    var patch2 = Patch(file.span(3, 4), "fgh");
    expect(Patch.applyAll(file, [patch1, patch2]), equals("xyzcfghe"));
  });
  test("overlapping patches fail", () {
    var file = SourceFile.fromString("abcde");
    var patch1 = Patch(file.span(0, 3), "xyz");
    var patch2 = Patch(file.span(2, 4), "fgh");
    expect(() => Patch.applyAll(file, [patch1, patch2]), throwsArgumentError);
  });
}
