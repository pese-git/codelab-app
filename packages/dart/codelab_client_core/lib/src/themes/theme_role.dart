/// Закрытый набор ролей цвета темы (spec `client-themes`, «Роли цветов темы»).
///
/// Почему: набор ролей закрыт и одинаков для app и CLI (§12.6.3), поэтому
/// он описан одним перечислением, а не строками в потребителях.
///
/// Как использовать: [ThemeRole.key] — JSON-ключ в своей области (`colors`
/// или `colors.code`), [ThemeRole.qualifiedName] — имя для списков и
/// сообщений (`code.number`).
library;

/// Роль цвета темы: одна строка закрытого набора app и CLI.
///
/// Как использовать: ключи области и имена для списков — [key] и
/// [qualifiedName]; роли, которые клиенту не нужны (`status_bg`,
/// `approval_border` в app), разбираются без предупреждения и не применяются.
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
