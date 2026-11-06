import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';

import '../input/key_decoder.dart';
import '../input/terminal.dart';
import '../render/sanitize.dart';
import 'prompt_line.dart';

/// Итог построчного мастера провайдера.
///
/// Почему закрытая иерархия: вызывающему (`codelab provider add`, первый
/// запуск, `/provider add`) нужно по-разному ответить на запись, отмену и
/// отказ записи, а набор булевых флагов позволил бы невозможные сочетания
/// (AGENTS.md §8).
sealed class ProviderWizardResult {
  const ProviderWizardResult();
}

/// Провайдер записан в конфиг; [providerId] — id, под которым он сохранён.
final class ProviderWizardSaved extends ProviderWizardResult {
  const ProviderWizardSaved(this.providerId);

  final String providerId;
}

/// Пользователь отменил мастер (Ctrl+C, Esc, `n`, конец ввода): файлы не
/// изменены.
final class ProviderWizardCancelled extends ProviderWizardResult {
  const ProviderWizardCancelled();
}

/// Мастер не открылся: [message] — причина (идёт ход, нет терминала).
final class ProviderWizardRefused extends ProviderWizardResult {
  const ProviderWizardRefused(this.message);

  final String message;
}

/// Запись не удалась: [message] — строка для человека без значений секретов.
final class ProviderWizardFailed extends ProviderWizardResult {
  const ProviderWizardFailed(this.message);

  final String message;
}

/// Запускает построчный мастер на терминале и ждёт его итога.
///
/// Почему отдельная функция: подкоманда `codelab provider add` и первый
/// запуск (D16) владеют вводом сами, а `/provider add` в REPL подаёт клавиши
/// из подписки `Repl` (см. [LineWizard]); общая логика шагов — одна.
///
/// Как использовать: [flow] строит `run.dart` (`entry: cli`/`firstRun`);
/// [providerId] — позиционный id подкоманды, применяется на «Review» событием
/// `ReviewEdited(providerId:)`; [pathOf] даёт путь файла слоя для сводки.
/// Функция включает raw-режим, подписывается на `Terminal.input`, на любом
/// выходе отменяет подписку, восстанавливает терминал и освобождает [flow]
/// (значение ключа не переживает мастер, SETUP-1).
Future<ProviderWizardResult> runProviderWizard({
  required ProviderSetupFlow flow,
  required Terminal terminal,
  String? providerId,
  ConfigTarget? target,
  String Function(ConfigTarget target)? pathOf,
}) async {
  final wizard = LineWizard(
    flow: flow,
    output: terminal.output,
    providerId: providerId,
    target: target,
    pathOf: pathOf,
    columns: terminal.columns,
  );
  final decoder = KeyDecoder(wizard.onKey);
  final input = terminal.input.listen(
    decoder.add,
    onDone: () {
      decoder.close();
      wizard.inputClosed();
    },
  );
  // Raw-режим — после успешной подписки: иначе при сбое `listen` терминал
  // остался бы без эха.
  if (terminal.hasTerminal) {
    terminal.enableRawMode();
  }
  wizard.start();
  try {
    return await wizard.result;
  } finally {
    await input.cancel();
    decoder.close();
    terminal.restore();
    await wizard.dispose();
  }
}

/// Построчный мастер провайдера (артборд `CliSetup`, design.md D15, D17).
///
/// Почему отдельный класс с [onKey]: в REPL клавиши приходят из единственной
/// подписки `Repl` на `Terminal.input`, а вторая подписка на stdin запрещена
/// (D15, D16, D17); подкоманда и первый запуск подают те же события из своей
/// подписки.
///
/// Для чего: превращает состояния `ProviderSetupFlow` в вопросы и ответы
/// пользователя в события автомата. Состояния не хранит — источник правды
/// автомат; здесь только вид ввода текущего шага ([_mode]).
///
/// Как использовать: `start()`, затем `onKey` на каждую клавишу; [result]
/// завершается записью, отменой или отказом записи. Ключ вводится в скрытое
/// поле: на экране `*` по числу рун, Ctrl+R показывает и прячет, Ctrl+U
/// очищает (U-17); буфер не попадает в историю и сбрасывается при отправке.
final class LineWizard {
  LineWizard({
    required ProviderSetupFlow flow,
    required StringSink output,
    String? providerId,
    ConfigTarget? target,
    String Function(ConfigTarget target)? pathOf,
    int columns = 80,
  }) : _flow = flow,
       _out = output,
       _columns = columns,
       _pendingId = providerId,
       _pendingTarget = target,
       _pathOf = pathOf;

