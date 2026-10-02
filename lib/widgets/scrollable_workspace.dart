import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lets toolbars and the workspace scroll as a page in short windows, while
/// retaining each timeline/board's own scrolling and drag behaviour.
class ScrollableWorkspace extends StatefulWidget {
  const ScrollableWorkspace({
    super.key,
    required this.header,
    required this.body,
    this.minimumBodyHeight = 320,
  });
  final Widget header, body;
  final double minimumBodyHeight;
  @override
  State<ScrollableWorkspace> createState() => _ScrollableWorkspaceState();
}

class _ScrollableWorkspaceState extends State<ScrollableWorkspace> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    child: CustomScrollView(
      key: const ValueKey('workspace-page-scroll'),
      controller: _scroll,
      primary: false,
      slivers: [
        SliverToBoxAdapter(child: widget.header),
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverToBoxAdapter(
            child: SizedBox(
              height: math.max(
                widget.minimumBodyHeight,
                constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent,
              ),
              child: widget.body,
            ),
          ),
        ),
      ],
    ),
  );
}
