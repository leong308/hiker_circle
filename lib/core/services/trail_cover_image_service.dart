import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../trail/Model/trail_models.dart';

class TrailCoverImageService {
  const TrailCoverImageService({http.Client? client}) : _client = client;

  static const instance = TrailCoverImageService();
  static final _futureCache = <String, Future<String>>{};

  final http.Client? _client;

  Future<String> imageUrlForTrail(Trail trail) {
    final explicitUrl = trail.coverImageUrl.trim();
    if (explicitUrl.isNotEmpty) {
      return Future.value(explicitUrl);
    }

    final key = [
      trail.trailId,
      trail.name,
      trail.area,
      trail.state,
    ].join('|').toLowerCase();

    return _futureCache.putIfAbsent(key, () => _fetchImageUrlForTrail(trail));
  }

  Future<String> _fetchImageUrlForTrail(Trail trail) async {
    final client = _client ?? http.Client();
    try {
      final queries = _queriesForTrail(trail);
      for (final query in queries) {
        final url = await _searchCommons(
          client: client,
          query: query,
          trail: trail,
        );
        if (url.isNotEmpty) {
          return url;
        }
      }
      for (final query in queries) {
        final url = await _searchOpenverse(
          client: client,
          query: query,
          trail: trail,
        );
        if (url.isNotEmpty) {
          return url;
        }
      }
    } finally {
      if (_client == null) {
        client.close();
      }
    }
    return '';
  }

  List<String> _queriesForTrail(Trail trail) {
    return [
      '${trail.name} ${trail.area} ${trail.state} hiking trail',
      '${trail.name} ${trail.state}',
      '${trail.area} ${trail.state} hill trail',
      '${trail.area} ${trail.state} forest reserve',
      '${trail.latitude.toStringAsFixed(3)} ${trail.longitude.toStringAsFixed(3)}',
    ];
  }

  Future<String> _searchCommons({
    required http.Client client,
    required String query,
    required Trail trail,
  }) async {
    final response = await client
        .get(
          Uri.https('commons.wikimedia.org', '/w/api.php', {
            'action': 'query',
            'generator': 'search',
            'gsrsearch': query,
            'gsrnamespace': '6',
            'gsrlimit': '12',
            'prop': 'imageinfo',
            'iiprop': 'url|mime',
            'iiurlwidth': '1200',
            'format': 'json',
            'origin': '*',
          }),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'HikerCircle/1.0 trail cover image search',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return '';
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    final queryResult = decoded['query'];
    final pages = queryResult is Map ? queryResult['pages'] : null;
    if (pages is! Map) {
      return '';
    }

    final candidates =
        pages.values
            .whereType<Map>()
            .map((page) => _ImageCandidate.fromPage(page, trail))
            .whereType<_ImageCandidate>()
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    if (candidates.isEmpty || candidates.first.score < 0) {
      return '';
    }
    return candidates.first.url;
  }

  Future<String> _searchOpenverse({
    required http.Client client,
    required String query,
    required Trail trail,
  }) async {
    final response = await client
        .get(
          Uri.https('api.openverse.org', '/v1/images/', {
            'q': query,
            'page_size': '12',
            'mature': 'false',
          }),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'HikerCircle/1.0 trail cover image search',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return '';
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    final results = decoded['results'];
    if (results is! List) {
      return '';
    }

    final candidates =
        results
            .whereType<Map>()
            .map((result) => _ImageCandidate.fromOpenverse(result, trail))
            .whereType<_ImageCandidate>()
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    if (candidates.isEmpty || candidates.first.score < 0) {
      return '';
    }
    return candidates.first.url;
  }
}

class _ImageCandidate {
  const _ImageCandidate({required this.url, required this.score});

  final String url;
  final int score;

  static _ImageCandidate? fromPage(Map page, Trail trail) {
    final title = page['title'] as String? ?? '';
    final imageInfo = page['imageinfo'];
    if (imageInfo is! List || imageInfo.isEmpty || imageInfo.first is! Map) {
      return null;
    }

    final firstImageInfo = Map<String, dynamic>.from(imageInfo.first as Map);
    final mime = firstImageInfo['mime'] as String? ?? '';
    if (!mime.startsWith('image/')) {
      return null;
    }

    final url =
        firstImageInfo['thumburl'] as String? ??
        firstImageInfo['url'] as String? ??
        '';
    if (url.isEmpty) {
      return null;
    }

    return _ImageCandidate(url: url, score: _score(title, url, trail));
  }

  static _ImageCandidate? fromOpenverse(Map result, Trail trail) {
    final title = result['title'] as String? ?? '';
    final url =
        result['thumbnail'] as String? ?? result['url'] as String? ?? '';
    if (!url.startsWith('https://')) {
      return null;
    }

    return _ImageCandidate(url: url, score: _score(title, url, trail));
  }

  static int _score(String title, String url, Trail trail) {
    final haystack = '$title $url'.toLowerCase();
    final trailWords = '${trail.name} ${trail.area} ${trail.state}'
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length >= 4)
        .toSet();

    var score = 0;
    for (final word in trailWords) {
      if (haystack.contains(word)) {
        score += 8;
      }
    }

    if (haystack.contains('trail') || haystack.contains('hiking')) {
      score += 7;
    }
    if (haystack.contains('hill') ||
        haystack.contains('bukit') ||
        haystack.contains('mount') ||
        haystack.contains('gunung')) {
      score += 5;
    }
    if (haystack.contains('forest') ||
        haystack.contains('view') ||
        haystack.contains('summit')) {
      score += 3;
    }
    if (haystack.contains('map') ||
        haystack.contains('diagram') ||
        haystack.contains('logo') ||
        haystack.contains('sign') ||
        haystack.contains('railway')) {
      score -= 14;
    }
    return score;
  }
}
