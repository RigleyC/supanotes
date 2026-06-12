library;

import 'package:flutter/material.dart';

import 'package:supanotes/shared/widgets/empty_state.dart';

class SearchErrorView extends StatelessWidget {
  const SearchErrorView({
    super.key,
    required this.headerSlivers,
    required this.error,
  });

  final List<Widget> headerSlivers;
  final String error;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.cloud_off,
            title: 'Erro na busca',
            subtitle: error,
          ),
        ),
      ],
    );
  }
}
