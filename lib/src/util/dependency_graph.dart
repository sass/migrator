// Copyright 2023 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

/// A graph data structure to manage dependencies between URIs.
///
/// This class allows adding, removing, and querying dependencies
/// between source URIs and their imported paths.
class DependencyGraph {
  final Map<Uri, Set<Uri>> _graph = {};

  /// Adds a dependency relationship between source and importedPath.
  void add(Uri source, Uri importedPath) {
    _graph.putIfAbsent(source, () => {}).add(importedPath);
  }

  /// Removes a dependency relationship between source and importedPath.
  void remove(Uri source, Uri importedPath) {
    _graph[source]?.remove(importedPath);
  }

  /// Finds all dependencies of a given source.
  Set<Uri>? find(Uri source) {
    return _graph[source];
  }

  /// Checks if a specific dependency exists.
  bool hasDependency(Uri source, Uri importedPath) {
    return _graph.containsKey(source) && _graph[source]!.contains(importedPath);
  }
}
