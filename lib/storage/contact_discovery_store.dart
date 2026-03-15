import 'dart:convert';
import 'dart:typed_data';

import '../models/contact.dart';
import 'prefs_manager.dart';

class ContactDiscoveryStore {
  static const String _keyPrefix = 'discovered_contacts';

  List<Contact> decodeContacts(String jsonStr) {
    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList
          .map((entry) => _fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String encodeContacts(List<Contact> contacts) {
    final jsonList = contacts.map(_toJson).toList();
    return jsonEncode(jsonList);
  }

  Future<List<Contact>> loadContacts() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_keyPrefix);
    if (jsonStr == null) return [];
    return decodeContacts(jsonStr);
  }

  Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = PrefsManager.instance;
    await prefs.setString(_keyPrefix, encodeContacts(contacts));
  }

  Map<String, dynamic> _toJson(Contact contact) {
    return {
      'publicKey': base64Encode(contact.publicKey),
      'name': contact.name,
      'type': contact.type,
      'flags': contact.flags,
      'pathLength': contact.pathLength,
      'path': base64Encode(contact.path),
      'pathOverride': contact.pathOverride,
      'pathOverrideBytes': contact.pathOverrideBytes != null
          ? base64Encode(contact.pathOverrideBytes!)
          : null,
      'latitude': contact.latitude,
      'longitude': contact.longitude,
      'lastSeen': contact.lastSeen.millisecondsSinceEpoch,
      'lastMessageAt': contact.lastMessageAt.millisecondsSinceEpoch,
      'rawPacket': contact.rawPacket != null
          ? base64Encode(contact.rawPacket!)
          : null,
    };
  }

  Contact _fromJson(Map<String, dynamic> json) {
    final lastSeenMs = json['lastSeen'] as int? ?? 0;
    final lastMessageMs = json['lastMessageAt'] as int?;
    final rawName = json['name'] as String? ?? 'Unknown';
    return Contact(
      publicKey: Uint8List.fromList(base64Decode(json['publicKey'] as String)),
      name: _repairMojibakeIfNeeded(rawName),
      type: json['type'] as int? ?? 0,
      flags: json['flags'] as int? ?? 0,
      pathLength: json['pathLength'] as int? ?? -1,
      path: json['path'] != null
          ? Uint8List.fromList(base64Decode(json['path'] as String))
          : Uint8List(0),
      pathOverride: json['pathOverride'] as int?,
      pathOverrideBytes: json['pathOverrideBytes'] != null
          ? Uint8List.fromList(
              base64Decode(json['pathOverrideBytes'] as String),
            )
          : null,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
        lastMessageMs ?? lastSeenMs,
      ),
      isActive: false,
      rawPacket: json['rawPacket'] != null
          ? Uint8List.fromList(base64Decode(json['rawPacket'] as String))
          : null,
    );
  }

  String _repairMojibakeIfNeeded(String value) {
    if (value.isEmpty) return value;

    final looksMojibake =
        value.contains('Ã') ||
        value.contains('Â') ||
        value.contains('â') ||
        value.contains('ð') ||
        RegExp(r'[\u0080-\u009F]').hasMatch(value);
    if (!looksMojibake) return value;

    try {
      final repaired = utf8.decode(latin1.encode(value));
      if (repaired.isNotEmpty) {
        return repaired;
      }
    } catch (_) {
      // Keep original if conversion is not valid.
    }

    return value;
  }
}
