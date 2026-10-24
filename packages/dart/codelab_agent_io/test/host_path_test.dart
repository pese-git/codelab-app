import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

void main() {
  group('Windows paths ↔ core paths (design.md, D3)', () {
    test('a drive path becomes /<drive>/…', () {
      expect(toCorePath(r'C:\proj\a.txt', windows: true), '/c/proj/a.txt');
      expect(toCorePath(r'D:\', windows: true), '/d');
      expect(toCorePath('c:/proj', windows: true), '/c/proj');
    });

    test('a core path becomes a drive path', () {
      expect(toHostPath('/c/proj/a.txt', windows: true), r'C:\proj\a.txt');
      expect(toHostPath('/d', windows: true), r'D:\');
    });

    test('sibling folders stay different after conversion', () {
      expect(toCorePath(r'C:\proj2', windows: true), '/c/proj2');
    });
  });

  test('POSIX paths pass unchanged', () {
    expect(toCorePath('/home/u/proj', windows: false), '/home/u/proj');
    expect(toHostPath('/home/u/proj', windows: false), '/home/u/proj');
  });
}
