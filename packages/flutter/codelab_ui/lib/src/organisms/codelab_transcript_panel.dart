import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/strings.dart';
import '../molecules/molecules.dart';
import '../rendering/rendering.dart';
import 'codelab_approval_prompt.dart';
import 'codelab_tool_call_tile.dart';
import 'codelab_transcript_notice.dart';
import 'codelab_transcript_row.dart';
import 'codelab_transcript_target.dart';

/// Наибольшая ширина колонки переписки вместе с её боковыми полями
/// [_columnSidePadding] (артборд Main: `max-width: 760px` с
/// `box-sizing: border-box`; требование «Transcript reads as a
/// conversation»). Тексту остаётся 720 px.
const kTranscriptColumnMaxWidth = 760.0;

/// Поля колонки по макету: 20 px по бокам, 8 сверху, 12 снизу; между
/// строками — 12. Боковые поля входят в [kTranscriptColumnMaxWidth], иначе
/// на широком окне текст расползается на 40 px шире макета.
const _columnSidePadding = 20.0;
const _columnTopPadding = 8.0;
const _columnBottomPadding = 12.0;
const _rowGap = 12.0;

/// Пузырь пользователя — доля ширины колонки; в узкой колонке шире, чтобы
/// многострочный промпт не превращался в столбик слов (design, Risks).
const _bubbleWidthFactor = 0.78;
const _narrowBubbleWidthFactor = 0.9;
const _narrowColumnWidth = 560.0;

/// Раскрыта ли строка, если пользователь её не трогал (design D3 change
/// `redesign-transcript-rows`): мысли раскрыты во время стрима, кроме
/// `summary`; вызовы — только в `verbose`.
bool _expandedByDefault(CodeLabTranscriptRow row, CodeLabViewMode viewMode) {
  return switch (row) {
    CodeLabThoughtRow(:final streaming) => switch (viewMode) {
      CodeLabViewMode.summary => false,
      CodeLabViewMode.normal => streaming,
      CodeLabViewMode.verbose => true,
    },
    CodeLabToolCallRow() => viewMode == CodeLabViewMode.verbose,
    _ => false,
  };
}

/// Насколько близко к низу (в пикселях) лента считается «у хвоста».
///
/// Пока пользователь в пределах этого расстояния, лента следует за новыми
/// записями и прокручивается к новому pending approval; дальше — пользователь
/// читает историю, и позиция не меняется (`agent-workbench-ui`, требование
/// «Лента transcript следует за хвостом»).
const _autoScrollBottomThreshold = 80.0;

/// Лента переписки с агентом.
///
/// Почему: лента должна читаться как переписка — колонка по центру, пузырь
/// пользователя, ответ без карточки, свои виджеты для мыслей, вызовов и
/// заметок (change `redesign-transcript-rows`; §12.3.2).
///
/// Для чего: рисует [rows], следует за хвостом и прокручивается к новому
/// ожидающему одобрению. Ручное раскрытие строк хранит владелец
/// ([expansionOverrides]): строки виртуализированы, и `State` строки теряет
/// выбор при уходе с экрана (design D3).
///
/// Как использовать: хост передаёт строки и [onExpansionChanged]; без него
/// строки раскрываются только по умолчанию. Ожидающее одобрение всегда
/// раскрыто. [showRequest] — разовый запрос показа (панель Agents: «Show in
/// transcript», «Go to approval»); раскрытие строк пути хост делает сам через
/// [expansionOverrides] в том же обновлении.
class CodeLabTranscriptPanel extends StatefulWidget {
  const CodeLabTranscriptPanel({
    required this.rows,
    this.expansionOverrides = const {},
    this.onExpansionChanged,
    this.emptyLabel,
    this.viewMode = CodeLabViewMode.normal,
    this.showRequest,
    this.onShowRequestDone,
    this.onApprovalFocusReleased,
    super.key,
  });

  /// Ключ строки ленты по её id — для тестов и автоматизации.
  static ValueKey<String> rowKey(String id) => ValueKey('transcript-row-$id');

  /// Ключ цели показа внутри строки (вложенная строка `agent`, блок
  /// одобрения потомка с `targetId`) — для тестов и автоматизации (D49 Т7).
  static ValueKey<String> targetKey(String id) => transcriptTargetKey(id);

