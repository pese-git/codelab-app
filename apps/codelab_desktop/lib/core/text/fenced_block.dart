/// Снимает одно внешнее markdown-ограждение ответа (задача 6.1i, Q34/Q37,
/// D27 change `add-provider-setup-ui`).
///
/// ЗАГЛУШКА красной фазы: поведения нет, возвращает `null`. Реализация —
/// перенос `McpSettingsCubit._unfenced`; `null` означает «весь текст — не один
/// огороженный блок, показывать как есть».
String? unfenceSingleBlock(String text) => null;
