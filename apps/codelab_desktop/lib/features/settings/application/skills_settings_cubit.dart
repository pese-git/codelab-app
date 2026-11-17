import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        Connected,
        ConnectionProfile,
        EmbeddedProfile,
        Reconnecting,
        StdioProfile,
        WebSocketProfile,
        WorkspaceState,
        profileOrigin;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/local_folder_opener.dart';
import 'provider_settings_session.dart';
import 'skills_settings_state.dart';

export 'provider_settings_session.dart';
export 'skills_settings_state.dart';

/// Страница «Skills & extensions»: файлы контекста, навыки и шаблоны агента
/// текущего подключения (change `add-app-skills-page`, D2, D6, D8, D10, D14).
///
/// Почему: один владелец данных страницы. Что агент загрузит из папки,
/// считает мост `codelab_setup` (`readAgentExtensions` через порт сессии
/// настроек); Cubit только решает, чьи это настройки и какая папка, вызывает
/// порт и превращает итог в [SkillsSettingsState] (`AGENTS.md` §7, §10).
///
/// Для чего: для WebSocket и стороннего агента локальные файлы НЕ читаются
/// (SETUP-2) — [SkillsSettingsReadOnly]; без папки — [SkillsSettingsNoFolder];
/// не читающийся конфиг — [SkillsSettingsUnreadable]. События журнала (D10) —
/// только виды, числа и имена типов: без путей, описаний и текстов исключений.
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы, страница зовёт [reload] и закрывает Cubit вместе с собой. Cubit
/// сам перечитывает страницу при смене профиля подключения или папки;
/// результат устаревшей загрузки отбрасывается по номеру загрузки
/// (`load_discarded`, `AGENTS.md` §9). Подписка на `ClientWorkspace.state`
/// одна, [close] её отменяет. Каталог для [openFolder] берётся только из
/// показанного вида (Q5), а не из ввода.
class SkillsSettingsCubit extends Cubit<SkillsSettingsState> {
  SkillsSettingsCubit({
    required ClientWorkspace workspace,
    required Future<ConnectionProfile> Function() defaultProfile,
    required ProviderSettingsOpener open,
    required Map<String, String> environment,
    required String? codelabHome,
    required String? Function() projectDirectory,
    required LocalFolderOpener folderOpener,
    Logger? logger,
  }) : _workspace = workspace,
       _defaultProfile = defaultProfile,
       _open = open,
       _environment = environment,
       _codelabHome = codelabHome,
       _projectDirectory = projectDirectory,
       _folderOpener = folderOpener,
       _logger = logger,
       super(const SkillsSettingsLoading()) {
    _accessProfile = _connectedProfile(_workspace.current);
    _folder = _normalized(_projectDirectory());
    _workspaceSubscription = _workspace.state.listen(_onWorkspace);
  }

  final ClientWorkspace _workspace;
  final Future<ConnectionProfile> Function() _defaultProfile;
  final ProviderSettingsOpener _open;
  final Map<String, String> _environment;
  final String? _codelabHome;

  /// Папка страницы: папка сессии в фокусе, без неё — выбранный проект (D2).
  final String? Function() _projectDirectory;
  final LocalFolderOpener _folderOpener;
  final Logger? _logger;

  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Профиль и папка, для которых страница прочитана: их смена — повод
  /// перечитать.
  ConnectionProfile? _accessProfile;
  String? _folder;

  /// Номер загрузки: результат после более новой загрузки или [close]
  /// отбрасывается (D14).
  var _loadAttempt = 0;

  /// `CODELAB_HOME` профиля текущей загрузки; уходит в состояние (Q4).
  String? _profileHome;

  /// Каталоги, которые страница показывает; только их можно открыть (Q5).
  Set<String> _openable = const {};

  /// Сессия настроек и папка снимка последней успешной загрузки: по ним
  /// пишутся `skills.*` (D5). `null` — страница не для записи.
  ProviderSettingsSession? _session;
  String? _snapshotCwd;

