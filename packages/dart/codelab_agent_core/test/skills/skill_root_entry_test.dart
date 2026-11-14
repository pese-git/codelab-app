import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Предикаты элемента `skills.extra_roots` (design.md change
/// `add-app-skills-page`, D5, ревью итерации 2: один предикат для загрузчика
/// и моста).
///
/// Почему в ядре: загрузчик (`codelab_agent_io`) и мост настроек
/// (`codelab_setup`, web-безопасный) решают по одному признаку, читать ли
/// относительный корень у недоверенного проекта; два дубликата разошлись бы.
/// Чистые функции над строкой, без `dart:io`.
void main() {
  test('isRelativeSkillRoot: путь от папки — относительный', () {
    expect(isRelativeSkillRoot('.claude/skills'), isTrue);
    expect(isRelativeSkillRoot('skills'), isTrue);
    expect(isRelativeSkillRoot('../other/skills'), isTrue);
  });

  test('isRelativeSkillRoot: абсолютные, ~ и схемы — нет', () {
    expect(isRelativeSkillRoot('/opt/skills'), isFalse);
    expect(isRelativeSkillRoot(r'C:\skills'), isFalse);
    expect(isRelativeSkillRoot('C:/skills'), isFalse);
    expect(isRelativeSkillRoot('~/skills'), isFalse);
    expect(isRelativeSkillRoot('~'), isFalse);
    expect(isRelativeSkillRoot('~bob/skills'), isFalse);
    expect(isRelativeSkillRoot('https://x/skills'), isFalse);
  });

  test('isHomeSkillRoot: только ~ и ~/…', () {
    expect(isHomeSkillRoot('~'), isTrue);
    expect(isHomeSkillRoot('~/skills'), isTrue);
    expect(isHomeSkillRoot('~bob/skills'), isFalse);
    expect(isHomeSkillRoot('/x'), isFalse);
  });

  test('isAbsoluteSkillRoot: корень, буква диска', () {
    expect(isAbsoluteSkillRoot('/x'), isTrue);
    expect(isAbsoluteSkillRoot(r'D:\x'), isTrue);
    expect(isAbsoluteSkillRoot('x/y'), isFalse);
    expect(isAbsoluteSkillRoot('~/x'), isFalse);
  });
}
