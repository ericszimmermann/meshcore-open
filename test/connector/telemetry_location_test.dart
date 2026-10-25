import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/services/telemetry_location_request.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _contactFrame(
  Uint8List key, {
  required int advertTimestamp,
  required double lat,
  required double lon,
}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, key);
  bytes[33] = advTypeChat;
  bytes[35] = 0xFF; // path unknown
  bytes.setRange(100, 103, 'Bob'.codeUnits);
  data.setUint32(132, advertTimestamp, Endian.little);
  data.setInt32(136, (lat * 1e6).round(), Endian.little);
  data.setInt32(140, (lon * 1e6).round(), Endian.little);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  test('telemetry fix survives a refresh of the same advert', () {
    final connector = MeshCoreConnector();
    final frame = _contactFrame(
      key,
      advertTimestamp: 1700000000,
      lat: 10,
      lon: 20,
    );
    connector.handleFrameForTest(frame);
    final keyHex = connector.contacts.single.publicKeyHex;

    connector.updateContactLocationFromTelemetry(keyHex, 11.5, 21.5);
    final fixed = connector.contacts.single;
    expect(fixed.latitude, 11.5);
    expect(fixed.longitude, 21.5);
    // lastSeen stays the advert time the radio holds (path and flag writes
    // send it back); the fix only moves lastHeard.
    final advertTime = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    expect(fixed.lastSeen, advertTime);
    expect(fixed.lastHeard.isAfter(advertTime), isTrue);

    connector.handleFrameForTest(frame);
    final refreshed = connector.contacts.single;
    expect(refreshed.latitude, 11.5);
    expect(refreshed.longitude, 21.5);
    expect(refreshed.lastSeen, advertTime);
    expect(refreshed.telemetryFixAt, fixed.telemetryFixAt);
  });

  test('telemetry fix survives a full contact sync', () {
    final connector = MeshCoreConnector();
    final frame = _contactFrame(
      key,
      advertTimestamp: 1700000000,
      lat: 10,
      lon: 20,
    );
    connector.handleFrameForTest(frame);
    final keyHex = connector.contacts.single.publicKeyHex;
    connector.updateContactLocationFromTelemetry(keyHex, 11.5, 21.5);

    // A full sync clears the list on CONTACTS_START and the radio resends
    // the same advert record.
    connector.handleFrameForTest([respCodeContactsStart]);
    expect(connector.contacts, isEmpty);
    connector.handleFrameForTest(frame);
    connector.handleFrameForTest([respCodeEndOfContacts]);

    final contact = connector.contacts.single;
    expect(contact.latitude, 11.5);
    expect(contact.longitude, 21.5);
    expect(contact.telemetryFixAt, isNotNull);
  });

  test('a newer advert replaces the telemetry fix', () {
    final connector = MeshCoreConnector();
    connector.handleFrameForTest(
      _contactFrame(key, advertTimestamp: 1700000000, lat: 10, lon: 20),
    );
    final keyHex = connector.contacts.single.publicKeyHex;
    connector.updateContactLocationFromTelemetry(keyHex, 11.5, 21.5);

    connector.handleFrameForTest(
      _contactFrame(key, advertTimestamp: 1700000100, lat: 12, lon: 22),
    );
    final contact = connector.contacts.single;
    expect(contact.latitude, 12);
    expect(contact.longitude, 22);
    expect(contact.telemetryFixAt, isNull);
  });

  test('telemetryGpsFix skips missing and null-island fixes', () {
    expect(telemetryGpsFix([]), isNull);
    expect(
      telemetryGpsFix([
        {
          'channel': 1,
          'values': {
            'gps': {'latitude': 0.0, 'longitude': 0.0, 'altitude': 0.0},
          },
        },
      ]),
      isNull,
    );
    expect(
      telemetryGpsFix([
        {
          'channel': 1,
          'values': {'voltage': 4.1},
        },
        {
          'channel': 2,
          'values': {
            'gps': {'latitude': 45.5, 'longitude': -122.6, 'altitude': 10.0},
          },
        },
      ]),
      (latitude: 45.5, longitude: -122.6),
    );
  });
}
