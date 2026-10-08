import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Content that scrolls sideways when it is wider than the space it is given,
/// with a scrollbar along the bottom that shows only when there is something
/// to scroll. It scrolls by dragging (with a mouse too, not only touch), with
/// the scrollbar, or with a sideways wheel or trackpad swipe.
class HorizontalScroll extends StatefulWidget {
  const HorizontalScroll({super.key, required this.child});
  final Widget child;

  @override
  State<HorizontalScroll> createState() => _HorizontalScrollState();
}

class _HorizontalScrollState extends State<HorizontalScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      // Dragging with the mouse scrolls too.
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(dragDevices: {...PointerDeviceKind.values}, scrollbars: false),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          // Room beneath for the scrollbar.
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