  final ProviderSetupFlow _flow;
  final StringSink _out;
  final String Function(ConfigTarget target)? _pathOf;
  final int _columns;
  Timer? _closeTimer;
  String? _pendingId;
  ConfigTarget? _pendingTarget;

  final _result = Completer<ProviderWizardResult>();
  StreamSubscription<ProviderSetupState>? _states;

  /// Вид ввода текущего шага; меняется только в [_render].
  _Mode _mode = const _Idle();

  /// Высота блока выбора на экране (для перерисовки стрелками).
  var _blockLines = 0;

  /// Хранилище, о котором шаг ключа сообщил последним (для сводки).
  String _backend = '';

  Future<ProviderWizardResult> get result => _result.future;

  void start() {
    _states = _flow.states.listen(_render);
    _render(_flow.current);
  }

  Future<void> dispose() async {
    _closeTimer?.cancel();
    _wipe();
    await _states?.cancel();
    await _flow.dispose();
  }

  /// Конец ввода терминала — как отмена. Во время записи мастер ждёт её итога
  /// (не дольше 10 с), чтобы не бросить запись на середине (D21).
  void inputClosed() {
    if (_mode is _Saving) {
      _closeTimer ??= Timer(const Duration(seconds: 10), () {
        _finish(const ProviderWizardCancelled());
      });
      return;
    }
    _flow.dispatch(const Cancel());
    _finish(const ProviderWizardCancelled());
  }

  /// Сбрасывает буфер поля: значение не переживает мастер (D17, SETUP-1).
  void _wipe() {
    if (_mode case final _LineMode mode) {
      mode.line.clear();
    }
  }

  void _finish(ProviderWizardResult result) {
    _closeTimer?.cancel();
    _wipe();
    if (!_result.isCompleted) {
      _result.complete(result);
    }
  }

  // --- вывод шагов ---------------------------------------------------------

  void _render(ProviderSetupState state) {
    if (_result.isCompleted) {
      return;
    }
    switch (state) {
      case ChoosingPreset(:final presets):
        _mode = _Pick(
          title: 'API type',
          labels: [for (final p in presets) p.label],
          onPick: (i) => _flow.dispatch(PresetChosen(presets[i].id)),
        );
        _drawPick();
      case EnteringBaseUrl(:final draft, :final error, :final insecureHost):
        if (error != null) {
          _say('  $error');
        }
        if (insecureHost != null) {
          _mode = _LineMode(
            prompt: '? Send the key unencrypted to $insecureHost? [y/N] ',
            onSubmit: (text) {
              if (text.trim().toLowerCase() == 'y') {
                _flow.dispatch(InsecureAddressConfirmed(draft.baseUrl ?? ''));
              } else {
                // Автомат остаётся на шаге адреса: спросить его заново.
                _render(EnteringBaseUrl(draft));
              }
            },
          );
        } else {
          _mode = _LineMode(
            prompt: '? Base URL › ',
            initial: draft.baseUrl ?? '',
            onSubmit: (text) => _flow.dispatch(BaseUrlSubmitted(text)),
          );
        }
        _drawLine();
      case final ChoosingKey key:
        _renderKey(key);
      case Checking(:final probeUrl):
        _mode = const _Idle();
        _out.write('Checking $probeUrl … ');
      case final CheckFailed failed:
        _renderCheckFailed(failed);
      case final ChoosingModel model:
        _renderModels(model);
      case EnteringModelDetails(
        :final modelId,
        :final suggestedContextWindow,
        :final error,
      ):
        if (error != null) {
          _say('  $error');
        }
        _mode = _LineMode(
          prompt: '? Context window for $modelId (tokens) › ',
          initial: '$suggestedContextWindow',
          // Проверка значения — у автомата (его ошибка покажется на шаге).
          onSubmit: (text) => _flow.dispatch(
            ModelDetailsSubmitted(
              contextWindow: int.tryParse(text.trim()) ?? 0,
            ),
          ),
        );
        _drawLine();
      case final Reviewing review:
        _renderReview(review);
      case Saving():
        _mode = const _Saving();
        _say('Saving…');
      case SaveFailed(:final failure):
        _say(_saveFailure(failure));
        _finish(ProviderWizardFailed(_saveFailure(failure)));
      case Done(:final plan):
        _mode = const _Idle();
        _finish(ProviderWizardSaved(plan.providerId));
      case Cancelled():
        _mode = const _Idle();
        _finish(const ProviderWizardCancelled());
    }
  }