  /// Ключ накладки подсветки: есть, пока цель показа подсвечена (около 1,5 с).
  static ValueKey<String> highlightKey(String id) => transcriptHighlightKey(id);

  /// Разовый запрос показа строки (D49 Т7): прокрутить ленту к строке или к
  /// цели внутри неё и коротко подсветить. Новый [CodeLabTranscriptShowRequest.serial]
  /// — новый запрос; тот же номер при перестроении повторно не прокручивает.
  /// Хост очищать запрос не обязан.
  final CodeLabTranscriptShowRequest? showRequest;

  /// Показ с этим номером закончен: цель показана или шаги исчерпаны. Не
  /// вызывается, если цепочку оборвала смена или исчезновение запроса, смена
  /// сессии или `dispose`. Хост по нему гасит разовый запрос, чтобы
  /// перемонтированная лента не прокрутила снова (D49 Т7).
  final ValueChanged<int>? onShowRequestDone;

  /// Полоса одобрения с клавиатурным фокусом исчезла из ленты (ответ, отмена
  /// хода, снятие запроса, смена сессии): хост возвращает фокус (change
  /// `fix-approval-focus`, D5). Колбэк идёт от полосы через строку вызова;
  /// вызывается один раз и только если фокус был в полосе, когда она уходила.
  /// Если Flutter отдал фокус внутрь другой полосы одобрения, хост переводит
  /// его сразу (в микротаске), иначе — в следующем кадре, если пользователь
  /// не перевёл фокус сам (§12).
  final VoidCallback? onApprovalFocusReleased;

  final List<CodeLabTranscriptRow> rows;
  final Map<String, bool> expansionOverrides;
  final ValueChanged<({String rowId, bool expanded})>? onExpansionChanged;

  /// Текст пустой ленты; `null` — текст кита («No transcript yet»,
  /// `add-desktop-localization`, D4).
  final String? emptyLabel;
  final CodeLabViewMode viewMode;

  @override
  State<CodeLabTranscriptPanel> createState() => _AcpTranscriptPanelState();
}

/// Разовый запрос показа строки в ленте (D49 Т7): панель Agents просит
/// показать строку `agent` или блок одобрения потомка.
///
/// [rowId] — id строки верхнего уровня, [targetId] — id цели внутри неё
/// (равен [rowId], если цель — сама строка), [serial] — номер запроса:
/// повтор того же действия получает новый номер и прокручивает снова.
final class CodeLabTranscriptShowRequest {
  const CodeLabTranscriptShowRequest({
    required this.rowId,
    required this.targetId,
    required this.serial,
    this.focusApproval = false,
    this.sessionId,
    this.approvalId,
  });

  final String rowId;
  final String targetId;
  final int serial;

  /// После показа поставить клавиатурный фокус на полосу решения цели
  /// (change `fix-approval-focus`, D4, п. 2): сочетание «Go to approval».
  /// Фокус ставится только в построенной цели и только пока запрос актуален;
  /// не нашли полосу или запрос устарел — фокус прежний. Разовость запроса
  /// (`serial`, `onShowRequestDone`) защищает от повтора при перемонтировании.
  final bool focusApproval;

  /// Сессия и id запроса, выбранного при нажатии «Go to approval»: фокус
  /// получает только полоса с ключом `CodeLabApprovalPrompt.keyFor(sessionId,
  /// approvalId)`. Без них или без такой полосы в цели фокус не трогается:
  /// запрос мог уйти, а в той же строке появиться другой (D13; спецификация
  /// «Цель ушла до фокуса»).
  final String? sessionId;
  final String? approvalId;
}

/// Состояние ленты: владеет `ScrollController` и решает, когда двигать
/// прокрутку.
///
/// Почему: записи дописываются в конец ленты (ответы агента, карточки
/// инструментов, approval), а ленивый список сам к ним не прокручивается.
/// Для чего: два механизма прокрутки — анимированная к новому pending
/// approval и мгновенное следование за хвостом (change
/// `follow-transcript-tail`, D1–D4); оба отключаются, когда пользователь
/// прокрутил ленту вверх.
class _AcpTranscriptPanelState extends State<CodeLabTranscriptPanel> {
  final _controller = ScrollController();