  /// Идёт запись `skills.*`: повторные действия игнорируются (D14).
  var _saving = false;

  /// Баннер исхода записи: ложится на состояние, которое соберёт ближайшая
  /// не устаревшая загрузка, чтобы баннер пережил перечитывание.
  SkillsBanner? _pendingBanner;

  /// Читает доступ, конфиг и файлы; вызывается при открытии страницы,
  /// «Reload» и при смене профиля или папки.
  Future<void> reload() async {
    final attempt = ++_loadAttempt;
    _accessProfile = _connectedProfile(_workspace.current);
    _folder = _normalized(_projectDirectory());
    final folder = _folder;
    final ConnectionProfile profile;
    try {
      profile = _accessProfile ?? await _defaultProfile();
    } on Object catch (error) {
      if (_stale(attempt)) {
        return;
      }
      // Чтение профилей по умолчанию тоже может упасть (файл профилей); текст
      // исключения не идёт ни в состояние, ни в журнал (D10).
      _logger?.warning(
        'skills_settings.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(const ['Cannot read the agent settings.'], log: false);
      return;
    }
    if (_stale(attempt)) {
      return;
    }
    switch (_accessOf(profile, folder)) {
      case RemoteReadOnly(:final endpoint):
        _setReadOnly(
          notice: 'Read-only: this agent runs on ${profileOrigin(endpoint)}.',
          hint:
              'Its skills, context files and prompt templates are read on '
              'that host: codelab-agent config check.',
          access: 'remote',
        );
      case NotManaged(:final agentName):
        _setReadOnly(
          notice: 'Skills are managed by $agentName.',
          access: 'not_managed',
        );
      case EditableSettings access:
        await _loadEditable(attempt, profile, access, folder);
    }
  }

  SettingsAccess _accessOf(ConnectionProfile profile, String? cwd) {
    final home = _codelabHome ?? '';
    return switch (profile) {
      EmbeddedProfile() => resolveSettingsAccess(
        kind: AgentLaunchKind.embedded,
        cwd: cwd,
        defaultCodelabHome: home,
      ),
      StdioProfile(:final command, :final args, :final env) =>
        resolveSettingsAccess(
          kind: AgentLaunchKind.stdio,
          command: command,
          args: args,
          env: env,
          cwd: profile.runInProjectDirectory ? cwd : null,
          defaultCodelabHome: home,
        ),
      WebSocketProfile(:final uri) => resolveSettingsAccess(
        kind: AgentLaunchKind.webSocket,
        endpoint: uri,
        defaultCodelabHome: home,
      ),
    };
  }

  void _setReadOnly({
    required String notice,
    String? hint,
    required String access,
  }) {
    _profileHome = null;
    _session = null;
    _openable = const {};
    _logger?.debug('skills_settings.read_only', context: {'access': access});
    _emit(SkillsSettingsReadOnly(notice: notice, hint: hint));
  }

  Future<void> _loadEditable(
    int attempt,
    ConnectionProfile profile,
    EditableSettings access,
    String? folder,
  ) async {
    _profileHome = access.paths.codelabHome.isEmpty
        ? null
        : access.paths.codelabHome;
    if (_profileHome == null) {
      _setUnreadable(const ['The CodeLab home folder is not available.']);
      return;
    }
    if (folder == null) {
      _openable = const {};
      _emit(SkillsSettingsNoFolder(codelabHome: _profileHome));
      return;
    }
    final environment = {
      ..._environment,
      if (profile is StdioProfile) ...profile.env,
    };
    final AgentConfigSnapshot snapshot;
    final AgentExtensionsView view;
    final ProviderSettingsSession session;
    try {
      session = await _open(access, environment);
      snapshot = await session.config.snapshot(
        cwd: access.cwd ?? access.paths.codelabHome,
      );
      if (snapshot.issues.isNotEmpty ||
          !snapshot.isReadable(ConfigLayer.user)) {
        if (_stale(attempt)) {
          return;
        }
        _setUnreadable([
          for (final issue in snapshot.issues) issue.toString(),
          if (snapshot.issues.isEmpty) 'The user config.yaml cannot be read.',
        ], issues: snapshot.issues.length);
        return;
      }
      view = await session.extensions(snapshot);
    } on Object catch (error) {
      if (_stale(attempt)) {
        return;
      }
      // Текст исключения может содержать путь или фрагмент файла: наружу идёт
      // только имя типа (D10, `AGENTS.md` §16).
      _logger?.warning(
        'skills_settings.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(const [
        'Cannot read the skills and extensions of this folder.',
      ], log: false);
      return;
    }
    if (_stale(attempt)) {
      return;
    }
    _openable = _openableOf(view);
    _session = session;
    _snapshotCwd = access.cwd ?? access.paths.codelabHome;
    _logLoaded(view);
    final banner = _pendingBanner;
    _pendingBanner = null;
    _emit(
      SkillsSettingsReady(
        view: view,
        userConfigPath: snapshot.layers[ConfigLayer.user]?.path,
        folder: folder,
        codelabHome: _profileHome,
        banner: banner,
        saving: _saving,
      ),
    );
  }

