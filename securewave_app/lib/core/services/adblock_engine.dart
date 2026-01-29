import 'dart:async';
import 'dart:io';

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Efficient domain matcher using reversed-suffix hash set
/// This provides O(domain-depth) lookup instead of linear scan
class DomainMatcher {
  DomainMatcher(this._blockedDomains);

  final Set<String> _blockedDomains;

  bool isBlocked(String domain) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // Split domain into parts: example.com -> ['example', 'com']
    final parts = normalized.split('.');
    if (parts.length < 2) return false;

    // Check all suffix combinations from longest to shortest
    // For 'tracker.ads.example.com', checks:
    // 1. tracker.ads.example.com
    // 2. ads.example.com
    // 3. example.com
    // 4. com
    var suffix = '';
    for (var i = parts.length - 1; i >= 0; i--) {
      suffix = suffix.isEmpty ? parts[i] : '${parts[i]}.$suffix';
      if (_blockedDomains.contains(suffix)) {
        return true;
      }
    }
    return false;
  }

  int get ruleCount => _blockedDomains.length;
}

/// Blocklist provider: downloads and caches blocklists
class BlocklistProvider {
  static const String _cacheFileName = 'adblock_cache.txt';

  /// Downloads blocklist from remote URL with timeout
  Future<String> fetchRemote(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    final response = await dio.get<String>(url);
    return response.data ?? '';
  }

  /// Loads blocklist from asset bundle
  Future<String> loadAsset(String assetPath) async {
    return await rootBundle.loadString(assetPath);
  }

  /// Saves blocklist to cache (atomic write)
  Future<void> saveCache(String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      final tempFile = File('${file.path}.tmp');

      // Write to temp file first
      await tempFile.writeAsString(content);

      // Atomic rename
      await tempFile.rename(file.path);
    } catch (error) {
      // Cache write failures are non-critical
      // Log but don't throw
    }
  }

  /// Loads blocklist from cache if available
  Future<String?> loadCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (error) {
      // Cache read failures are non-critical
    }
    return null;
  }
}

/// Main adblock engine: coordinates blocklist loading and domain matching
class AdblockEngine {
  AdblockEngine({required this.fallbackAssetPath})
      : _provider = BlocklistProvider();

  final String fallbackAssetPath;
  final BlocklistProvider _provider;
  DomainMatcher? _matcher;

  DomainMatcher? get matcher => _matcher;

  /// Load blocklist from fallback asset
  Future<int> loadFallback() async {
    final content = await _provider.loadAsset(fallbackAssetPath);
    final entries = parseListForTesting(content);
    _matcher = DomainMatcher(entries);
    return entries.length;
  }

  /// Load blocklist from cache if available
  Future<int?> loadCache() async {
    final content = await _provider.loadCache();
    if (content == null) return null;
    final entries = parseListForTesting(content);
    if (entries.isNotEmpty) {
      _matcher = DomainMatcher(entries);
      return entries.length;
    }
    return null;
  }

  /// Update blocklist from remote URL
  Future<int> updateFromRemote(String url) async {
    final content = await _provider.fetchRemote(url);
    final entries = parseListForTesting(content);
    if (entries.isNotEmpty) {
      _matcher = DomainMatcher(entries);
      // Save to cache for next boot
      await _provider.saveCache(content);
    }
    return entries.length;
  }

  /// Parse EasyList-style blocklist format
  Set<String> parseListForTesting(String content) {
    final lines = const LineSplitter().convert(content);
    final entries = <String>{};

    for (final line in lines) {
      final cleaned = line.trim();

      // Skip empty lines and comments
      if (cleaned.isEmpty || cleaned.startsWith('#') || cleaned.startsWith('!')) {
        continue;
      }

      // Extract domain from various formats:
      // ||example.com^ -> example.com
      // ||ads.example.com^ -> ads.example.com
      var domain = cleaned.split(' ').first;
      domain = domain.replaceFirst('||', '').replaceAll('^', '');

      // Only add valid domains (must contain at least one dot)
      if (domain.contains('.')) {
        entries.add(domain.toLowerCase());
      }
    }

    return entries;
  }
}
