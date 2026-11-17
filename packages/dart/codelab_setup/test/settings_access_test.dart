import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// `resolveSettingsAccess`: чьи настройки агента клиент вправе читать и писать
/// (client-agent-setup «Доступ к настройкам агента»; design.md change
/// `add-provider-setup-ui`, D5). Чистый Dart: ни файлов, ни процессов.
void main() {
  const home = '/app-home';

  SettingsAccess resolve({
    required AgentLaunchKind kind,
    String? command,
    String? agentName,
    List<String> args = const [],
    Map<String, String> env = const {},
    Uri? endpoint,
    String? cwd = '/work/project',
  }) => resolveSettingsAccess(
    kind: kind,
    command: command,
    agentName: agentName,
    args: args,
    env: env,
    endpoint: endpoint,
    cwd: cwd,
    defaultCodelabHome: home,
  );

  group('доступ по профилю', () {
    test('встроенный агент, codelab-agent, чужой агент и WebSocket', () {
      final embedded = resolve(kind: AgentLaunchKind.embedded);
      final local = resolve(
        kind: AgentLaunchKind.stdio,
        command: 'codelab-agent',
        args: const ['serve', '--stdio'],
      );
      final other = resolve(
        kind: AgentLaunchKind.stdio,
        command: 'python',
        args: const ['-m', 'other'],
        agentName: 'other',
      );
      final remote = resolve(
        kind: AgentLaunchKind.webSocket,
        endpoint: Uri.parse('wss://box:7420'),
      );

      expect(embedded, isA<EditableSettings>());
      expect(local, isA<EditableSettings>());
      expect(other, isA<NotManaged>());
      expect((other as NotManaged).agentName, 'other');
      expect(remote, isA<RemoteReadOnly>());
      expect((remote as RemoteReadOnly).endpoint, Uri.parse('wss://box:7420'));
    });

    test('команда codelab-agent с путём и суффиксом .exe', () {
      for (final command in const [
        '/usr/local/bin/codelab-agent',
        r'C:\tools\codelab-agent.exe',
      ]) {
        expect(
          resolve(kind: AgentLaunchKind.stdio, command: command),
          isA<EditableSettings>(),
          reason: command,
        );
      }
    });

    test('после подключения имя из initialize должно быть codelab-agent', () {
      final named = resolve(
        kind: AgentLaunchKind.stdio,
        command: 'codelab-agent',
        agentName: 'codelab-agent',
      );
      final renamed = resolve(
        kind: AgentLaunchKind.stdio,
        command: 'codelab-agent',
        agentName: 'impostor',
      );
      // Команда — не `codelab-agent`, хотя агент так представился: конфиг
      // читается по команде профиля, а не по самоназванию.
      final wrapped = resolve(
        kind: AgentLaunchKind.stdio,
        command: 'python',
        agentName: 'codelab-agent',
      );

      expect(named, isA<EditableSettings>());
      expect((renamed as NotManaged).agentName, 'impostor');
      expect(wrapped, isA<NotManaged>());
    });

    test('сторонний агент без имени называется по команде', () {
      final access = resolve(
        kind: AgentLaunchKind.stdio,
        command: '/opt/bin/other-agent',
      );

      expect((access as NotManaged).agentName, 'other-agent');
    });

    test('WebSocket без адреса — ошибка программиста', () {
      expect(
        () => resolve(kind: AgentLaunchKind.webSocket),
        throwsArgumentError,
      );
    });
  });

  group('пути и цели записи', () {
    test('CODELAB_HOME берётся из env stdio-профиля, иначе из app', () {
      final profile =
          resolve(
                kind: AgentLaunchKind.stdio,
                command: 'codelab-agent',
                env: const {'CODELAB_HOME': '/agent-home'},
              )
              as EditableSettings;
      final empty =
          resolve(
                kind: AgentLaunchKind.stdio,
                command: 'codelab-agent',
                env: const {'CODELAB_HOME': ''},
              )
              as EditableSettings;
      final embedded =
          resolve(
                kind: AgentLaunchKind.embedded,
                env: const {'CODELAB_HOME': '/ignored'},
              )
              as EditableSettings;

      expect(profile.paths.codelabHome, '/agent-home');
      expect(empty.paths.codelabHome, home);
      // Встроенный агент живёт в процессе app: env профиля у него нет.
      expect(embedded.paths.codelabHome, home);
    });

    test('цели — user и projectLocal; project и --config только чтение', () {
      final access =
          resolve(
                kind: AgentLaunchKind.stdio,
                command: 'codelab-agent',
                args: const ['serve', '--stdio', '--config', '/etc/team.yaml'],
              )
              as EditableSettings;

      expect(access.targets, [
        const ConfigTarget.user(),
        const ConfigTarget.projectLocal('/work/project'),
      ]);
      expect(access.paths.projectDir, '/work/project');
      expect(access.paths.extraConfig, '/etc/team.yaml');
    });

    test('--config=<файл> и CODELAB_CONFIG из env', () {
      final flag =
          resolve(
                kind: AgentLaunchKind.stdio,
                command: 'codelab-agent',
                args: const ['--config=/etc/a.yaml'],
                env: const {'CODELAB_CONFIG': '/etc/b.yaml'},
              )
              as EditableSettings;
      final env =
          resolve(
                kind: AgentLaunchKind.stdio,
                command: 'codelab-agent',
                env: const {'CODELAB_CONFIG': '/etc/b.yaml'},
              )
              as EditableSettings;

      expect(flag.paths.extraConfig, '/etc/a.yaml');
      expect(env.paths.extraConfig, '/etc/b.yaml');
    });

    test('без папки проекта projectLocal не предлагается', () {
      final access =
          resolve(
                kind: AgentLaunchKind.stdio,
                command: 'codelab-agent',
                cwd: null,
              )
              as EditableSettings;

      expect(access.targets, [const ConfigTarget.user()]);
      expect(access.paths.projectDir, isNull);
    });
  });
}
