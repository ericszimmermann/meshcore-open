import 'dart:convert';

import 'prefs_manager.dart';

class RoomSyncStateRecord {
  final String roomPubKeyHex;
  final bool autoSyncEnabled;
  final int? lastLoginAttemptAtMs;
  final int? lastLoginSuccessAtMs;
  final int? lastSuccessfulSyncAtMs;
  final int? lastFailureAtMs;
  final int consecutiveFailures;

  const RoomSyncStateRecord({
    required this.roomPubKeyHex,
    this.autoSyncEnabled = true,
    this.lastLoginAttemptAtMs,
    this.lastLoginSuccessAtMs,
    this.lastSuccessfulSyncAtMs,
    this.lastFailureAtMs,
    this.consecutiveFailures = 0,
  });

  RoomSyncStateRecord copyWith({
    bool? autoSyncEnabled,
    int? lastLoginAttemptAtMs,
    int? lastLoginSuccessAtMs,
    int? lastSuccessfulSyncAtMs,
    int? lastFailureAtMs,
    int? consecutiveFailures,
  }) {
    return RoomSyncStateRecord(
      roomPubKeyHex: roomPubKeyHex,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lastLoginAttemptAtMs: lastLoginAttemptAtMs ?? this.lastLoginAttemptAtMs,
      lastLoginSuccessAtMs: lastLoginSuccessAtMs ?? this.lastLoginSuccessAtMs,
      lastSuccessfulSyncAtMs:
          lastSuccessfulSyncAtMs ?? this.lastSuccessfulSyncAtMs,
      lastFailureAtMs: lastFailureAtMs ?? this.lastFailureAtMs,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomPubKeyHex': roomPubKeyHex,
      'autoSyncEnabled': autoSyncEnabled,
      'lastLoginAttemptAtMs': lastLoginAttemptAtMs,
      'lastLoginSuccessAtMs': lastLoginSuccessAtMs,
      'lastSuccessfulSyncAtMs': lastSuccessfulSyncAtMs,
      'lastFailureAtMs': lastFailureAtMs,
      'consecutiveFailures': consecutiveFailures,
    };
  }

  static RoomSyncStateRecord fromJson(Map<String, dynamic> json) {
    return RoomSyncStateRecord(
      roomPubKeyHex: json['roomPubKeyHex'] as String,
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
      lastLoginAttemptAtMs: json['lastLoginAttemptAtMs'] as int?,
      lastLoginSuccessAtMs: json['lastLoginSuccessAtMs'] as int?,
      lastSuccessfulSyncAtMs: json['lastSuccessfulSyncAtMs'] as int?,
      lastFailureAtMs: json['lastFailureAtMs'] as int?,
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
    );
  }
}

class RoomSyncStore {
  static const String _roomSyncStateKey = 'room_sync_state_v1';

  Future<Map<String, RoomSyncStateRecord>> load() async {
    final prefs = PrefsManager.instance;
    final raw = prefs.getString(_roomSyncStateKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) {
        return MapEntry(
          key,
          RoomSyncStateRecord.fromJson(value as Map<String, dynamic>),
        );
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, RoomSyncStateRecord> states) async {
    final prefs = PrefsManager.instance;
    final payload = states.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_roomSyncStateKey, jsonEncode(payload));
  }
}
