import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart';

/// Общие заготовки ядра экрана TUI для тестов оверлеев (задачи 4.9–4.12
/// change `add-provider-setup-ui`): модель, кадр, клавиши и состояния
/// мастера без автомата и портов.

final t0 = DateTime.utc(2026, 11, 6, 12);
final _sgr = RegExp('\x1b\\[[0-9;]*m');

/// Строка кадра без SGR.
String plain(String line) => line.replaceAll(_sgr, '');

TuiModel newModel({int columns = 100, int rows = 30}) => TuiModel.initial(
  profile: 'default',
  size: TerminalSize(columns: columns, rows: rows),
  cwd: '/work',
  commands: replCommands,
);

TuiChrome chrome() =>
    TuiChrome(hints: 'Enter send · Shift+Enter new line', now: t0);

/// Строки кадра [model] без SGR.
List<String> frameOf(TuiModel model) => [
  for (final line in render(model, chrome()).lines) plain(line),
];

/// Все строки кадра одним текстом (для проверки отсутствия значения).
String screenOf(TuiModel model) => frameOf(model).join('\n');

KeyMsg key(Key k) => KeyMsg(SpecialKey(k), at: t0);
KeyMsg text(String t) => KeyMsg(TextKey(t), at: t0);

/// Применяет сообщения по порядку; возвращает модель и все команды.
(TuiModel, List<TuiCmd>) run(TuiModel model, List<TuiMsg> messages) {
  final cmds = <TuiCmd>[];
  for (final msg in messages) {
    final (next, out) = reduce(model, msg);
    model = next;
    cmds.addAll(out);
  }
  return (model, cmds);
}

const anthropic = ProviderPreset(
  id: 'anthropic',
  label: 'Anthropic',
  kind: 'anthropic',
  baseUrl: 'https://api.anthropic.com',
  key: KeyRequirement.required,
  suggestedEnvVar: 'ANTHROPIC_API_KEY',
);

const draft = ProviderDraft(
  providerId: 'anthropic',
  kind: 'anthropic',
  baseUrl: 'https://api.anthropic.com',
  preset: anthropic,
);

ChoosingPreset presetsState() => ChoosingPreset(ProviderPresets.all);

ChoosingKey keyState({bool writable = true, String? hint}) => ChoosingKey(
  draft,
  backend: SecretBackendInfo(
    id: 'file',
    writable: writable,
    unavailableReason: writable ? null : 'no OS store',
  ),
  ready: true,
  canStoreSecret: writable,
  canKeepStored: false,
  readOnlyHint: hint,
  suggestedEnvVar: 'ANTHROPIC_API_KEY',
);

ProviderSetupPlan plan() => const ProviderSetupPlan(
  providerId: 'anthropic',
  kind: 'anthropic',
  baseUrl: 'https://api.anthropic.com',
  key: NoKey(),
  secretName: null,
  replaceSecret: false,
  model: PlannedModel(id: 'claude-sonnet-5-5', contextWindow: 200000),
  makeDefault: true,
  target: ConfigTarget.user(),
);

ChoosingModel modelsState(List<String> ids) => ChoosingModel(draft, [
  for (final id in ids) RemoteModel(id),
], checked: true);

/// Модель с открытым мастером [id] на состоянии [state].
TuiModel openWizard(ProviderSetupState state, {int id = 1, TuiModel? model}) =>
    reduce(
      model ?? newModel(),
      OpenWizardMsg(id, state, pathOf: (_) => '/h/config.yaml'),
    ).$1;

// --- одобрение ---------------------------------------------------------

const allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);
const rejectOnce = PermissionOption(
  optionId: PermissionOptionId('reject-once'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);

/// Идёт ход с запросом разрешения `make test`.
TuiModel withApproval(TuiModel model) => reduce(
  model,
  SessionViewMsg(
    SessionView(
      revision: 1,
      status: SessionStatusView.running,
      pendingApprovals: [
        PendingApprovalView(
          approvalId: const ApprovalRequestId('a1'),
          sessionId: const SessionId('s1'),
          risk: ApprovalRiskLevel.shell,
          command: 'make test',
          rawInput: const {'command': 'make test'},
          options: const [allowOnce, rejectOnce],
          focused: true,
        ),
      ],
    ),
    at: t0,
  ),
).$1;