  void _renderKey(ChoosingKey state) {
    if (!state.ready) {
      _mode = const _Idle();
      return;
    }
    _backend = state.backend.id;
    final id = state.draft.providerId;
    final secret = 'codelab/$id';
    if (state.notice case final notice?) {
      _say(notice);
    }
    if (state.error case final error?) {
      _say('  $error');
    }
    final labels = <String>[];
    final actions = <void Function()>[];
    if (state.canStoreSecret) {
      if (state.existingSecret case final existing?) {
        _say('A stored key $existing already exists in ${state.backend.id}.');
        if (state.canKeepStored) {
          labels.add('Use the stored key');
          actions.add(() => _submitKey(const KeepStoredSecret()));
        }
        labels.add('Replace it');
        actions.add(() => _askSecret(replace: true));
      } else {
        labels.add('Store in ${state.backend.id} as "$secret"');
        actions.add(() => _askSecret(replace: false));
      }
    } else {
      // Причина read-only бэкенда (D3) вместо варианта «Store…».
      _say(
        state.readOnlyHint ??
            state.backend.unavailableReason ??
            'The secret store is read-only.',
      );
    }
    final env = state.suggestedEnvVar;
    labels.add(
      env == null
          ? 'Read from an environment variable'
          : 'Read from environment variable ($env)',
    );
    actions.add(env == null ? _askEnvName : () => _submitKey(UseEnvVar(env)));
    labels.add('No key');
    actions.add(() => _submitKey(const NoKey()));
    _mode = _Pick(
      title: 'API key source',
      labels: labels,
      onPick: (i) => actions[i](),
    );
    _drawPick();
  }

  void _submitKey(KeyChoice choice, {bool replace = false}) {
    _flow.dispatch(KeySubmitted(choice, replaceExisting: replace));
  }

  void _askEnvName() {
    _mode = _LineMode(
      prompt: '? Environment variable › ',
      onSubmit: (text) => _submitKey(UseEnvVar(text.trim())),
    );
    _drawLine();
  }

  void _askSecret({required bool replace}) {
    _mode = _LineMode(
      prompt: '? API key › ',
      hidden: true,
      onReject: () {
        _say(keyRejectedLine);
        _askSecret(replace: replace);
      },
      onSubmit: (text) {
        if (text.isEmpty) {
          _say('Enter the API key.');
          _askSecret(replace: replace);
          return;
        }
        _submitKey(StoreSecret(SecretValue(text)), replace: replace);
      },
    );
    _drawLine();
  }