  void _setUnreadable(List<String> problems, {int? issues, bool log = true}) {
    _openable = const {};
    if (log) {
      _logger?.warning(
        'skills_settings.unreadable',
        context: {'issues': issues ?? problems.length},
      );
    }
    _emit(SkillsSettingsUnreadable(problems: problems));
  }

  /// Результат устаревшей загрузки не применяется (D14).
  bool _stale(int attempt) {
    if (isClosed || attempt != _loadAttempt) {
      _logger?.debug('skills_settings.load_discarded');
      return true;
    }
    return false;
  }

  void _logLoaded(AgentExtensionsView view) {
    final skills = view.skills.entries;
    final disabled = skills
        .where((e) => e.availability == SkillAvailability.disabled)
        .length;
    _logger?.debug(
      'skills_settings.loaded',
      context: {
        'access': 'editable',
        'trusted': view.trusted,
        'context_files': view.context.files.length,
        'skills': skills.length - disabled,
        'disabled': disabled,
        'templates': view.templates.entries.length,
        'warnings':
            view.context.warnings.length +
            view.skills.warnings.length +
            view.templates.warnings.length,
      },
    );
    // Одна фаза файлов проекта даёт исход и цепочке, и шаблонам (D4).
    _logPhase('project_files', view.context.outcome);
    _logPhase('skills', view.skills.outcome);
  }

  void _logPhase(String phase, SectionOutcome outcome) {
    final reason = switch (outcome) {
      SectionTimedOut() => 'timeout',
      SectionFailed(:final errorType) => errorType,
      _ => null,
    };
    if (reason != null) {
      _logger?.warning(
        'skills_settings.phase_failed',
        context: {'phase': phase, 'reason': reason},
      );
    }
  }

  /// Каталоги, которые показывает вид: только их страница может открыть.
  Set<String> _openableOf(AgentExtensionsView view) => {
    for (final file in view.context.files) ?file.openDir,
    for (final skill in view.skills.entries) skill.directory,
    for (final template in view.templates.entries)
      p.dirname(template.sourcePath),
  };

  // --- Открытие каталогов ---------------------------------------------------

  /// «Open .codelab folder»: `<папка>/.codelab`, а если каталога нет —
  /// `CODELAB_HOME` профиля (Q4). Существование проверяет порт, не Cubit.
  Future<void> openCodelabFolder() async {
    // Папка и `CODELAB_HOME` берутся из ПОКАЗАННОГО состояния, а не из более
    // новой идущей загрузки: кнопка открывает то, что видит пользователь.
    final (String? folder, String? home) = switch (state) {
      SkillsSettingsReady(:final folder, :final codelabHome) => (
        folder,
        codelabHome,
      ),
      SkillsSettingsNoFolder(:final codelabHome) => (null, codelabHome),
      _ => (null, null),
    };
    if (isClosed ||
        (state is! SkillsSettingsReady && state is! SkillsSettingsNoFolder)) {
      return;
    }
    final candidates = [if (folder != null) p.join(folder, '.codelab'), ?home];
    String? attempted;
    var outcome = FolderOpenOutcome.missing;
    for (final path in candidates) {
      attempted = path;
      outcome = await _folderOpener.open(path);
      if (isClosed) {
        return;
      }
      if (outcome != FolderOpenOutcome.missing) {
        break;
      }
    }
    _finishOpen(outcome, attempted, target: 'codelab_folder');
  }

