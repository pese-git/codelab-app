import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recent_projects_store.dart';

/// Recents are capped at this many entries — see
/// add-open-project-picker/design.md, Decision 4.
const kRecentProjectsLimit = 10;

const _kRecentProjectsPrefsKey = 'codelab.recent_projects';

/// Persists recents as a single JSON array under one
/// [SharedPreferences] key, rather than one key per entry — simplifies
/// atomic replacement and future format versioning (design.md, Decision 4).
final class SharedPreferencesRecentProjectsStore
    implements RecentProjectsStore {
  const SharedPreferencesRecentProjectsStore();

  @override
  Future<List<RecentProject>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecentProjectsPrefsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => RecentProject.fromJson(entry as Map<String, Object?>))
        .toList(growable: false);
  }

  @override
  Future<void> record(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final withoutPath = current.where((entry) => entry.path != path);
    final updated = [
      RecentProject(path: path, lastOpenedAt: DateTime.now()),
      ...withoutPath,
    ].take(kRecentProjectsLimit).toList(growable: false);

    await prefs.setString(
      _kRecentProjectsPrefsKey,
      jsonEncode(updated.map((entry) => entry.toJson()).toList()),
    );
  }
}