  void _renderCheckFailed(CheckFailed state) {
    final failure = state.failure;
    final title = switch (failure.kind) {
      ProviderCheckFailureKind.unauthorized =>
        'Key rejected (${failure.statusCode ?? 401})',
      ProviderCheckFailureKind.unreachable => 'Server unreachable',
      ProviderCheckFailureKind.timeout => 'Timed out after 10 s',
      ProviderCheckFailureKind.tlsError => 'TLS error',
      ProviderCheckFailureKind.notFound =>
        'Model list not found (${failure.statusCode ?? 404})',
      ProviderCheckFailureKind.badResponse =>
        'Unexpected response (${failure.statusCode ?? '?'})',
    };
    _say('failed: $title');
    final labels = <String>['Retry'];
    final actions = <void Function()>[() => _flow.dispatch(const RetryCheck())];
    if (state.canUseV1) {
      labels.add('Use the address with /v1');
      actions.add(() => _flow.dispatch(const UseV1Address()));
    }
    if (failure.kind == ProviderCheckFailureKind.notFound) {
      labels.add('Enter model id manually');
      actions.add(_askModelId);
    }
    if (state.canSkip) {
      labels.add('Continue without checking');
      actions.add(() => _flow.dispatch(const SkipCheck(confirmed: true)));
    }
    labels.add('Back');
    actions.add(() => _flow.dispatch(const Back()));
    _mode = _Pick(
      title: 'The check failed',
      labels: labels,
      onPick: (i) => actions[i](),
    );
    _drawPick();
  }

  void _askModelId() {
    _mode = _LineMode(
      prompt: '? Model id › ',
      onSubmit: (text) {
        if (text.trim().isEmpty) {
          _askModelId();
          return;
        }
        _flow.dispatch(ModelEnteredManually(text.trim()));
      },
    );
    _drawLine();
  }

  void _renderModels(ChoosingModel state) {
    _say(
      state.checked
          ? 'ok, ${state.models.length} models'
          : 'not verified; the model list is unknown',
    );
    if (state.models.isEmpty) {
      _askModelId();
      return;
    }
    final ids = [for (final m in state.models) m.id];
    _mode = _Filter(
      ids: ids,
      onModel: (id) => _flow.dispatch(ModelChosen(id)),
      onManual: _askModelId,
      selected: state.currentModel == null
          ? 0
          : ids.indexOf(state.currentModel!).clamp(0, ids.length - 1),
    );
    _drawFilter();
  }

  void _renderReview(Reviewing state) {
    if ((_pendingId != null || _pendingTarget != null) && state.error == null) {
      // Позиционный id и `--local` подкоманды применяются один раз (D15).
      final (id, target) = (_pendingId, _pendingTarget);
      _pendingId = _pendingTarget = null;
      _flow.dispatch(ReviewEdited(providerId: id, target: target));
      return;
    }
    reviewSummary(
      state.plan,
      backend: _backend,
      path: _pathOf?.call(state.plan.target),
    ).forEach(_say);
    for (final warning in state.warnings) {
      _say('  $warning');
    }
    if (state.error case final error?) {
      _say('  $error');
      if (state.refusal != null) {
        _finish(ProviderWizardFailed(error));
        return;
      }
    }
    _mode = _LineMode(
      prompt: '? Save? [Y/n] ',
      onSubmit: (text) {
        switch (text.trim().toLowerCase()) {
          case '' || 'y' || 'yes':
            _flow.dispatch(const ConfirmSave());
          case 'n' || 'no':
            _flow.dispatch(const Cancel());
          default:
            _drawLine();
        }
      },
    );
    _drawLine();
  }

  String _saveFailure(ProviderConfigNotSaved failure) =>
      saveFailureText(failure);

  // --- ввод ----------------------------------------------------------------

  /// Клавиша терминала. Ctrl+C и Esc отменяют мастер, кроме записи (D21).
  void onKey(KeyEvent event) {
    if (_result.isCompleted) {
      return;
    }
    final mode = _mode;
    if (mode is _Saving) {
      return;
    }
    if (mode is _LineMode && mode.submitting) {
      mode.trailing = true;
      return;
    }
    if (event case SpecialKey(key: Key.ctrlC || Key.escape)) {
      _flow.dispatch(const Cancel());
      return;
    }
    switch (mode) {
      case _Idle() || _Saving():
        return;
      case final _LineMode line:
        _onLineKey(line, event);
      case final _Pick pick:
        _onPickKey(pick, event);
      case final _Filter filter:
        _onFilterKey(filter, event);
    }
  }

