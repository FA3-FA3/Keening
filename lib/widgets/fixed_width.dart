import 'package:flutter/material.dart';

/// Room a dialog takes for itself on each side of its content: the gap to the
/// edge of the screen and its own padding.
const _dialogChrome = 128.0;

/// A box [width] wide for the content of a dialog. When the screen is too
/// narrow for it the content keeps that width and the box scrolls sideways,
/// instead of squeezing everything into a thinner space.
///
/// (A dialog measures its content's width up front, which a LayoutBuilder
/// cannot answer, so this goes by the size of the screen.)
class FixedWidth extends StatelessWidget {
  const FixedWidth({
    super.key,
    required this.width,
    this.height,
    required this.child,
  });
  final double width;
  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final room = MediaQuery.sizeOf(context).width - _dialogChrome;
    if (room >= width) {
      return SizedBox(width: width, height: height, child: child);
    }
    return SizedBox(
      width: room < 160 ? 160 : room,
      height: height,
      child: SingleChildScrollView(
        key: const ValueKey('sideways-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}

/// [child] laid out at least [minWidth] wide. In a narrower space it keeps
/// that width and scrolls sideways, rather than being squeezed.
class MinWidthScroll extends StatefulWidget {
  const MinWidthScroll({
    super.key,
    required this.minWidth,
    required this.child,
  });
  final double minWidth;
  final Widget child;

  @override
  State<MinWidthScroll> createState() => _MinWidthScrollState();
}

/// Makes the sideways scrolling of a page's smaller scroll areas (a board's
/// panels, the schedule's grid, a timeline) pass to the page itself first when
/// the page is the one being scrolled sideways: dragging such an area moves the
/// whole page until the page reaches its edge, and only then does the smaller
/// area carry on by itself. Give an area `physics: pageChainPhysics(context)`.
class PageSideways extends InheritedWidget {
  const PageSideways({
    super.key,
    required this.controller,
    required super.child,
  });
  final ScrollController controller;

  static ScrollController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageSideways>()?.controller;

  @override
  bool updateShouldNotify(PageSideways old) => old.controller != controller;
}

/// The physics for a smaller scroll area inside a page that scrolls sideways
/// (null, so the area's usual physics, when the page does not scroll).
ScrollPhysics? pageChainPhysics(BuildContext context) {
  final outer = PageSideways.of(context);
  return outer == null ? null : _PageChainPhysics(outer: outer);
}

class _PageChainPhysics extends ScrollPhysics {
  const _PageChainPhysics({super.parent, required this.outer});
  final ScrollController outer;

  @override
  _PageChainPhysics applyTo(ScrollPhysics? ancestor) =>
      _PageChainPhysics(parent: buildParent(ancestor), outer: outer);

  /// A drag of [offset] first moves the page; what the page cannot take (it is
  /// at its edge) is left for this area.
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final base = super.applyPhysicsToUserOffset(position, offset);
    if (!outer.hasClients || base == 0) return base;
    final page = outer.position;
    final target = (page.pixels - base).clamp(
      page.minScrollExtent,
      page.maxScrollExtent,
    );
    final taken = page.pixels - target; // in the direction of the drag
    if (taken == 0) return base;
    page.jumpTo(target);
    return base - taken;
  }
}

class _MinWidthScrollState extends State<MinWidthScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (!box.hasBoundedWidth || box.maxWidth >= widget.minWidth) {
        return widget.child;
      }
      return Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          key: const ValueKey('sideways-scroll'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: PageSideways(
            controller: _controller,
            child: SizedBox(
              width: widget.minWidth,
              height: box.hasBoundedHeight ? box.maxHeight : null,
              child: widget.child,
            ),
          ),
        ),
      );
    },
  );
}
