## MODIFIED Requirements

### Requirement: Recent projects persist across app restarts
CodeLab SHALL remember recently opened project directories across application restarts, on the local machine. The list SHALL be stored in `$CODELAB_HOME/recent_projects.json` through `JsonFileRecentProjectsStore` (acp-client-kit "Хранилище недавних проектов в CODELAB_HOME"), the same file the `codelab` CLI writes, so it does not depend on the application bundle identifier (design.md change `share-recent-projects-store`, D1, D8).

CodeLab SHALL NOT read, move or remove the `shared_preferences` key `codelab.recent_projects` used by builds before change `share-recent-projects-store`: a list left there is not shown (design.md change `remove-recent-projects-migration`, D1).

An unreadable recents file (corrupt JSON, unknown version) or an invalid `CODELAB_HOME` SHALL NOT block startup, project selection or session restore: the recents list is shown empty, a warning appears in diagnostics, and the file is not overwritten (design.md change `share-recent-projects-store`, D2, D8).

#### Scenario: A newly opened project appears in recents after restart
- **WHEN** the user opens a project directory (via browse or by it becoming the selected project) and then restarts CodeLab
- **THEN** that directory still appears in the "Open Project" recents list

#### Scenario: Recents list has a bound
- **WHEN** the number of distinct opened project directories exceeds the recents list's capacity
- **THEN** CodeLab keeps only the most recently opened entries, dropping the least recently used ones, rather than growing the list without bound

#### Scenario: A project opened in the CLI appears in the app
- **WHEN** `recent_projects.json` in `CODELAB_HOME` lists `/work/cli-project`, written by `codelab`, and CodeLab starts with that `CODELAB_HOME`
- **THEN** the sidebar shows `/work/cli-project` among the recent projects

#### Scenario: The key of earlier builds is ignored
- **WHEN** `shared_preferences` holds `codelab.recent_projects` with `/work/old`, `recent_projects.json` in `CODELAB_HOME` does not exist, and CodeLab starts and loads the recents list
- **THEN** the recents list is empty, `recent_projects.json` is not created, and the key `codelab.recent_projects` keeps its value

#### Scenario: An unreadable recents file is kept
- **WHEN** `recent_projects.json` contains `{not json`, and the user starts CodeLab and selects the project `/work/app`
- **THEN** the project is selected and the workbench works, the recents list is empty, diagnostics show a recent-projects warning, and the file bytes are unchanged

#### Scenario: Invalid CODELAB_HOME
- **WHEN** CodeLab starts with `CODELAB_HOME='~bob/cl'`
- **THEN** the app starts, the recents list is empty, diagnostics show the home folder problem, and no `recent_projects.json` is created
