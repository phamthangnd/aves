import 'dart:async';

import 'package:aves/model/image_entry.dart';
import 'package:aves/model/metadata_service.dart';
import 'package:aves/widgets/fullscreen/info/info_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MetadataSection extends StatefulWidget {
  final ImageEntry entry;

  const MetadataSection({this.entry});

  @override
  State<StatefulWidget> createState() => MetadataSectionState();
}

class MetadataSectionState extends State<MetadataSection> {
  Future<Map> _metadataLoader;

  @override
  void initState() {
    super.initState();
    _initMetadataLoader();
  }

  @override
  void didUpdateWidget(MetadataSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initMetadataLoader();
  }

  Future<void> _initMetadataLoader() async {
    _metadataLoader = MetadataService.getAllMetadata(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MediaQueryData, double>(
      selector: (c, mq) => mq.size.width,
      builder: (c, mqWidth, child) => FutureBuilder(
        future: _metadataLoader,
        builder: (futureContext, AsyncSnapshot<Map> snapshot) {
          if (snapshot.hasError) return Text(snapshot.error.toString());
          if (snapshot.connectionState != ConnectionState.done) return const SizedBox.shrink();
          final metadataMap = snapshot.data.cast<String, Map>();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionRow('Metadata'),
              _MetadataSectionContent(
                metadataMap: metadataMap,
                split: mqWidth > 400,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetadataSectionContent extends StatelessWidget {
  final Map<String, Map> metadataMap;
  final List<String> directoryNames;
  final bool split;

  _MetadataSectionContent({@required this.metadataMap, @required this.split}) : directoryNames = metadataMap.keys.toList()..sort();

  @override
  Widget build(BuildContext context) {
    if (split) {
      final first = <String>[], second = <String>[];
      var firstItemCount = 0, secondItemCount = 0;
      var firstIndex = 0, secondIndex = directoryNames.length - 1;
      while (firstIndex <= secondIndex) {
        if (firstItemCount <= secondItemCount) {
          final directoryName = directoryNames[firstIndex++];
          first.add(directoryName);
          firstItemCount += 2 + metadataMap[directoryName].length;
        } else {
          final directoryName = directoryNames[secondIndex--];
          second.insert(0, directoryName);
          secondItemCount += 2 + metadataMap[directoryName].length;
        }
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _MetadataColumn(metadataMap: metadataMap, directoryNames: first)),
          const SizedBox(width: 8),
          Expanded(child: _MetadataColumn(metadataMap: metadataMap, directoryNames: second)),
        ],
      );
    } else {
      return _MetadataColumn(metadataMap: metadataMap, directoryNames: directoryNames);
    }
  }
}

class _MetadataColumn extends StatelessWidget {
  final Map<String, Map> metadataMap;
  final List<String> directoryNames;

  const _MetadataColumn({@required this.metadataMap, @required this.directoryNames});

  static const int maxValueLength = 140;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...directoryNames.expand((directoryName) {
          final directory = metadataMap[directoryName];
          final tagKeys = directory.keys.toList()..sort();
          return [
            if (directoryName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(directoryName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontFamily: 'Concourse Caps',
                    )),
              ),
            ...tagKeys.map((tagKey) {
              final value = directory[tagKey] as String;
              if (value == null || value.isEmpty) return const SizedBox.shrink();
              return InfoRow(tagKey, value.length > maxValueLength ? '${value.substring(0, maxValueLength)}…' : value);
            }),
            const SizedBox(height: 16),
          ];
        }),
      ],
    );
  }
}