  void _onLineKey(_LineMode mode, KeyEvent event) {
    final line = mode.line;
    switch (applyLineKey(line, event)) {
      case LineKey.edited:
        _drawLine(redraw: true);
      case LineKey.submit:
        final text = line.text;
        _out.write('\n');
        line.clear();
        if (!line.hidden) {
          mode.onSubmit(text);
          return;
        }
        // Остаток чтения после Enter — вставка нескольких строк: ключ не
        // принимается (D14). Решение — после разбора всего чтения.
        mode.submitting = true;
        scheduleMicrotask(() {
          mode.submitting = false;
          if (_result.isCompleted || !identical(_mode, mode)) {
            return;
          }
          if (mode.trailing) {
            mode.onReject?.call();
          } else {
            mode.onSubmit(text);
          }
        });
      case LineKey.multiline:
        _out.write('\n');
        line.clear();
        mode.onReject?.call();
      case LineKey.cancel:
        // Ctrl+C и Esc обработаны выше; сюда доходит Ctrl+D.
        _flow.dispatch(const Cancel());
      case LineKey.ignored:
        break;
    }
  }

  void _onPickKey(_Pick pick, KeyEvent event) {
    if (event case SpecialKey(:final key)) {
      switch (key) {
        case Key.up:
          pick.move(-1);
          _drawPick(redraw: true);
        case Key.down:
          pick.move(1);
          _drawPick(redraw: true);
        case Key.enter:
          pick.onPick(pick.selected);
        case _:
          break;
      }
    }
  }

  void _onFilterKey(_Filter filter, KeyEvent event) {
    switch (event) {
      case TextKey(:final text):
        filter.insert(text);
        _drawFilter(redraw: true);
      case SpecialKey(:final key):
        switch (key) {
          case Key.up:
            filter.move(-1);
            _drawFilter(redraw: true);
          case Key.down:
            filter.move(1);
            _drawFilter(redraw: true);
          case Key.backspace:
            filter.backspace();
            _drawFilter(redraw: true);
          case Key.ctrlU:
            filter.clear();
            _drawFilter(redraw: true);
          case Key.enter:
            _out.write('\n');
            filter.choose();
          case _:
            break;
        }
    }
  }

  // --- рисование -----------------------------------------------------------

  void _say(String text) => _out.write('${sanitizeTerminalText(text)}\n');

  void _drawLine({bool redraw = false}) {
    (_mode as _LineMode).line.draw(_out, columns: _columns, redraw: redraw);
  }

  void _drawPick({bool redraw = false}) {
    final pick = _mode as _Pick;
    if (redraw) {
      _out.write('\x1b[${_blockLines}A\r\x1b[J');
    }
    _out.write('? ${sanitizeTerminalText(pick.title)}\n');
    for (final (i, label) in pick.labels.indexed) {
      _out.write(
        '${i == pick.selected ? '  › ' : '    '}${sanitizeTerminalText(label)}\n',
      );
    }
    _blockLines = pick.labels.length + 1;
  }

  void _drawFilter({bool redraw = false}) {
    final filter = _mode as _Filter;
    if (redraw) {
      _out.write('\x1b[${_blockLines}A\r\x1b[J');
    }
    _out.write(
      '? Model (type to filter) › ${sanitizeTerminalText(filter.text)}\n',
    );
    final (start, rows) = filter.visible;
    for (final (i, label) in rows.indexed) {
      _out.write(
        '${start + i == filter.cursor ? '  › ' : '    '}'
        '${sanitizeTerminalText(label)}\n',
      );
    }
    _blockLines = rows.length + 1;
  }
}

sealed class _Mode {
  const _Mode();
}

final class _Idle extends _Mode {
  const _Idle();
}

final class _Saving extends _Mode {
  const _Saving();
}

/// Поле ввода шага: [line] — буфер и маска, [onSubmit] получает строку.
final class _LineMode extends _Mode {
  _LineMode({
    required String prompt,
    required this.onSubmit,
    this.onReject,
    String initial = '',
    bool hidden = false,
  }) : line = PromptLine(prompt: prompt, initial: initial, hidden: hidden);