  /// «Open» строки шаблона: каталог файла шаблона считается здесь, в одном
  /// месте (страница путей не вычисляет); открывается только показанный
  /// шаблон.
  Future<void> openTemplateFolder(TemplateEntryView template) =>
      openFolder(p.dirname(template.sourcePath));

  /// «Open» строки: открывает каталог [directory], если страница его
  /// показывает; чужие пути (в том числе файлы) отвергаются без вызова порта
  /// (Q5, D8).
  Future<void> openFolder(String directory) async {
    if (isClosed || state is! SkillsSettingsReady) {
      return;
    }
    if (!_openable.contains(directory)) {
      return;
    }
    final outcome = await _folderOpener.open(directory);
    if (isClosed) {
      return;
    }
    _finishOpen(outcome, directory, target: 'file_dir');
  }

  void _finishOpen(
    FolderOpenOutcome outcome,
    String? path, {
    required String target,
  }) {
    final banner = outcome == FolderOpenOutcome.opened || path == null
        ? null
        : SkillsBanner(SkillsBannerKind.openFailed, 'Could not open $path.');
    if (banner != null) {
      // Путь — в баннере для пользователя, в журнале его нет (D10).
      _logger?.warning(
        'skills_settings.open_failed',
        context: {'target': target},
      );
    }
    switch (state) {
      case final SkillsSettingsReady ready:
        _emit(ready.withBanner(banner));
      case SkillsSettingsNoFolder():
        _emit(SkillsSettingsNoFolder(banner: banner));
      default:
        break;
    }
  }

  // --- Запись skills.disabled и skills.extra_roots (D5, D9, D14) -----------

  /// Выключатель «Enabled» навыка [name]: `enabled: false` кладёт имя в
  /// `skills.disabled`, `true` — убирает.
  ///
  /// Почему снимок берётся заново: между показом страницы и нажатием файл
  /// мог измениться, а `base` плана обязан быть снимком файла, который
  /// меняется (SETUP-6). Что писать и можно ли, решает `skillsListEdit`
  /// моста; Cubit его вызывает и превращает итог в баннер. События — только
  /// после `ConfigSaved` и без путей (D10).
  Future<void> setSkillEnabled(String name, {required bool enabled}) => _write(
    key: 'skills.disabled',
    element: name,
    present: !enabled,
    onSaved: (layer) => _logger?.info(
      'skills_settings.skill_toggled',
      context: {'name': name, 'enabled': enabled, 'layer': layer.name},
    ),
  );

  /// Согласие на каталог навыков другого агента: [entry] — элемент
  /// `skills.extra_roots` (`.claude/skills`, `~/.claude/skills`); [granted]
  /// `true` добавляет элемент, `false` убирает (Q3).
  Future<void> setRootConsent(String entry, {required bool granted}) => _write(
    key: 'skills.extra_roots',
    element: entry,
    present: granted,
    onSaved: (layer) => _logger?.info(
      'skills_settings.root_consent',
      context: {
        'root_kind': consentKindOf(entry).rootKind,
        'enabled': granted,
        'layer': layer.name,
      },
    ),
  );

