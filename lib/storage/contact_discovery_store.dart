import 'dart:convert';
import 'dart:typed_data';

import '../models/discovery_contact.dart';
import 'prefs_manager.dart';

class ContactDiscoveryStore {
  static const String _key = 'discovered_contacts';

  Future<List<DiscoveryContact>> loadContacts() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList
          .map((entry) => _fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveContacts(List<DiscoveryContact> contacts) async {
    final prefs = PrefsManager.instance;
    final jsonList = contacts.map(_toJson).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
  }

  String encodeContacts(List<DiscoveryContact> contacts) {
    final jsonList = contacts.map(_toJson).toList();
    return jsonEncode(jsonList);
  }

  List<DiscoveryContact> decodeContacts(String jsonStr) {
    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList
          .map((entry) => _fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _toJson(DiscoveryContact contact) {
    return {
      'rawPacket': base64Encode(contact.rawPacket),
      'publicKey': base64Encode(contact.publicKey),
      'name': contact.name,
      'type': contact.type,
      'pathLength': contact.pathLength,
      'path': base64Encode(contact.path),
      'latitude': contact.latitude,
      'longitude': contact.longitude,
      'lastSeen': contact.lastSeen.millisecondsSinceEpoch,
    };
  }

  DiscoveryContact _fromJson(Map<String, dynamic> json) {
    final lastSeenMs = json['lastSeen'] as int? ?? 0;
    final rawName = json['name'] as String? ?? 'Unknown';
    return DiscoveryContact(
      rawPacket: Uint8List.fromList(base64Decode(json['rawPacket'] as String)),
      publicKey: Uint8List.fromList(base64Decode(json['publicKey'] as String)),
      name: _repairMojibakeIfNeeded(rawName),
      type: json['type'] as int? ?? 0,
      pathLength: json['pathLength'] as int? ?? -1,
      path: json['path'] != null
          ? Uint8List.fromList(base64Decode(json['path'] as String))
          : Uint8List(0),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
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
