import 'package:aves/model/entry.dart';
import 'package:aves/model/filters/album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/services.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

mixin AlbumMixin on SourceBase {
  final Set<String> _directories = {};

  List<String> get rawAlbums => List.unmodifiable(_directories);

  int compareAlbumsByName(String a, String b) {
    final ua = getAlbumDisplayName(null, a);
    final ub = getAlbumDisplayName(null, b);
    final c = compareAsciiUpperCase(ua, ub);
    if (c != 0) return c;
    final va = androidFileUtils.getStorageVolume(a)?.path ?? '';
    final vb = androidFileUtils.getStorageVolume(b)?.path ?? '';
    return compareAsciiUpperCase(va, vb);
  }

  void _notifyAlbumChange() => eventBus.fire(AlbumsChangedEvent());

  String getAlbumDisplayName(BuildContext context, String dirPath) {
    assert(!dirPath.endsWith(pContext.separator));

    if (context != null) {
      final type = androidFileUtils.getAlbumType(dirPath);
      if (type == AlbumType.camera) return context.l10n.albumCamera;
      if (type == AlbumType.download) return context.l10n.albumDownload;
      if (type == AlbumType.screenshots) return context.l10n.albumScreenshots;
      if (type == AlbumType.screenRecordings) return context.l10n.albumScreenRecordings;
    }

    final dir = VolumeRelativeDirectory.fromPath(dirPath);
    if (dir == null) return dirPath;

    final relativeDir = dir.relativeDir;
    if (relativeDir.isEmpty) {
      final volume = androidFileUtils.getStorageVolume(dirPath);
      return volume.getDescription(context);
    }

    String unique(String dirPath, Set<String> others) {
      final parts = pContext.split(dirPath);
      for (var i = parts.length - 1; i > 0; i--) {
        final testName = pContext.joinAll(['', ...parts.skip(i)]);
        if (others.every((item) => !item.endsWith(testName))) return testName;
      }
      return dirPath;
    }

    final otherAlbumsOnDevice = _directories.where((item) => item != dirPath).toSet();
    final uniqueNameInDevice = unique(dirPath, otherAlbumsOnDevice);
    if (uniqueNameInDevice.length < relativeDir.length) {
      return uniqueNameInDevice;
    }

    final volumePath = dir.volumePath;
    String trimVolumePath(String path) => path.substring(dir.volumePath.length);
    final otherAlbumsOnVolume = otherAlbumsOnDevice.where((path) => path.startsWith(volumePath)).map(trimVolumePath).toSet();
    final uniqueNameInVolume = unique(trimVolumePath(dirPath), otherAlbumsOnVolume);
    final volume = androidFileUtils.getStorageVolume(dirPath);
    if (volume.isPrimary) {
      return uniqueNameInVolume;
    } else {
      return '$uniqueNameInVolume (${volume.getDescription(context)})';
    }
  }

  Map<String, AvesEntry> getAlbumEntries() {
    final entries = sortedEntriesByDate;
    final regularAlbums = <String>[], appAlbums = <String>[], specialAlbums = <String>[];
    for (final album in rawAlbums) {
      switch (androidFileUtils.getAlbumType(album)) {
        case AlbumType.regular:
          regularAlbums.add(album);
          break;
        case AlbumType.app:
          appAlbums.add(album);
          break;
        default:
          specialAlbums.add(album);
          break;
      }
    }
    return Map.fromEntries([...specialAlbums, ...appAlbums, ...regularAlbums].map((album) => MapEntry(
          album,
          entries.firstWhere((entry) => entry.directory == album, orElse: () => null),
        )));
  }

  void updateDirectories() {
    final visibleDirectories = visibleEntries.map((entry) => entry.directory).toSet();
    addDirectories(visibleDirectories);
    cleanEmptyAlbums();
  }

  void addDirectories(Set<String> albums) {
    if (!_directories.containsAll(albums)) {
      _directories.addAll(albums);
      _notifyAlbumChange();
    }
  }

  void cleanEmptyAlbums([Set<String> albums]) {
    final emptyAlbums = (albums ?? _directories).where(_isEmptyAlbum).toSet();
    if (emptyAlbums.isNotEmpty) {
      _directories.removeAll(emptyAlbums);
      _notifyAlbumChange();
      invalidateAlbumFilterSummary(directories: emptyAlbums);

      final pinnedFilters = settings.pinnedFilters;
      emptyAlbums.forEach((album) => pinnedFilters.removeWhere((filter) => filter is AlbumFilter && filter.album == album));
      settings.pinnedFilters = pinnedFilters;
    }
  }

  bool _isEmptyAlbum(String album) => !visibleEntries.any((entry) => entry.directory == album);

  // filter summary

  // by directory
  final Map<String, int> _filterEntryCountMap = {};
  final Map<String, AvesEntry> _filterRecentEntryMap = {};

  void invalidateAlbumFilterSummary({Set<AvesEntry> entries, Set<String> directories}) {
    if (entries == null && directories == null) {
      _filterEntryCountMap.clear();
      _filterRecentEntryMap.clear();
    } else {
      directories ??= entries.map((entry) => entry.directory).toSet();
      directories.forEach(_filterEntryCountMap.remove);
      directories.forEach(_filterRecentEntryMap.remove);
    }
    eventBus.fire(AlbumSummaryInvalidatedEvent(directories));
  }

  int albumEntryCount(AlbumFilter filter) {
    return _filterEntryCountMap.putIfAbsent(filter.album, () => visibleEntries.where(filter.test).length);
  }

  AvesEntry albumRecentEntry(AlbumFilter filter) {
    return _filterRecentEntryMap.putIfAbsent(filter.album, () => sortedEntriesByDate.firstWhere(filter.test, orElse: () => null));
  }
}

class AlbumsChangedEvent {}

class AlbumSummaryInvalidatedEvent {
  final Set<String> directories;

  const AlbumSummaryInvalidatedEvent(this.directories);
}
