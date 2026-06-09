import 'package:flutter/material.dart';

import 'daily_brief_panel.dart';

class PullDownBriefPanel extends StatefulWidget {
  const PullDownBriefPanel({super.key, required this.child});

  final Widget child;

  static const double _kBriefMaxHeight = 180;

  @override
  State<PullDownBriefPanel> createState() => _PullDownBriefPanelState();
}

class _PullDownBriefPanelState extends State<PullDownBriefPanel> {
  final _controller = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheetMaxExtent =
        (PullDownBriefPanel._kBriefMaxHeight / MediaQuery.sizeOf(context).height)
            .clamp(0.0, 1.0);

    return Stack(
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DailyBriefPanel(),
        ),

        DraggableScrollableSheet(
          controller: _controller,
          initialChildSize: 1.0,
          minChildSize: 1.0 - sheetMaxExtent,
          maxChildSize: 1.0,
          snap: true,
          snapSizes: [1.0 - sheetMaxExtent, 1.0],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: PrimaryScrollController(
                controller: scrollController,
                child: widget.child,
              ),
            );
          },
        ),
      ],
    );
  }
}
