/// Состояние страницы «Providers» (design.md change `add-provider-setup-ui`,
/// D10, D21; spec app-settings «Страница «Providers»»).
///
/// Почему закрытая иерархия, а не набор флагов: страница либо загружается,
/// либо только читает (WebSocket и сторонний агент, SETUP-2), либо не может
/// прочитать `config.yaml`, либо готова к правкам; невозможные сочетания
/// («только чтение» со строками провайдеров) не представимы
/// (`state-management.md`, AGENTS.md §8).
///
/// Для чего: чистые значения для отображения. Ни значений ключей, ни тел
/// ответов `/models` здесь нет — только то, что видит пользователь (SETUP-1).
sealed class ProviderSettingsState {
  const ProviderSettingsState();
}

/// Доступ к настройкам ещё определяется или конфиг читается.
final class ProviderSettingsLoading extends ProviderSettingsState {
  const ProviderSettingsLoading();
}

/// Любое состояние после первой загрузки: общие поля.
sealed class ProviderSettingsLoaded extends ProviderSettingsState {
  const ProviderSettingsLoaded({this.activeModel});

  /// Значение опции `model` активной сессии (`Active in this session`);
  /// `null` — сессии или опции нет.
  final String? activeModel;
}

/// Агент не наш или удалённый: настройки не читаются и не пишутся (SETUP-2).
final class ProviderSettingsReadOnly extends ProviderSettingsLoaded {
  const ProviderSettingsReadOnly({
    required this.notice,
    this.hint,
    super.activeModel,
  });

  /// Заголовок InfoBar: `Read-only: this agent runs on <origin>.` или
  /// `Provider settings are managed by <agent>.`
  final String notice;

  /// Команды для хоста агента; у стороннего агента `null`.
  final String? hint;

  @override
  String toString() => 'ProviderSettingsReadOnly($notice)';
}

/// `config.yaml` не разбирается или нарушает схему: запись недоступна, файл
/// не перезаписывается (целостность данных, AGENTS.md §2).
final class ProviderSettingsUnreadable extends ProviderSettingsLoaded {
  const ProviderSettingsUnreadable({required this.problems, super.activeModel});

  /// Проблемы загрузчика с путём ключа, по строке на проблему.
  final List<String> problems;

  @override
  String toString() => 'ProviderSettingsUnreadable(${problems.length})';
}

/// Вид баннера результата записи.
enum ProviderBannerKind { saved, conflict, error }

/// Баннер результата записи (ключ `providers-banner`).
final class ProviderBanner {
  const ProviderBanner(this.kind, this.text);

  final ProviderBannerKind kind;
  final String text;

  @override
  String toString() => 'ProviderBanner(${kind.name})';
}

/// Вид итога проверки для цвета тега.
enum ProviderCheckKind { notChecked, running, ok, failed, keyMissing }

/// Итог последней проверки провайдера: UI-состояние страницы, в файл не
/// пишется (D10).
final class ProviderCheckView {
  const ProviderCheckView._(this.kind, this.label, this.detail);

  /// «Not checked» — проверок за жизнь страницы не было.
  const ProviderCheckView.notChecked()
    : this._(ProviderCheckKind.notChecked, 'not checked', 'Not checked yet');

  /// Запрос идёт.
  const ProviderCheckView.running()
    : this._(ProviderCheckKind.running, 'checking…', 'Checking…');

  /// `ok, <n> models`; [detail] — `14:01 · 12 models · 184 ms`.
  factory ProviderCheckView.ok({
    required int models,
    required int durationMs,
    required DateTime at,
  }) => ProviderCheckView._(
    ProviderCheckKind.ok,
    'ok, ${_models(models)}',
    '${_clock(at)} · ${_models(models)} · $durationMs ms',
  );

  /// Отказ с тегом [label] (`unauthorized`, `timeout`…); [status] — код HTTP.
  factory ProviderCheckView.failed({
    required String label,
    required DateTime at,
    int? status,
  }) => ProviderCheckView._(
    ProviderCheckKind.failed,
    label,
    '${_clock(at)} · $label${status == null ? '' : ' (HTTP $status)'}',
  );

  /// Ключ не найден: запрос не отправлялся.
  const ProviderCheckView.keyMissing()
    : this._(
        ProviderCheckKind.keyMissing,
        'Key: missing',
        'Not checked: the key is missing',
      );

  final ProviderCheckKind kind;

  /// Текст тега.
  final String label;

  /// Текст строки «Last check» раскрытой карточки.
  final String detail;

  static String _models(int n) => n == 1 ? '1 model' : '$n models';

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  @override
  String toString() => 'ProviderCheckView(${kind.name}, $label)';
}

