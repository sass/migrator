// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/src/renamer.dart';
import 'package:test/test.dart';

void main() {
  group('single statements', () {
    group('single key', () {
      test('simple rename', () {
        var renamer = Renamer.simple('old to new');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });

      test(r'backreference to entire match', () {
        var renamer = Renamer.simple(r'.+ to prefix-\0');
        expect(renamer.rename('a'), equals('prefix-a'));
        expect(renamer.rename('abc'), equals('prefix-abc'));
      });

      test(r'backreference to group', () {
        var renamer = Renamer.simple(r'(.+)-suffix to \1');
        expect(renamer.rename('a-suffix'), equals('a'));
        expect(renamer.rename('abc-suffix'), equals('abc'));
        expect(renamer.rename('abc'), isNull);
        expect(renamer.rename('-suffix'), isNull);
      });
    });

    group('escapes', () {
      test(r'spaces', () {
        var renamer = Renamer.simple(r'a\ b to x\ y');
        expect(renamer.rename('a b'), equals('x y'));
      });

      test(r'semicolons', () {
        var renamer = Renamer.simple(r'a\;b to x\;y');
        expect(renamer.rename('a;b'), equals('x;y'));
      });

      test(r'backslash at start', () {
        var renamer = Renamer.simple(r'\\ab to \\xy');
        expect(renamer.rename(r'\ab'), equals(r'\xy'));
      });

      test(r'backslash in middle', () {
        var renamer = Renamer.simple(r'a\\b to x\\y');
        expect(renamer.rename(r'a\b'), equals(r'x\y'));
      });

      test(r'backslash at end', () {
        var renamer = Renamer.simple(r'ab\\ to xy\\');
        expect(renamer.rename(r'ab\'), equals(r'xy\'));
      });

      test(r'backslash followed by escaped space', () {
        var renamer = Renamer.simple(r'ab\\\  to x\\\ y');
        expect(renamer.rename(r'ab\ '), equals(r'x\ y'));
      });
    });

    group('multiple keys', () {
      test('named key', () {
        var renamer =
            Renamer.map(r'url .*/(\w+)/lib/mixins to \1', ['namespace', 'url']);
        expect(
            renamer.rename(
                {'namespace': 'mixins', 'url': 'path/button/lib/mixins'}),
            equals('button'));
      });

      test('named key with unused default key', () {
        var renamer =
            Renamer.map(r'url .*/(\w+)/lib/mixins to \1', ['', 'url']);
        expect(renamer.rename({'': 'mixins', 'url': 'path/button/lib/mixins'}),
            equals('button'));
      });

      test('default key', () {
        var renamer =
            Renamer.map(r'.*/(\w+)/lib/mixins to \1', ['namespace', '']);
        expect(
            renamer
                .rename({'namespace': 'mixins', '': 'path/button/lib/mixins'}),
            equals('button'));
      });

      test('matcher on default key has same name as another key', () {
        var renamer = Renamer.map('key to to', ['', 'key']);
        expect(renamer.rename({'': 'key', 'key': 'x'}), equals('to'));
      });

      test('matcher on named key is `to`', () {
        var renamer = Renamer.map('key to to new', ['', 'key']);
        expect(renamer.rename({'': 'key', 'key': 'to'}), equals('new'));
      });
    });
  });

  group('multiple statements', () {
    test('separated by semicolon', () {
      var renamer = Renamer.simple('a to b; x to y');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('separated by line break', () {
      var renamer = Renamer.simple('a to b\nx to y');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('empty statements', () {
      var renamer = Renamer.simple('\n;\n;a to b; ;;\n; \n;; x to y ;\n;');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('separated by semicolon and line break', () {
      var renamer = Renamer.simple('a to b;\nx to y;');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('only first matching statement is applied', () {
      var renamer = Renamer.simple('.* to all; old to wrong; all to wrong');
      expect(renamer.rename('old'), equals('all'));
      expect(renamer.rename('wrong'), equals('all'));
      expect(renamer.rename('all'), equals('all'));
    });

    test('no statements', () {
      var renamer = Renamer.simple('');
      expect(renamer.rename('abc'), isNull);
    });
  });

  group('invalid syntax', () {
    test('too few clauses', () {
      expect(() => Renamer.simple('old new'), throwsFormatException);
    });

    test('three clauses but not `to` ', () {
      expect(() => Renamer.simple('old xx new'), throwsFormatException);
    });

    test('four clauses with only default key', () {
      expect(() => Renamer.simple('key old to new'), throwsFormatException);
    });

    test('four clauses with invalid key', () {
      expect(() => Renamer.map('wrong old to new', ['key']),
          throwsFormatException);
    });

    test('five clauses', () {
      expect(() => Renamer.map('key old to new extra', ['key']),
          throwsFormatException);
    });
  });
}
