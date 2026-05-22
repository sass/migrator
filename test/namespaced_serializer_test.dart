// Copyright 2026 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';
import 'package:sass_migrator/src/util/namespaced_serializer.dart';
import 'package:test/test.dart';

void main() {
  final echoNamespace = NamespacedSerializer((ref) => ref.name);

  group('serializer handles a binary operation', () {
    test('with literals', () {
      var code = r'1 + 2';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('with variables', () {
      var code = r'$a + $b';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'a.$a + b.$b');
    });

    test('with function calls', () {
      var code = r'a() + b()';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'a.a() + b.b()');
    });
  });

  group('serializer handles an if function', () {
    test('with literals', () {
      var code = r'if(sass(true): 1; else: 2)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('with variables', () {
      var code = r'if(sass($a): $b; else: $c)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'if(sass(a.$a): b.$b; else: c.$c)');
    });

    test('with function calls', () {
      var code = r'if(sass(a()): b(); else: c())';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'if(sass(a.a()): b.b(); else: c.c())');
    });
  });

  group('serializer handles a legacy if function', () {
    test('with literals', () {
      var code = r'if(true, 1, 2)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('with variables', () {
      var code = r'if($a, $b, $c)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'if(a.$a, b.$b, c.$c)');
    });

    test('with function calls', () {
      var code = r'if(a(), b(), c())';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'if(a.a(), b.b(), c.c())');
    });
  });

  group('serializer handles a list', () {
    test('space separated with brackets', () {
      var code = r'[1 2]';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('comma separated with brackets', () {
      var code = r'[1, 2]';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('space separated without brackets', () {
      var code = r'1 2';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('comma separated without brackets', () {
      var code = r'1, 2';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('with variables', () {
      var code = r'[$a, $b]';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'[a.$a, b.$b]');
    });

    test('with function calls', () {
      var code = r'[a(), b()]';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'[a.a(), b.b()]');
    });
  });

  group('serializer handles a map', () {
    test('with literals', () {
      var code = r'("a": 1)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('with variables', () {
      var code = r'($a: $b)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'(a.$a: b.$b)');
    });

    test('with function calls', () {
      var code = r'(a(): b())';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'(a.a(): b.b())');
    });
  });

  group('serializer handles interpolation', () {
    test('in a quoted string', () {
      var code = r'"#{red}-#{green}-#{blue}"';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('in an unquoted string', () {
      var code = r'#{red}-#{green}-#{blue}';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, code);
    });

    test('with variables', () {
      var code = r'#{$r}-#{$g}-#{$b}';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'#{r.$r}-#{g.$g}-#{b.$b}');
    });

    test('with function calls', () {
      var code = r'#{r()}-#{g()}-#{b()}';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'#{r.r()}-#{g.g()}-#{b.b()}');
    });
  });

  group('serializer handles a function call', () {
    test('with positional arguments', () {
      var code = r'fn($a, $b)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'fn.fn(a.$a, b.$b)');
    });

    test('with named arguments', () {
      var code = r'fn($x: $a, $y: $b)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'fn.fn($x: a.$a, $y: b.$b)');
    });

    test('with a rest argument', () {
      var code = r'fn($args...)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'fn.fn(args.$args...)');
    });

    test('with a rest argument and a keyword map', () {
      var code = r'fn($args..., $kwargs...)';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'fn.fn(args.$args..., kwargs.$kwargs...)');
    });
  });

  group('serializer can remove existing namespace', () {
    test('from a variable', () {
      var code = r'library.$var';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'var.$var');
    });

    test('from a function', () {
      var code = r'library.fn()';
      var serialized = echoNamespace.serialize(Expression.parse(code));
      expect(serialized, r'fn.fn()');
    });
  });
}
