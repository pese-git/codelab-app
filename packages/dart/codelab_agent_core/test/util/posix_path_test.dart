import 'package:codelab_agent_core/src/util/posix_path.dart';
import 'package:test/test.dart';

void main() {
  group('normalizePath', () {
    test('a relative path is joined to the base', () {
      expect(normalizePath('/proj', 'src/a.dart'), '/proj/src/a.dart');
    });

    test('dot and empty segments are dropped', () {
      expect(normalizePath('/proj', './a//b/./c'), '/proj/a/b/c');
    });

    test('.. removes the previous segment and stops at the root', () {
      expect(normalizePath('/proj', 'src/../../etc/passwd'), '/etc/passwd');
      expect(normalizePath('/proj', '../../../..'), '/');
    });

    test('an absolute path ignores the base', () {
      expect(normalizePath('/proj', '/proj_evil/x'), '/proj_evil/x');
    });

    test('the home directory is not expanded', () {
      expect(normalizePath('/proj', '~'), isNull);
      expect(normalizePath('/proj', '~/.ssh/id_rsa'), isNull);
    });
  });

  group('isInside compares segments, not string prefixes', () {
    test('the root and its descendants are inside', () {
      expect(isInside('/proj', '/proj'), isTrue);
      expect(isInside('/proj', '/proj/a/b'), isTrue);
      expect(isInside('/', '/anything'), isTrue);
    });

    test('a sibling with a shared name prefix is outside', () {
      expect(isInside('/proj', '/proj_evil/x'), isFalse);
      expect(isInside('/c/proj', '/c/proj2/x'), isFalse);
    });
  });

  test('relativeTo shows paths under the root relative to it', () {
    expect(relativeTo('/proj', '/proj/lib/a.dart'), 'lib/a.dart');
    expect(relativeTo('/proj', '/proj'), '.');
    expect(relativeTo('/proj', '/other/a'), '/other/a');
  });
}