  /// Пользователь прокрутил ленту вверх, дальше порога от низа, и читает
  /// историю. Меняется только прокруткой самого пользователя: рост ленты под
  /// нетронутой видимой частью не означает, что пользователь ушёл от хвоста.
  bool _isReadingHistory = false;
  bool _isUserScrolling = false;

  /// Выставлен, пока новый pending approval нужно держать в виду: ленивый
  /// список лишь оценивает высоту непостроенных записей, и реальный низ
  /// может сдвинуться уже после завершения прокрутки к нему.
  bool _isKeepingApprovalInView = false;

  /// Лента следует за хвостом: выставляется, когда обновление пришло, пока
  /// пользователь был у низа, и сбрасывается любой прокруткой пользователя
  /// (D2). Пока выставлен, лента догоняет сдвинувшийся низ так же, как для
  /// approval.
  bool _isFollowingTail = false;

  /// Номер текущего показа строки: смена отменяет цепочку кадров прежнего
  /// запроса и поздний кадр после `dispose` (AGENTS.md §9, D49 Т7).
  int _showToken = 0;

  /// Номер последнего исполненного запроса показа. Номер монотонный и общий
  /// для всех сессий, а лента одна: при возврате в сессию прежний запрос
  /// снова приходит в `showRequest` и без этой памяти повторил бы прокрутку
  /// и подсветку (D49 Т7). Исполняется только запрос с бо́льшим номером.
  int? _lastShowSerial;

  /// Цель, подсвеченная сейчас; живёт около [_highlightDuration].
  String? _highlightId;
  Timer? _highlightTimer;

  /// Конфигурация markdown, общая для всех строк ответа (D3). Живёт в
  /// `State`, а не создаётся в `build`: пакет кеширует закрытые блоки, только
  /// пока тема и builder'ы — те же объекты (DSK-3).
  CodeLabMarkdownConfig? _markdownConfig;

  /// Конфигурация для текущей темы Fluent; новая — только при смене темы.
  CodeLabMarkdownConfig _markdownConfigFor(FluentThemeData theme) {
    final current = _markdownConfig;
    if (current != null && current.theme == theme) return current;
    return _markdownConfig = CodeLabMarkdownConfig(theme);
  }

  @override
  void initState() {
    super.initState();

    // Панель может появиться сразу с pending approval в первых записях (хост
    // обычно подставляет ленту, только когда записи уже есть) — предыдущей
    // сборки, с которой сравнил бы `didUpdateWidget`, нет.
    if (_pendingApprovalEntryIds(widget.rows).isNotEmpty) {
      _bringApprovalIntoView();
    }
    if (widget.showRequest case final request?) {
      _startShow(request);
    }
  }

  @override
  void dispose() {
    _showToken++;
    _highlightTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CodeLabTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Запрос показа важнее следования за хвостом: он сам переводит ленту в
    // режим чтения истории (D49 Т7), иначе обновление строк ниже вернуло бы
    // её к низу.
    final request = widget.showRequest;
    if (request?.serial != oldWidget.showRequest?.serial) {
      // Смена или исчезновение запроса (в том числе смена сессии) обрывает
      // цепочку кадров прежнего: иначе она нашла бы `rowId` в чужих строках.
      _showToken++;
      final last = _lastShowSerial;
      if (request != null && (last == null || request.serial > last)) {
        _startShow(request);
        return;
      }
    }

    // Метрики контроллера ещё описывают прежнюю раскладку: после раскладки
    // новая запись уже отодвинет низ, и «был у низа» станет не отличить от
    // «читал историю» (D1).
    final wasAtTail = !_isReadingHistory && (_isFollowingTail || _isNearBottom);

    final pendingApprovalIds = _pendingApprovalEntryIds(widget.rows);
    if (pendingApprovalIds.isEmpty) {
      _isKeepingApprovalInView = false;
    }

    final newPendingApprovalIds = pendingApprovalIds.difference(
      _pendingApprovalEntryIds(oldWidget.rows),
    );
    if (newPendingApprovalIds.isNotEmpty && !_isReadingHistory) {
      // Анимация к approval важнее прыжка в этом кадре: `jumpTo` оборвал бы
      // её (D3).
      _bringApprovalIntoView();
      return;
    }

    if (wasAtTail && !identical(widget.rows, oldWidget.rows)) {
      _jumpToTail();
    }
  }