/// Строка провайдера (Expander).
final class ProviderRow {
  const ProviderRow({
    required this.id,
    required this.subtitle,
    required this.keyLabel,
    required this.keyText,
    this.keyMono,
    required this.source,
    required this.isDefault,
    required this.editable,
    required this.canRemove,
    this.removeHint,
    this.canCheck = true,
    this.checkHint,
    this.keyHint,
    this.unencryptedHost,
    required this.check,
  });

  final String id;

  /// `<id> · <kind> · [<base_url> ·] Key: … · <n> model(s)[ · defined in …]`.
  final String subtitle;

  /// Статус ключа без значения: `Key: in file`.
  final String keyLabel;

  /// Строка «Key» раскрытой карточки: текст и моноширинная часть.
  final String keyText;
  final String? keyMono;

  /// Строка «Source» раскрытой карточки.
  final String source;

  /// У провайдера модель по умолчанию — тег «Default».
  final bool isDefault;

  /// Слои `user` и `projectLocal`; иначе «Edit» и «Remove» нет (SETUP-3).
  final bool editable;

  /// «Remove» доступна: редактируемый и не последний.
  final bool canRemove;

  /// Подсказка неактивной «Remove» (последний провайдер).
  final String? removeHint;

  /// «Check» доступна. У литерального ключа в `config.yaml` нет: app его не
  /// читает (SETUP-1), запрос без ключа дал бы заведомый отказ.
  final bool canCheck;

  /// Почему Check недоступна для вида провайдера (мост не умеет проверять).
  final String? checkHint;

  /// Подсказка под строкой (литеральный ключ → `codelab secret migrate`).
  final String? keyHint;

  /// Хост, к которому ключ уходит открытым текстом (`http://` к нелокальному
  /// хосту, SETUP-10); `null` — предупреждения нет. Check остаётся доступной.
  final String? unencryptedHost;

  final ProviderCheckView check;

  ProviderRow withCheck(ProviderCheckView next) => ProviderRow(
    id: id,
    subtitle: subtitle,
    keyLabel: keyLabel,
    keyText: keyText,
    keyMono: keyMono,
    source: source,
    isDefault: isDefault,
    editable: editable,
    canRemove: canRemove,
    removeHint: removeHint,
    canCheck: canCheck,
    checkHint: checkHint,
    keyHint: keyHint,
    unencryptedHost: unencryptedHost,
    check: next,
  );

  @override
  String toString() => 'ProviderRow($id, $keyLabel)';
}

/// Строка «Key storage» (D3).
final class KeyStorageView {
  const KeyStorageView({
    required this.backendId,
    required this.writable,
    this.unavailableReason,
    this.openFilePath,
  });

  final String backendId;
  final bool writable;

  /// Причина, по которой хранилище ОС недоступно; `null` — нет причины.
  final String? unavailableReason;

  /// Путь открытого файла секретов для бэкенда `file`.
  final String? openFilePath;

  @override
  String toString() => 'KeyStorageView($backendId, writable: $writable)';
}

/// Страница готова: строки, «Default model», хранилище.
final class ProviderSettingsReady extends ProviderSettingsLoaded {
  const ProviderSettingsReady({
    required this.rows,
    required this.models,
    required this.defaultModel,
    required this.keyStorage,
    required this.configPath,
    this.saving = false,
    this.banner,
    super.activeModel,
  });

  final List<ProviderRow> rows;

  /// Модели каталога всех провайдеров для «Default model», по порядку.
  final List<String> models;

  /// Эффективное `agent.default_model`.
  final String? defaultModel;

  final KeyStorageView keyStorage;

  /// Пользовательский `config.yaml` для подвала `Config file: <path>`.
  final String configPath;

  /// Идёт запись: повторные действия блокируются (D21).
  final bool saving;

  final ProviderBanner? banner;

  ProviderSettingsReady copyWith({
    List<ProviderRow>? rows,
    bool? saving,
    ProviderBanner? Function()? banner,
    String? Function()? activeModel,
  }) => ProviderSettingsReady(
    rows: rows ?? this.rows,
    models: models,
    defaultModel: defaultModel,
    keyStorage: keyStorage,
    configPath: configPath,
    saving: saving ?? this.saving,
    banner: banner == null ? this.banner : banner(),
    activeModel: activeModel == null ? this.activeModel : activeModel(),
  );

  @override
  String toString() =>
      'ProviderSettingsReady(${rows.length} rows, saving: $saving)';
}

/// План удаления для диалога `Remove provider <id>?` (D10).
final class ProviderRemovalPlan {
  const ProviderRemovalPlan({
    required this.providerId,
    required this.offersKeyDeletion,
    required this.needsNewDefault,
    required this.newDefaultChoices,
  });

  final String providerId;

  /// Показать флажок «Also delete the stored key» (включён по умолчанию).
  final bool offersKeyDeletion;

  /// Удаляется провайдер модели по умолчанию: нужен выбор новой.
  final bool needsNewDefault;

  /// Модели остальных провайдеров для выбора.
  final List<String> newDefaultChoices;
}