  Future<void> _write({
    required String key,
    required String element,
    required bool present,
    required void Function(ConfigLayer layer) onSaved,
  }) async {
    final current = state;
    final session = _session;
    final cwd = _snapshotCwd;
    if (isClosed ||
        _saving ||
        current is! SkillsSettingsReady ||
        session == null ||
        cwd == null) {
      return;
    }
    _saving = true;
    final attempt = _loadAttempt;
    _emit(current.withSaving(saving: true));
    SkillsBanner? banner;
    var changed = true;
    try {
      final snapshot = await session.config.snapshot(cwd: cwd);
      // Страницу закрыли или перечитали на другую папку, пока брался снимок:
      // он относится к прежнему виду, неначатая запись отменяется.
      if (isClosed || attempt != _loadAttempt) {
        _finishSaving();
        return;
      }
      switch (skillsListEdit(snapshot, key, element, present: present)) {
        case SkillsListRefused(:final refusal):
          banner = SkillsBanner(
            SkillsBannerKind.error,
            skillsRefusalText(refusal, element: element),
          );
        case SkillsListPlan(:final edits) when edits.isEmpty:
          // Уже так: файл не пишется, баннера и события нет.
          changed = false;
        case SkillsListPlan(:final layer, :final base, :final edits):
          switch (await session.config.apply(base, edits)) {
            case ConfigSaved():
              onSaved(layer);
              banner = const SkillsBanner(SkillsBannerKind.saved, _savedText);
            case ConfigConflict():
              _logSaveFailed('conflict');
              banner = const SkillsBanner(
                SkillsBannerKind.conflict,
                'The config changed on disk, so nothing was saved. The page '
                'was reloaded; review it and try again.',
              );
            case ConfigRejected(:final issues):
              _logSaveFailed('rejected');
              banner = SkillsBanner(
                SkillsBannerKind.error,
                'The config was not saved: ${[for (final i in issues) i.key.isEmpty ? i.message : '${i.key}: ${i.message}'].join('; ')}',
              );
            case ConfigInlineSecret(:final key):
              _logSaveFailed('inline_secret');
              banner = SkillsBanner(
                SkillsBannerKind.error,
                'The config was not saved: $key must not hold a literal '
                'secret.',
              );
          }
      }
    } on Object catch (error) {
      // Текст исключения может содержать путь или значение: наружу — тип.
      _logSaveFailed(error.runtimeType.toString());
      banner = const SkillsBanner(
        SkillsBannerKind.error,
        'The config was not saved.',
      );
    }
    if (changed) {
      // Любой исход перечитывает страницу (файл мог измениться, отказ оставляет
      // её прежней); баннер ложится на состояние ближайшей свежей загрузки и
      // снимается только ею (устаревшая загрузка его не применяет и не стирает).
      _pendingBanner = banner;
      await reload();
    }
    // `saving` снимается ПОСЛЕ перечитывания: одна запись на нажатие (D14).
    _finishSaving();
  }

  void _finishSaving() {
    _saving = false;
    final current = state;
    if (!isClosed && current is SkillsSettingsReady && current.saving) {
      _emit(current.settled());
    }
  }

  static const _savedText =
      'Saved. New sessions use it; open sessions keep their skills.';

  void _logSaveFailed(String outcome) => _logger?.warning(
    'skills_settings.save_failed',
    context: {'outcome': outcome},
  );

  // --- Рабочее пространство -------------------------------------------------

  static ConnectionProfile? _connectedProfile(WorkspaceState state) =>
      state.connection is Connected || state.connection is Reconnecting
      ? state.profile
      : null;

  static String? _normalized(String? folder) =>
      folder == null || folder.isEmpty ? null : folder;

  void _onWorkspace(WorkspaceState next) {
    if (_connectedProfile(next) != _accessProfile ||
        _normalized(_projectDirectory()) != _folder) {
      // Смена подключения или папки сессии в фокусе перечитывает страницу
      // (D2); результат прежней загрузки отбросит номер загрузки.
      unawaited(reload());
    }
  }

  void _emit(SkillsSettingsState next) {
    // Баннер записи ждёт только состояния `Ready`; иное состояние его теряет.
    if (next is! SkillsSettingsReady) {
      _pendingBanner = null;
    }
    if (!isClosed) {
      emit(next);
    }
  }

  @override
  Future<void> close() async {
    _loadAttempt++;
    await _workspaceSubscription.cancel();
    return super.close();
  }
}
