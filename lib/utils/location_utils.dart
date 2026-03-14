import 'package:latlong2/latlong.dart';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

bool _hasValidContactLocation(Contact contact) {
  final lat = contact.latitude;
  final lon = contact.longitude;
  if (lat == null || lon == null) return false;
  if (lat == 0 && lon == 0) return false;
  return true;
}

Contact? selectBestRepeaterContactForPrefix(
  List<Contact> contacts,
  int pubkeyFirstByte, {
  LatLng? searchPoint,
  bool preferFavorites = false,
}) {
  final candidates = contacts
      .where(
        (c) =>
            c.publicKey.isNotEmpty &&
            c.publicKey.first == pubkeyFirstByte &&
            (c.type == advTypeRepeater || c.type == advTypeRoom),
      )
      .toList();

  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    if (preferFavorites) {
      final favA = a.isFavorite ? 1 : 0;
      final favB = b.isFavorite ? 1 : 0;
      final favCompare = favB.compareTo(favA);
      if (favCompare != 0) return favCompare;
    }

    final seenCompare = b.lastSeen.compareTo(a.lastSeen);
    if (seenCompare != 0) return seenCompare;

    return a.publicKeyHex.compareTo(b.publicKeyHex);
  });

  if (searchPoint == null) {
    return candidates.first;
  }

  final distance = Distance();
  Contact best = candidates.first;
  var bestDistance = double.infinity;

  for (final c in candidates) {
    if (_hasValidContactLocation(c)) {
      final d = distance(searchPoint, LatLng(c.latitude!, c.longitude!));
      if (d < bestDistance) {
        bestDistance = d;
        best = c;
      }
    }
  }

  return best;
}