  bool get _isNearBottom {
    if (!_controller.hasClients) {
      // Первая раскладка с записями ещё не прошла: лента пуста или только
      // появилась, пользователь её не прокручивал.
      return true;
    }
    final position = _controller.position;
    return position.maxScrollExtent - position.pixels <=
        _autoScrollBottomThreshold;
  }

  void _jumpToTail() {
    _isFollowingTail = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients && _isFollowingTail) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  void _bringApprovalIntoView() {
    _isKeepingApprovalInView = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      unawaited(
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _isUserScrolling = true;
      _isKeepingApprovalInView = false;
      _isFollowingTail = false;
    } else if (notification is ScrollEndNotification) {
      if (_isUserScrolling) {
        _isUserScrolling = false;
        final metrics = notification.metrics;
        _isReadingHistory =
            metrics.maxScrollExtent - metrics.pixels >
            _autoScrollBottomThreshold;
      } else {
        _followMovedBottom(notification.metrics);
      }
    }
    return false;
  }

  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (!_controller.position.isScrollingNotifier.value) {
      _followMovedBottom(notification.metrics);
    }
    return false;
  }

  void _followMovedBottom(ScrollMetrics metrics) {
    final isHoldingBottom = _isKeepingApprovalInView || _isFollowingTail;
    if (!isHoldingBottom || _isReadingHistory || metrics.extentAfter <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _controller.hasClients &&
          (_isKeepingApprovalInView || _isFollowingTail)) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  /// Сколько кадров лента ищет построенную цель, двигаясь к ней.
  static const _maxShowAttempts = 40;
  static const _highlightDuration = Duration(milliseconds: 1500);

  /// Начинает показ: программная прокрутка — такое же «чтение истории», как
  /// прокрутка пользователем; следование за хвостом и удержание одобрения
  /// выключаются, иначе поток вернул бы ленту к низу (D49 Т7; change
  /// `follow-transcript-tail`). Возврат к хвосту — прокруткой пользователя.
  void _startShow(CodeLabTranscriptShowRequest request) {
    final token = ++_showToken;
    _lastShowSerial = request.serial;
    // Фокус уже в полосе цели: повторный переход ничего не меняет — ни фокуса,
    // ни прокрутки, ни подсветки, ни следования за хвостом (спецификация
    // «Переход к ожидающему одобрению с клавиатуры»). Показ закрываем в
    // следующем кадре: `didUpdateWidget` идёт в сборке, а хост меняет состояние.
    if (request.focusApproval && _approvalBarNode(request)?.hasFocus == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _showToken) return;
        widget.onShowRequestDone?.call(request.serial);
      });
      return;
    }
    _isReadingHistory = true;
    _isFollowingTail = false;
    _isKeepingApprovalInView = false;
    _highlightTimer?.cancel();
    _highlightId = null;
    _scheduleShowStep(request, token, 0);
  }

  void _scheduleShowStep(
    CodeLabTranscriptShowRequest request,
    int token,
    int attempt,
  ) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || token != _showToken || !_controller.hasClients) return;
        _showStep(request, token, attempt);
      })
      // `jumpTo` в ту же позицию кадра не вызовет, а цепочка ждёт кадра.
      ..scheduleFrame();
  }

  /// Один шаг показа. Ленивый список не знает высоту непостроенных строк, и
  /// строки нет в дереве, пока она далеко от окна: первый шаг прыгает по
  /// оценке смещения, дальше лента двигается к строке окнами, пока цель не
  /// построена, и тогда `ensureVisible` ставит её точно (D49 Т7).
  void _showStep(CodeLabTranscriptShowRequest request, int token, int attempt) {
    if (widget.showRequest?.serial != request.serial) return;
    final index = widget.rows.indexWhere((row) => row.id == request.rowId);
    if (index < 0) {
      widget.onShowRequestDone?.call(request.serial);
      return;
    }
    final target = _findKeyed(_targetKeyOf(request));
    if (target != null) {
      _reveal(target);
      _setHighlight(request.targetId);
      // Строки выше цели достроились и могли сдвинуть её: ещё один кадр
      // уточняет положение.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _showToken) return;
        final again = _findKeyed(_targetKeyOf(request));
        if (again != null) _reveal(again);
        // Запрос мог устареть между кадрами: фокус ставит только актуальный.
        if (request.focusApproval &&
            widget.showRequest?.serial == request.serial) {
          _focusApprovalBar(request);
        }
        widget.onShowRequestDone?.call(request.serial);
      });
      return;
    }
    if (attempt >= _maxShowAttempts) {
      widget.onShowRequestDone?.call(request.serial);
      return;
    }

    final position = _controller.position;
    final total = position.maxScrollExtent + position.viewportDimension;
    if (attempt == 0 &&
        _findKeyed(CodeLabTranscriptPanel.rowKey(request.rowId)) == null) {
      _controller.jumpTo(
        (total * index / widget.rows.length).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    } else if (_findKeyed(CodeLabTranscriptPanel.rowKey(request.rowId)) ==
        null) {
      // Строки нет в окне: идём туда, где она относительно построенных.
      final firstBuilt = _firstBuiltRowIndex();
      final direction = firstBuilt != null && index < firstBuilt ? -1 : 1;
      _controller.jumpTo(
        (position.pixels + direction * position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
    _scheduleShowStep(request, token, attempt + 1);
  }

  /// Ключ цели: строка верхнего уровня — её `rowKey`, иначе ключ цели внутри.
  static Key _targetKeyOf(CodeLabTranscriptShowRequest request) =>
      request.targetId == request.rowId
      ? CodeLabTranscriptPanel.rowKey(request.rowId)
      : CodeLabTranscriptPanel.targetKey(request.targetId);

  /// Узел фокуса полосы запроса, выбранного в [request], или `null`: запрос
  /// не назван или полосы с его ключом нет в построенном дереве. Ищется
  /// именно по ключу запроса, а не «первая полоса цели»: цель могла сменить
  /// запрос или нести под собой блок потомка (§9, D13).
  FocusNode? _approvalBarNode(CodeLabTranscriptShowRequest request) {
    final session = request.sessionId;
    final approval = request.approvalId;
    if (session == null || approval == null) return null;
    final prompt = _findKeyed(CodeLabApprovalPrompt.keyFor(session, approval));
    if (prompt is! Element || !prompt.mounted) return null;
    Element? bar;
    void visit(Element element) {
      if (bar != null) return;
      if (element.widget.key == CodeLabApprovalPrompt.barKey) {
        bar = element;
        return;
      }
      element.visitChildren(visit);
    }

    prompt.visitChildren(visit);
    final found = bar;
    if (found == null || !found.mounted) return null;
    return Focus.maybeOf(found, createDependency: false);
  }

  /// Ставит фокус на полосу решения запроса [request]; полосы нет — фокус не
  /// трогает. Фокус уже в полосе — тоже не трогает: перенос с кнопки на
  /// контейнер ломал бы текущий выбор пользователя.
  void _focusApprovalBar(CodeLabTranscriptShowRequest request) {
    final node = _approvalBarNode(request);
    if (node == null || node.hasFocus || !node.canRequestFocus) return;
    node.requestFocus();
  }

  void _reveal(BuildContext target) {
    Scrollable.ensureVisible(target, alignment: 0.1, duration: Duration.zero);
  }

  void _setHighlight(String id) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = id);
    _highlightTimer = Timer(_highlightDuration, () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  /// Элемент построенного виджета с этим ключом или `null`: ключи цели —
  /// `ValueKey`, не `GlobalKey`, поэтому ищем обходом построенных элементов
  /// (строк в окне немного: ленивый список).
  BuildContext? _findKeyed(Key key) {
    BuildContext? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  /// Наименьший индекс построенной сейчас строки ленты.
  int? _firstBuiltRowIndex() {
    int? first;
    void visit(Element element) {
      final key = element.widget.key;
      if (key is ValueKey<String> && key.value.startsWith('transcript-row-')) {
        final id = key.value.substring('transcript-row-'.length);
        final index = widget.rows.indexWhere((row) => row.id == id);
        if (index >= 0 && (first == null || index < first!)) first = index;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return first;
  }

  bool _isExpanded(CodeLabTranscriptRow row) {
    if (row is CodeLabToolCallRow && row.awaitsApproval) {
      return true;
    }
    return widget.expansionOverrides[row.id] ??
        _expandedByDefault(row, widget.viewMode);
  }

  void _toggle(String rowId, bool expanded) =>
      widget.onExpansionChanged?.call((rowId: rowId, expanded: expanded));

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CodeLabText(
            widget.emptyLabel ??
                codeLabStringsOf(context).codeLabTranscriptEmpty,
            role: CodeLabTextRole.caption,
          ),
        ),
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.only(
            top: _columnTopPadding,
            bottom: _columnBottomPadding,
          ),
          itemCount: widget.rows.length,
          itemBuilder: (context, index) {
            final row = widget.rows[index];
            final isLast = index == widget.rows.length - 1;
            return Align(
              key: CodeLabTranscriptPanel.rowKey(row.id),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kTranscriptColumnMaxWidth,
                ),
                child: Padding(
                  // Промежуток только между строками: у последней он
                  // сложился бы с нижним полем ленты.
                  padding: EdgeInsets.only(
                    left: _columnSidePadding,
                    right: _columnSidePadding,
                    bottom: isLast ? 0 : _rowGap,
                  ),
                  child: TranscriptTargetFrame(
                    id: row.id,
                    keyed: false,
                    highlighted: _highlightId == row.id,
                    child: _TranscriptRowView(
                      row: row,
                      markdownConfig: _markdownConfigFor(
                        FluentTheme.of(context),
                      ),
                      expanded: _isExpanded(row),
                      onToggle: (expanded) => _toggle(row.id, expanded),
                      // Вложенные строки дерева `agent` раскрываются теми же
                      // переопределениями по своему id; по умолчанию свёрнуты
                      // (D47 Т11).
                      nestedExpanded: (id) =>
                          widget.expansionOverrides[id] ?? false,
                      onNestedToggle: _toggle,
                      highlightedId: _highlightId,
                      onApprovalFocusReleased: widget.onApprovalFocusReleased,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Set<String> _pendingApprovalEntryIds(List<CodeLabTranscriptRow> rows) {
  return {
    for (final row in rows)
      if (row is CodeLabToolCallRow && row.awaitsApproval) row.id,
  };
}

/// Одна строка ленты: выбирает виджет по виду строки.
class _TranscriptRowView extends StatelessWidget {
  const _TranscriptRowView({
    required this.row,
    required this.markdownConfig,
    required this.expanded,
    required this.onToggle,
    required this.nestedExpanded,
    required this.onNestedToggle,
    this.highlightedId,
    this.onApprovalFocusReleased,
  });

  final String? highlightedId;
  final VoidCallback? onApprovalFocusReleased;
  final CodeLabTranscriptRow row;
  final CodeLabMarkdownConfig markdownConfig;
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final bool Function(String rowId) nestedExpanded;
  final void Function(String rowId, bool expanded) onNestedToggle;

  @override
  Widget build(BuildContext context) {
    return switch (row) {
      CodeLabUserRow(:final text) => _UserBubble(text: text),
      // Ответ агента — markdown (SMK-07, D3); огороженный ответ целиком
      // становится блоком кода внутри `CodeLabMarkdown` (D11).
      CodeLabAgentTextRow(:final id, :final text, :final streaming) => Align(
        alignment: Alignment.centerLeft,
        child: CodeLabMarkdown(
          id: id,
          text: text,
          streaming: streaming,
          config: markdownConfig,
        ),
      ),
      CodeLabThoughtRow(:final text, :final streaming) => CodeLabThoughtBlock(
        text: text,
        streaming: streaming,
        expanded: expanded,
        onToggle: onToggle,
      ),
      final CodeLabToolCallRow call => CodeLabToolCallTile(
        row: call,
        expanded: expanded,
        onToggle: onToggle,
        nestedExpanded: nestedExpanded,
        onNestedToggle: onNestedToggle,
        highlightedId: highlightedId,
        onApprovalFocusReleased: onApprovalFocusReleased,
      ),
      final CodeLabNoticeRow notice => CodeLabTranscriptNotice(row: notice),
      CodeLabTaskOpsRow(:final text) => CodeLabTaskOpsLine(text: text),
    };
  }
}

/// Сообщение пользователя — пузырь справа без подписи «You» (артборд Main).
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final factor = constraints.maxWidth < _narrowColumnWidth
            ? _narrowBubbleWidthFactor
            : _bubbleWidthFactor;
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * factor,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.accentColor.withAlpha(
                  theme.brightness == Brightness.dark ? 64 : 34,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: CodeLabText(text),
              ),
            ),
          ),
        );
      },
    );
  }
}
