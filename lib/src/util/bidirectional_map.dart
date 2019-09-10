// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

/// A map that allows you to efficiently find all keys associated with a
/// particular value.
///
/// Each key can be associated with at most one value, but each value can be
/// associated with more than one key.
///
/// This map also provides a mechanism for freezing its contents. Once [freeze]
/// is called, this map may no longer be modified.
class BidirectionalMap<K, V> extends MapBase<K, V> {
  /// Stores the value associated with each key.
  final _valueForKey = <K, V>{};

  /// Stores the set of keys associated with each value.
  ///
  /// This should always stay in sync with [_valueForKey].
  final _keysForValue = <V, Set<K>>{};

  @override
  V operator [](Object key) => _valueForKey[key];

  @override
  void operator []=(K key, V value) {
    remove(key);
    _valueForKey[key] = value;
    _keysForValue.putIfAbsent(value, () => {});
    _keysForValue[value].add(key);
  }

  @override
  void clear() {
    _valueForKey.clear();
    _keysForValue.clear();
  }

  @override
  Iterable<K> get keys => _valueForKey.keys;

  @override
  Iterable<V> get values => _keysForValue.keys;

  @override
  V remove(Object key) {
    if (!_valueForKey.containsKey(key)) return null;
    var value = _valueForKey.remove(key);
    _keysForValue[value].remove(key);
    if (_keysForValue[value].isEmpty) _keysForValue.remove(value);
    return value;
  }

  /// Returns the set of all keys associated with a given value.
  Iterable<K> keysForValue(V value) => _keysForValue[value]?.toSet() ?? {};
}
