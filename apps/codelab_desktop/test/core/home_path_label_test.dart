// Сокращение домашнего каталога до `~` в путях подсказок (подзаголовок
// диалога «Add connection profile» и подсказка хранилища только для чтения).

import 'package:codelab_desktop/core/platform/home_path_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a path under HOME starts with ~', () {
    expect(
      homePathLabel('/Users/u/.codelab/config.yaml', {'HOME': '/Users/u'}),
      '~/.codelab/config.yaml',
    );
  });

  test('USERPROFILE is used when HOME is absent', () {
    expect(homePathLabel('/home/u/x', {'USERPROFILE': '/home/u'}), '~/x');
  });

  test('a path outside HOME, or without HOME, stays absolute', () {
    expect(homePathLabel('/tmp/ch', {'HOME': '/Users/u'}), '/tmp/ch');
    expect(homePathLabel('/tmp/ch', const {}), '/tmp/ch');
    expect(homePathLabel('/Users/ux/a', {'HOME': '/Users/u'}), '/Users/ux/a');
  });
}
