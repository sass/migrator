// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:path/path.dart' as p;
import 'package:sass/sass.dart';

import '../utils.dart';
import 'reversible_importer.dart';

/// A version of [FilesystemImporter] that implements [ReversibleImporter] as
/// well.
class ReversibleFilesystemImporter extends Importer
    implements ReversibleImporter {
  /// The wrapped importer to which this delegates.
  final FilesystemImporter _inner;

  /// The path relative to which this importer looks for files.
  final String _loadPath;

  ReversibleFilesystemImporter(this._loadPath)
      : _inner = FilesystemImporter(_loadPath);

  Uri decanonicalize(Uri canonicalUrl) => cleanBasename(
      p.toUri(p.relative(p.fromUri(canonicalUrl), from: _loadPath)));

  Uri canonicalize(Uri url) => _inner.canonicalize(url);

  ImporterResult load(Uri canonicalUrl) => _inner.load(canonicalUrl);

  String toString() => _inner.toString();
}
