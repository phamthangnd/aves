import 'package:aves/model/image_collection.dart';
import 'package:aves/model/image_entry.dart';
import 'package:aves/widgets/album/thumbnail_collection.dart';
import 'package:aves/widgets/common/providers/media_query_data_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FilteredCollectionPage extends StatelessWidget {
  final ImageCollection collection;
  final bool Function(ImageEntry) filter;
  final String title;

  FilteredCollectionPage({Key key, ImageCollection collection, this.filter, this.title})
      : this.collection = collection.filter(filter),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return MediaQueryDataProvider(
      child: Scaffold(
        body: ChangeNotifierProvider<ImageCollection>.value(
          value: collection,
          child: ThumbnailCollection(
            appBar: SliverAppBar(
              title: Text(title),
              floating: true,
            ),
          ),
        ),
        resizeToAvoidBottomInset: false,
      ),
    );
  }
}
