import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/app_settings.dart';
import 'app_settings_service.dart';

enum MapRasterSourcePreset {
  osmStandard('osm_standard'),
  stamenTerrain('stamen_terrain'),
  alidadeSmoothDark('alidade_smooth_dark'),
  outdoors('outdoors'),
  osmBright('osm_bright');

  const MapRasterSourcePreset(this.id);

  final String id;

  static MapRasterSourcePreset fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return MapRasterSourcePreset.osmStandard;
  }
}

enum MapRasterEndpointPreset {
  standard('standard'),
  eu('eu');

  const MapRasterEndpointPreset(this.id);

  final String id;

  static MapRasterEndpointPreset fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return MapRasterEndpointPreset.standard;
  }
}

@immutable
class MapRasterSourceDefinition {
  const MapRasterSourceDefinition({
    required this.id,
    required this.label,
    required this.description,
    this.isStadia = false,
    this.allowsBulkDownload = false,
  });

  final String id;
  final String label;
  final String description;
  final bool isStadia;
  final bool allowsBulkDownload;
}

@immutable
class MapRasterEndpointDefinition {
  const MapRasterEndpointDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.host,
  });

  final String id;
  final String label;
  final String description;
  final String host;
}

class MapRasterSourceCatalog {
  static const MapRasterSourceDefinition osmStandard =
      MapRasterSourceDefinition(
        id: 'osm_standard',
        label: 'OpenStreetMap Standard',
        description: 'Direct tiles from tile.openstreetmap.org',
      );
  static const MapRasterSourceDefinition stamenTerrain =
      MapRasterSourceDefinition(
        id: 'stamen_terrain',
        label: 'Stamen Terrain',
        description: 'Terrain-focused style with hill shading',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition alidadeSmoothDark =
      MapRasterSourceDefinition(
        id: 'alidade_smooth_dark',
        label: 'Alidade Smooth Dark',
        description: 'Dark basemap with smooth contrast',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition outdoors = MapRasterSourceDefinition(
    id: 'outdoors',
    label: 'Outdoors',
    description: 'Outdoor-focused map with trails and terrain context',
    isStadia: true,
    allowsBulkDownload: true,
  );
  static const MapRasterSourceDefinition osmBright = MapRasterSourceDefinition(
    id: 'osm_bright',
    label: 'OSM Bright',
    description: 'Bright general-purpose OpenStreetMap style',
    isStadia: true,
    allowsBulkDownload: true,
  );

  static const List<MapRasterSourceDefinition> presets = [
    osmStandard,
    stamenTerrain,
    alidadeSmoothDark,
    outdoors,
    osmBright,
  ];

  static MapRasterSourceDefinition fromSettings(AppSettings settings) {
    final preset = MapRasterSourcePreset.fromId(settings.mapRasterSourceId);
    switch (preset) {
      case MapRasterSourcePreset.osmStandard:
        return osmStandard;
      case MapRasterSourcePreset.alidadeSmoothDark:
        return alidadeSmoothDark;
      case MapRasterSourcePreset.outdoors:
        return outdoors;
      case MapRasterSourcePreset.osmBright:
        return osmBright;
      case MapRasterSourcePreset.stamenTerrain:
        return stamenTerrain;
    }
  }
}

class MapRasterEndpointCatalog {
  static const MapRasterEndpointDefinition standard =
      MapRasterEndpointDefinition(
        id: 'standard',
        label: 'Standard Endpoint',
        description: 'Global CDN routing to the fastest Stadia server',
        host: 'tiles.stadiamaps.com',
      );
  static const MapRasterEndpointDefinition eu = MapRasterEndpointDefinition(
    id: 'eu',
    label: 'EU Endpoint',
    description: 'Route tile requests to Stadia EU servers',
    host: 'tiles-eu.stadiamaps.com',
  );

  static const List<MapRasterEndpointDefinition> presets = [standard, eu];

  static MapRasterEndpointDefinition fromSettings(AppSettings settings) {
    final preset = MapRasterEndpointPreset.fromId(settings.mapTileEndpointId);
    switch (preset) {
      case MapRasterEndpointPreset.eu:
        return eu;
      case MapRasterEndpointPreset.standard:
        return standard;
    }
  }
}

class MapTileCacheProgress {
  final int completed;
  final int total;
  final int failed;

  const MapTileCacheProgress({
    required this.completed,
    required this.total,
    required this.failed,
  });
}

class MapTileCacheResult {
  final int total;
  final int downloaded;
  final int failed;

  const MapTileCacheResult({
    required this.total,
    required this.downloaded,
    required this.failed,
  });
}

class MapTileCacheService extends ChangeNotifier {
  static const String cacheKey = 'map_tile_cache';
  static const String userAgentPackageName = 'com.meshcore.open';
  static const int defaultMinZoom = 10;
  static const int defaultMaxZoom = 15;

  final AppSettingsService appSettingsService;
  final BaseCacheManager cacheManager;
  late final TileProvider tileProvider;

  MapTileCacheService({
    required this.appSettingsService,
    BaseCacheManager? cacheManager,
  }) : cacheManager =
           cacheManager ??
           CacheManager(
             Config(
               cacheKey,
               stalePeriod: const Duration(days: 365),
               maxNrOfCacheObjects: 200000,
             ),
           ) {
    tileProvider = CachedNetworkTileProvider(cacheManager: this.cacheManager);
    appSettingsService.addListener(_handleSettingsChanged);
  }

  MapRasterSourceDefinition get source =>
      MapRasterSourceCatalog.fromSettings(appSettingsService.settings);

  MapRasterEndpointDefinition get endpoint =>
      MapRasterEndpointCatalog.fromSettings(appSettingsService.settings);

  String get urlTemplate => _buildUrlTemplate(appSettingsService.settings);

  Map<String, String> get defaultHeaders => {
    'User-Agent': 'flutter_map ($userAgentPackageName)',
  };

  Future<void> clearCache() async {
    await cacheManager.emptyCache();
  }

  int estimateTileCount(LatLngBounds bounds, int minZoom, int maxZoom) {
    final safeMin = math.min(minZoom, maxZoom);
    final safeMax = math.max(minZoom, maxZoom);
    int total = 0;

    for (int zoom = safeMin; zoom <= safeMax; zoom++) {
      final tileBounds = _tileBoundsForBounds(bounds, zoom);
      final xCount = tileBounds.maxX - tileBounds.minX + 1;
      final yCount = tileBounds.maxY - tileBounds.minY + 1;
      total += xCount * yCount;
    }
    return total;
  }

  Future<MapTileCacheResult> downloadRegion({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    int concurrentDownloads = 8,
    Map<String, String>? headers,
    void Function(MapTileCacheProgress progress)? onProgress,
  }) async {
    final safeMin = math.min(minZoom, maxZoom);
    final safeMax = math.max(minZoom, maxZoom);
    final total = estimateTileCount(bounds, safeMin, safeMax);
    final authHeaders = headers ?? defaultHeaders;
    final safeConcurrency = math.max(1, concurrentDownloads);
    final currentTemplate = urlTemplate;
    int completed = 0;
    int failed = 0;

    final pending = <Future<void>>[];
    Future<void> queueDownload(String url) async {
      final future = cacheManager
          .downloadFile(url, key: url, authHeaders: authHeaders)
          .then((_) {
            completed += 1;
          })
          .catchError((_) {
            completed += 1;
            failed += 1;
          })
          .whenComplete(() {
            onProgress?.call(
              MapTileCacheProgress(
                completed: completed,
                total: total,
                failed: failed,
              ),
            );
          });

      pending.add(future);
      if (pending.length >= safeConcurrency) {
        await Future.wait(pending);
        pending.clear();
      }
    }

    for (int zoom = safeMin; zoom <= safeMax; zoom++) {
      final tileBounds = _tileBoundsForBounds(bounds, zoom);
      for (int x = tileBounds.minX; x <= tileBounds.maxX; x++) {
        for (int y = tileBounds.minY; y <= tileBounds.maxY; y++) {
          final url = _buildTileUrl(x, y, zoom, urlTemplate: currentTemplate);
          await queueDownload(url);
        }
      }
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }

    return MapTileCacheResult(
      total: total,
      downloaded: completed - failed,
      failed: failed,
    );
  }

  static Map<String, double> boundsToJson(LatLngBounds bounds) {
    return {
      'north': bounds.north,
      'south': bounds.south,
      'east': bounds.east,
      'west': bounds.west,
    };
  }

  static LatLngBounds? boundsFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final north = (json['north'] as num?)?.toDouble();
    final south = (json['south'] as num?)?.toDouble();
    final east = (json['east'] as num?)?.toDouble();
    final west = (json['west'] as num?)?.toDouble();
    if (north == null || south == null || east == null || west == null) {
      return null;
    }
    return LatLngBounds.unsafe(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  void _handleSettingsChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    appSettingsService.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  _TileBounds _tileBoundsForBounds(LatLngBounds bounds, int zoom) {
    final north = _clampLatitude(bounds.north);
    final south = _clampLatitude(bounds.south);
    final maxIndex = (1 << zoom) - 1;

    final minX = _lonToTileX(bounds.west, zoom, maxIndex);
    final maxX = _lonToTileX(bounds.east, zoom, maxIndex);
    final minY = _latToTileY(north, zoom, maxIndex);
    final maxY = _latToTileY(south, zoom, maxIndex);

    return _TileBounds(
      minX: math.min(minX, maxX),
      maxX: math.max(minX, maxX),
      minY: math.min(minY, maxY),
      maxY: math.max(minY, maxY),
    );
  }

  String _buildUrlTemplate(AppSettings settings) {
    final source = MapRasterSourceCatalog.fromSettings(settings);
    if (!source.isStadia) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    final endpoint = MapRasterEndpointCatalog.fromSettings(settings);
    final apiKey = settings.mapTileApiKey?.trim();
    final base = 'https://${endpoint.host}/tiles/${source.id}/{z}/{x}/{y}.png';
    if (apiKey == null || apiKey.isEmpty) {
      return base;
    }
    final query = Uri(queryParameters: {'api_key': apiKey}).query;
    return '$base?$query';
  }

  int _lonToTileX(double lon, int zoom, int maxIndex) {
    final n = 1 << zoom;
    final value = ((lon + 180.0) / 360.0 * n).floor();
    return value.clamp(0, maxIndex);
  }

  int _latToTileY(double lat, int zoom, int maxIndex) {
    final n = 1 << zoom;
    final rad = lat * math.pi / 180.0;
    final value =
        ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
            .floor();
    return value.clamp(0, maxIndex);
  }

  double _clampLatitude(double lat) {
    const maxLat = 85.05112878;
    return lat.clamp(-maxLat, maxLat);
  }

  String _buildTileUrl(int x, int y, int zoom, {required String urlTemplate}) {
    return urlTemplate
        .replaceAll('{z}', zoom.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }
}

class CachedNetworkTileProvider extends TileProvider {
  final BaseCacheManager cacheManager;

  CachedNetworkTileProvider({required this.cacheManager, super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheManager: cacheManager,
      headers: headers,
    );
  }
}

class _TileBounds {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  const _TileBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}
