## MODIFIED Requirements

### Requirement: Recent projects persist across app restarts
CodeLab SHALL remember recently opened project directories across application restarts, on the local machine. The list SHALL be stored in `$CODELAB_HOME/recent_projects.json` through `JsonFileRecentProjectsStore` (acp-client-kit "Хранилище недавних проектов в CODELAB_HOME"), the same file the `codelab` CLI writes, so it does not depend on the application bundle identifier (design.md change `share-recent-projects-store`, D1, D8).

On the first access to the list, CodeLab SHALL move a list stored by an earlier version under the `shared_preferences` key `codelab.recent_projects` into that file: it merges it with the file's entries by `mergeRecentProjects`, writes the file, and only then removes the key. An unparseable key value SHALL be removed with a warning event and no file change. If the file is unreadable or `CODELAB_HOME` is invalid, the key SHALL be kept. No list access SHALL write the file before the move has finished (D4).

An unreadable recents file (corrupt JSON, unknown version) or an invalid `CODELAB_HOME` SHALL NOT block startup, project selection or session restore: the recents list is shown empty, a warning appears in diagnostics, and the file is not overwritten (D2, D8). Migration events SHALL NOT contain project paths (D11).

#### Scenario: A newly opened project appears in recents after restart
- **WHEN** the user opens a project directory (via browse or by it becoming the selected project) and then restarts CodeLab
- **THEN** that directory still appears in the "Open Project" recents list

#### Scenario: Recents list has a bound
- **WHEN** the number of distinct opened project directories exceeds the recents list's capacity
- **THEN** CodeLab keeps only the most recently opened entries, dropping the least recently used ones, rather than growing the list without bound

#### Scenario: A project opened in the CLI appears in the app
- **WHEN** `recent_projects.json` in `CODELAB_HOME` lists `/work/cli-project`, written by `codelab`, and CodeLab starts with that `CODELAB_HOME`
- **THEN** the sidebar shows `/work/cli-project` among the recent projects

#### Scenario: Recents from an earlier version are moved once
- **WHEN** `shared_preferences` holds `codelab.recent_projects` with `/work/old` at 09:00, `recent_projects.json` holds `/work/old` at 10:00 and `/work/cli` at 08:00, and CodeLab starts twice
- **THEN** after the first start the file lists `/work/old` at 10:00 and `/work/cli`, each once, the key is removed, and the second start leaves the file unchanged

#### Scenario: An unreadable recents file is kept
- **WHEN** `recent_projects.json` contains `{not json`, the key `codelab.recent_projects` holds `/work/old`, and the user starts CodeLab and selects the project `/work/app`
- **THEN** the project is selected and the workbench works, the recents list is empty, diagnostics show a recent-projects warning, the file bytes are unchanged, and the key `codelab.recent_projects` is kept

#### Scenario: Invalid CODELAB_HOME
- **WHEN** CodeLab starts with `CODELAB_HOME='~bob/cl'` and the key `codelab.recent_projects` holds `/work/old`
- **THEN** the app starts, the recents list is empty, diagnostics show the home folder problem, and the key `codelab.recent_projects` is kept
