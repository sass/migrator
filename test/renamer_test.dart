// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/src/renamer.dart';
import 'package:test/test.dart';

void main() {
  group('single statements', () {
    group('simple rename with', () {
      test('sed-style syntax', () {
        var renamer = Renamer.simple('s/old/new/');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });

      test('default key', () {
        var renamer = Renamer.simple('/old/new/');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });

      test('space syntax with `to` clause', () {
        var renamer = Renamer.simple('s old to new');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });

      test('space syntax with `to` clause and default key', () {
        var renamer = Renamer.simple('old to new');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });

      test('space syntax with `->` clause', () {
        var renamer = Renamer.simple('s old -> new');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });

      test('space syntax with `->` clause and default key', () {
        var renamer = Renamer.simple('old -> new');
        expect(renamer.rename('old'), equals('new'));
        expect(renamer.rename('oldx'), isNull);
        expect(renamer.rename('xold'), isNull);
        expect(renamer.rename('new'), isNull);
      });
    });

    group('backreferences', () {
      test(r'to entire match', () {
        var renamer = Renamer.simple(r'.+ to prefix-\0');
        expect(renamer.rename('a'), equals('prefix-a'));
        expect(renamer.rename('abc'), equals('prefix-abc'));
      });

      test(r'to group', () {
        var renamer = Renamer.simple(r'/(.+)-suffix/\1/');
        expect(renamer.rename('a-suffix'), equals('a'));
        expect(renamer.rename('abc-suffix'), equals('abc'));
        expect(renamer.rename('abc'), isNull);
        expect(renamer.rename('-suffix'), isNull);
      });
    });

    group('escaping', () {
      test(r'spaces', () {
        var renamer = Renamer.simple(r'a\ b to x\ y');
        expect(renamer.rename('a b'), equals('x y'));
      });

      test(r'normal delimiters', () {
        var renamer = Renamer.simple(r'/a\/b/x\/y/');
        expect(renamer.rename('a/b'), equals('x/y'));
      });

      test(r'semicolons', () {
        var renamer = Renamer.simple(r'a\;b to x\;y');
        expect(renamer.rename('a;b'), equals('x;y'));
      });
    });

    group('multiple keys', () {
      test('sed-style syntax', () {
        var renamer =
            Renamer.map(r'url=.*/(\w+)/lib/mixins=\1=', ['namespace', 'url']);
        expect(
            renamer.rename(
                {'namespace': 'mixins', 'url': 'path/button/lib/mixins'}),
            equals('button'));
      });

      test('space syntax', () {
        var renamer =
            Renamer.map(r'url .*/(\w+)/lib/mixins to \1', ['namespace', 'url']);
        expect(
            renamer.rename(
                {'namespace': 'mixins', 'url': 'path/button/lib/mixins'}),
            equals('button'));
      });
    });
  });

  group('multiple statements', () {
    test('separated by semicolon', () {
      var renamer = Renamer.simple('/a/b/;/x/y/');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('separated by line break', () {
      var renamer = Renamer.simple('/a/b/\n/x/y/');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('separated by semicolon and line break', () {
      var renamer = Renamer.simple('/a/b/;\n/x/y/;');
      expect(renamer.rename('a'), equals('b'));
      expect(renamer.rename('b'), isNull);
      expect(renamer.rename('x'), equals('y'));
      expect(renamer.rename('y'), isNull);
    });

    test('only first matching statement is applied', () {
      var renamer = Renamer.simple('/.*/all/;/old/wrong/;/all/wrong/');
      expect(renamer.rename('old'), equals('all'));
      expect(renamer.rename('wrong'), equals('all'));
      expect(renamer.rename('all'), equals('all'));
    });
  });

  group('invalid syntax', () {
    test('extra code after statement', () {
      expect(() => Renamer.simple('/old/new/extra'), throwsFormatException);
    });

    test('no trailing delimiter', () {
      expect(() => Renamer.simple('s/old/new'), throwsFormatException);
    });

    test('too few clauses', () {
      expect(() => Renamer.simple('s/old/'), throwsFormatException);
    });

    test('too few clauses in space syntax', () {
      expect(() => Renamer.simple('old new'), throwsFormatException);
    });

    test('too many clauses in space syntax', () {
      expect(() => Renamer.simple('s old to new extra'), throwsFormatException);
    });

    test('invalid delimiter', () {
      expect(() => Renamer.simple('s-old-new-'), throwsFormatException);
    });
  });
}
