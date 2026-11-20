/// Закрытый набор ролей цвета темы (spec `client-themes`, «Роли цветов темы»).
///
/// ЗАГЛУШКА красного теста 1.3: данные перечисления — часть API, поведение
/// разбора появится в задаче 1.4.
library;

enum ThemeRole {
  text('text'),
  accent('accent'),
  muted('muted'),
  success('success'),
  error('error'),
  warning('warning'),
  info('info'),
  diffAddBg('diff_add_bg'),
  diffRemoveBg('diff_remove_bg'),
  selection('selection'),
  approvalBorder('approval_border'),
  statusBg('status_bg'),
  codeBackground('background', isCode: true),
  codeKeyword('keyword', isCode: true),
  codeString('string', isCode: true),
  codeComment('comment', isCode: true),
  codeNumber('number', isCode: true),
  codeType('type', isCode: true),
  codeFunction('function', isCode: true),
  codeVariable('variable', isCode: true),
  codeOperator('operator', isCode: true),
  codeAttribute('attribute', isCode: true);

  const ThemeRole(this.key, {this.isCode = false});

  /// JSON-ключ внутри своей области (`colors` или `colors.code`).
  final String key;

  /// Роль палитры кода (`colors.code`).
  final bool isCode;

  /// Имя для списков и сообщений: `accent`, `code.number`.
  String get qualifiedName => isCode ? 'code.$key' : key;
}
