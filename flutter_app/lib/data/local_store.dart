/// JSON snapshot persistence for the whole app state.
///
/// Honest engineering note: the build sandbox cannot run Drift/sqflite
/// codegen or native SQLite plugins, so demo persistence uses an atomic JSON
/// snapshot written via path_provider. The repository API is
/// storage-agnostic; swapping in Drift later only touches this file.
/// Backup/restore/export operate on the same snapshot format.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SnapshotStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> snapshot);
  Future<String> backupTo(String suffix);
  Future<void> restoreFrom(String path);
  Future<void> wipe();
}

class FileSnapshotStore implements SnapshotStore {
  final String fileName;
  FileSnapshotStore({this.fileName = 'powerline_state.json'});

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<String> backupTo(String suffix) async {
    final f = await _file();
    final backup = File('${f.path}.backup-$suffix.json');
    if (await f.exists()) await f.copy(backup.path);
    return backup.path;
  }

  @override
  Future<void> restoreFrom(String path) async {
    final src = File(path);
    if (!await src.exists()) {
      throw const FileSystemException('backup not found');
    }
    // Validate JSON before overwriting.
    jsonDecode(await src.readAsString());
    final f = await _file();
    await src.copy(f.path);
  }

  @override
  Future<void> wipe() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

/// In-memory store for tests and for platforms where path_provider is
/// unavailable.
class MemorySnapshotStore implements SnapshotStore {
  Map<String, dynamic>? _snap;
  final Map<String, Map<String, dynamic>> backups = {};

  @override
  Future<Map<String, dynamic>?> load() async => _snap;

  @override
  Future<void> save(Map<String, dynamic> snapshot) async =>
      _snap = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

  @override
  Future<String> backupTo(String suffix) async {
    if (_snap != null) {
      backups[suffix] = jsonDecode(jsonEncode(_snap)) as Map<String, dynamic>;
    }
    return 'memory://$suffix';
  }

  @override
  Future<void> restoreFrom(String path) async {
    final suffix = path.replaceFirst('memory://', '');
    final b = backups[suffix];
    if (b == null) throw StateError('backup not found');
    _snap = jsonDecode(jsonEncode(b)) as Map<String, dynamic>;
  }

  @override
  Future<void> wipe() async => _snap = null;
}

class SharedPreferencesSnapshotStore implements SnapshotStore {
  static const _stateKey = 'powerline_state_v1';

  @override
  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(snapshot));
  }

  @override
  Future<String> backupTo(String suffix) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw != null) {
      await prefs.setString('powerline_backup_$suffix', raw);
    }
    return 'preferences://$suffix';
  }

  @override
  Future<void> restoreFrom(String path) async {
    final suffix = path.replaceFirst('preferences://', '');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('powerline_backup_$suffix');
    if (raw == null) throw StateError('backup not found');
    jsonDecode(raw);
    await prefs.setString(_stateKey, raw);
  }

  @override
  Future<void> wipe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stateKey);
  }
}
