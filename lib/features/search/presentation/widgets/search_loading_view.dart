library;

import 'package:flutter/material.dart';

class SearchLoadingView extends StatelessWidget {
  const SearchLoadingView({super.key, required this.headerSlivers});

  final List<Widget> headerSlivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }
}
