import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import 'codelab_markdown_row.dart';
import 'codelab_markdown_scope.dart';
import 'codelab_markdown_stats.dart';
import 'escape_for_display.dart';

/// Изображение ответа: заглушка, а после «Show image» — сама картинка.
///
/// Почему: изображение не загружается без явного действия пользователя —
/// иначе враждебный ответ вынесет данные адресом `![](https://…?d=секрет)`
/// (D6, VIEW-12, DSK-7).
///
/// Для чего: по умолчанию показывает «Image», хост, имя файла и полный адрес
/// в подсказке, не обращаясь к сети. Если app разрешил загрузку адреса
/// (`canLoadImage`) — добавляет кнопку «Show image»; нажатие сообщает ключ
/// `<rowId>#image:<url>` в `onShowImage`. Когда ключ есть в `shownImages`,
/// вместо заглушки рисуется `Image(imageFor(uri))`; ошибка загрузки возвращает
/// заглушку без исключения. Без scope кнопки нет.
///
/// Как использовать: строится только `imageBuilder` конфигурации; [url] —
/// адрес как в ответе, на экран он попадает через `escapeForDisplay`. Виджет
/// подписан на scope сам, поэтому смена `shownImages` не перестраивает
/// закрытые блоки пакета (DSK-3, D3).
class CodeLabImagePlaceholder extends StatelessWidget {
  const CodeLabImagePlaceholder({required this.url, super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    assert(CodeLabMarkdownStats.noteImagePlaceholderBuild());
    final scope = CodeLabMarkdownScope.maybeOf(context);
    final uri = Uri.tryParse(url);
    final loadable = scope != null && uri != null && scope.canLoadImage(uri);
    if (loadable) {
      final key = '${CodeLabMarkdownRowScope.of(context).id}#image:$url';
      if (scope.shownImages.contains(key)) {
        return _LoadedImage(
          provider: scope.imageFor,
          uri: uri,
          imageKey: key,
          fallback: _Placeholder(url: url),
          loading: _Placeholder(url: url, loading: true),
        );
      }
      return _Placeholder(url: url, onShow: () => scope.onShowImage(key));
    }
    return _Placeholder(url: url);
  }
}

/// Картинка после явного действия пользователя.
///
/// Почему и для чего: поставщик создаётся один раз в `initState` (перерисовка
/// не должна повторно обращаться к `imageFor`). Пока картинка грузится, на её
/// месте — заглушка в том же стиле и маленький `ProgressRing`; после первого
/// кадра — сама картинка. Картинка занимает свою строку под текстом (ширина
/// абзаца, выравнивание влево): иначе `WidgetSpan` по базовой линии прижимал бы
/// подпись к низу высокой картинки. Размер не больше натурального
/// (`BoxFit.scaleDown`), не шире абзаца и не выше 480 (smoke macOS,
/// итерация 4).
class _LoadedImage extends StatefulWidget {
  const _LoadedImage({
    required this.provider,
    required this.uri,
    required this.imageKey,
    required this.fallback,
    required this.loading,
  });

  final ImageProvider Function(Uri uri) provider;
  final Uri uri;

  /// Ключ `<rowId>#image:<url>` для отчёта о сбое.
  final String imageKey;

  /// Заглушка при ошибке загрузки (с кнопкой «Show image» не нужна).
  final Widget fallback;

  /// Заглушка с индикатором, пока картинка грузится.
  final Widget loading;

  @override
  State<_LoadedImage> createState() => _LoadedImageState();
}

class _LoadedImageState extends State<_LoadedImage> {
  late final ImageProvider _image = widget.provider(widget.uri);

  /// Сбой уже передан приложению: `errorBuilder` вызывается на каждой сборке, а
  /// событие журнала нужно одно (D12).
  bool _reported = false;

  void _reportFailure(Object error) {
    if (_reported) return;
    _reported = true;
    // Не во время сборки: колбэк меняет состояние приложения.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = context
          .getInheritedWidgetOfExactType<CodeLabMarkdownScope>();
      scope?.onImageFailed(widget.imageKey, error);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      // Во всю ширину абзаца, если она известна: узкий виджет делил бы строку
      // с текстом.
      width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Image(
            image: _image,
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                wasSynchronouslyLoaded || frame != null
                ? child
                : widget.loading,
            // Сбой загрузки (сеть, не картинка, SVG) — заглушка, без
            // исключения.
            errorBuilder: (context, error, stack) {
              _reportFailure(error);
              return widget.fallback;
            },
          ),
        ),
      ),
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.url, this.onShow, this.loading = false});

  final String url;
  final VoidCallback? onShow;

  /// Картинка загружается: вместо значка — маленький индикатор.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final uri = Uri.tryParse(url);
    // Хост и имя файла приходят из недоверенного адреса: показываются с
    // видимыми escape-последовательностями (D5, R4).
    final host = escapeForDisplay(uri?.host ?? '');
    final name = escapeForDisplay(
      (uri != null && uri.pathSegments.isNotEmpty) ? uri.pathSegments.last : '',
    );
    return Tooltip(
      message: displayAddress(url),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: resources.cardStrokeColorDefault),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              else
                const Icon(FluentIcons.photo2, size: 14),
              const SizedBox(width: 8),
              Flexible(
                child: CodeLabText(
                  ['Image', host, name].where((s) => s.isNotEmpty).join(' · '),
                  role: CodeLabTextRole.caption,
                ),
              ),
              if (onShow != null) ...[
                const SizedBox(width: 8),
                // Кнопка не входит в выделение ответа.
                SelectionContainer.disabled(
                  child: CodeLabButton(
                    label: 'Show image',
                    emphasis: CodeLabButtonEmphasis.subtle,
                    onPressed: onShow,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