  final PromptLine line;
  final void Function(String text) onSubmit;

  /// Что делать с отклонённым значением (вставка нескольких строк, слишком
  /// длинный ключ); `null` — перерисовать поле.
  final void Function()? onReject;

  /// Enter принят, решение откладывается до конца разбора чтения.
  var submitting = false;
  var trailing = false;
}

/// Список со стрелками.
final class _Pick extends _Mode {
  _Pick({required this.title, required this.labels, required this.onPick});

  final String title;
  final List<String> labels;
  final void Function(int index) onPick;
  var selected = 0;

  void move(int delta) =>
      selected = (selected + delta).clamp(0, labels.length - 1);
}

/// Выбор модели: фильтр по подстроке и пункт ручного ввода.
final class _Filter extends _Mode {
  _Filter({
    required this.ids,
    required this.onModel,
    required this.onManual,
    required int selected,
  }) : cursor = selected;

  static const _window = 8;
  static const manualLabel = 'Enter model id manually';

  final List<String> ids;
  final void Function(String id) onModel;
  final void Function() onManual;
  var text = '';
  int cursor;

  List<String> get _matches => [
    for (final id in ids)
      if (id.toLowerCase().contains(text.toLowerCase())) id,
  ];

  /// Строки списка: найденные модели и в конце ручной ввод.
  List<String> get _rows => [..._matches, manualLabel];

  /// Окно списка: индекс первой видимой строки и сами строки.
  (int, List<String>) get visible {
    final rows = _rows;
    cursor = cursor.clamp(0, rows.length - 1);
    final start = (cursor - _window + 1).clamp(0, rows.length);
    return (
      start,
      rows.sublist(start, (start + _window).clamp(0, rows.length)),
    );
  }

  void insert(String value) {
    text += String.fromCharCodes(value.runes.where((r) => r >= 0x20));
    cursor = 0;
  }

  void backspace() {
    if (text.isNotEmpty) {
      text = String.fromCharCodes(text.runes.toList()..removeLast());
      cursor = 0;
    }
  }

  void clear() {
    text = '';
    cursor = 0;
  }

  void move(int delta) => cursor = (cursor + delta).clamp(0, _rows.length - 1);

  void choose() {
    final rows = _rows;
    final index = cursor.clamp(0, rows.length - 1);
    if (index == rows.length - 1) {
      onManual();
    } else {
      onModel(rows[index]);
    }
  }
}

/// Сводка плана перед записью (артборд `CliSetup`): провайдер, источник
/// ключа, модель и файл. [backend] — хранилище секретов, [path] — файл слоя.
/// Значение ключа в сводку не попадает (SETUP-1).
List<String> reviewSummary(
  ProviderSetupPlan plan, {
  required String backend,
  String? path,
}) {
  final keyText = switch (plan.key) {
    StoreSecret() ||
    KeepStoredSecret() => 'secret "${plan.secretName}" ($backend)',
    UseEnvVar(:final name) => 'env $name',
    NoKey() => 'none',
  };
  return [
    'Provider "${plan.providerId}"',
    '  (${plan.kind}${plan.baseUrl == null ? '' : ', ${(displayBaseUrl(plan.baseUrl) ?? '')}'})',
    '  key    $keyText',
    '  model  ${plan.providerId}/${plan.model.id}'
        '${plan.makeDefault ? ' (default)' : ''}',
    if (path != null) '  file   $path',
  ];
}

/// Строка об отказе записи без значений секретов (D9).
String saveFailureText(ProviderConfigNotSaved failure) =>
    switch (failure.outcome) {
      ConfigConflict() => 'The config file changed; run the command again.',
      ConfigRejected(:final issues) =>
        'The config was rejected: ${issues.map((i) => i.message).join('; ')}',
      ConfigInlineSecret() => 'The config does not accept a literal key.',
      _ => 'Could not save the provider (${failure.errorType ?? 'error'}).',
    };
