import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/image_crop.dart';

/// Opens the crop menu for a picture. Returns the cropped picture, or null if
/// cancelled or nothing was cropped away.
Future<CropResult?> showImageCropper(BuildContext context, Uint8List bytes) =>
    showDialog<CropResult>(
      context: context,
      builder: (_) => _ImageCropper(bytes: bytes),
    );

const _maxWidth = 520.0, _maxHeight = 360.0;

class _ImageCropper extends StatefulWidget {
  const _ImageCropper({required this.bytes});
  final Uint8List bytes;

  @override
  State<_ImageCropper> createState() => _ImageCropperState();
}

class _ImageCropperState extends State<_ImageCropper> {
  ui.Image? _image;
  String? _error;
  var _busy = false;
  CropGeometry? _geometry;
  ui.Rect _box = ui.Rect.zero;
  CropShape _shape = CropShape.free;
  CropHandle? _grabbed;

  @override
  void initState() {
    super.initState();
    decodeImage(widget.bytes).then(
      (image) {
        if (!mounted) return image.dispose();
        setState(() {
          _image = image;
          _geometry = CropGeometry(
            ui.Size(image.width.toDouble(), image.height.toDouble()),
          );
          _box = _geometry!.whole;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _error = 'That picture cannot be opened.');
      },
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  ui.Size get _size => _geometry!.image;

  /// Screen pixels per picture pixel.
  double get _scale => (_maxWidth / _size.width) < (_maxHeight / _size.height)
      ? _maxWidth / _size.width
      : _maxHeight / _size.height;

  bool get _changed => _box != _geometry!.whole;

  void _chooseShape(CropShape shape) {
    final ratio = shape.ratio(_size);
    setState(() {
      _shape = shape;
      if (ratio != null) _box = _geometry!.fitShape(_box, ratio);
    });
  }

  void _reset() => setState(() {
    _box = _geometry!.whole;
    _shape = CropShape.free;
  });

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final png = await cropToPng(_image!, _box);
      if (mounted) Navigator.pop(context, CropResult(png, _box, _size));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'That picture could not be cropped.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _image != null && _geometry != null;
    // A plain Dialog: an AlertDialog measures its contents' natural width.
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Crop picture',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _error!,
                          key: const ValueKey('crop-error'),
                          style: TextStyle(color: scheme.error),
                        ),
                      )
                    else if (!ready)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final s in CropShape.values)
                            ChoiceChip(
                              key: ValueKey('crop-shape-${s.name}'),
                              label: Text(s.label),
                              selected: s == _shape,
                              onSelected: (_) => _chooseShape(s),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(child: _canvas()),
                      const SizedBox(height: 8),
                      Text(
                        '${_box.width.round()} × ${_box.height.round()} px '
                        '(of ${_size.width.round()} × ${_size.height.round()})',
                        key: const ValueKey('crop-size'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Drag the corners and edges to choose what to keep, or '
                        'drag inside the box to move it.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('crop-reset'),
                    onPressed: ready && _changed && !_busy ? _reset : null,
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('crop-cancel'),
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('crop-apply'),
                    onPressed: ready && _changed && !_busy ? _apply : null,
                    child: Text(_busy ? 'Cropping…' : 'Crop'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas() {
    final scale = _scale;
    final size = Size(_size.width * scale, _size.height * scale);
    ui.Offset toPicture(Offset local) =>
        ui.Offset(local.dx / scale, local.dy / scale);
    return GestureDetector(
      key: const ValueKey('crop-canvas'),
      onPanDown: (d) => _grabbed = _geometry!.handleAt(
        _box,
        toPicture(d.localPosition),
        scale,
      ),
      onPanUpdate: (d) {
        final grabbed = _grabbed;
        if (grabbed == null) return;
        setState(
          () => _box = _geometry!.drag(
            _box,
            grabbed,
            ui.Offset(d.delta.dx / scale, d.delta.dy / scale),
            ratio: _shape.ratio(_size),
          ),
        );
      },
      onPanEnd: (_) => _grabbed = null,
      onPanCancel: () => _grabbed = null,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RawImage(image: _image, fit: BoxFit.fill),
            CustomPaint(painter: _CropPainter(_box, scale)),
          ],
        ),
      ),
    );
  }
}

/// Dims what will be cut away and draws the crop box.
class _CropPainter extends CustomPainter {
  _CropPainter(this.box, this.scale);
  final ui.Rect box;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      box.left * scale,
      box.top * scale,
      box.right * scale,
      box.bottom * scale,
    );
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(r),
      ),
      dim,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawRect(r, line);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(r.left + r.width * i / 3, r.top),
        Offset(r.left + r.width * i / 3, r.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(r.left, r.top + r.height * i / 3),
        Offset(r.right, r.top + r.height * i / 3),
        grid,
      );
    }
    final handle = Paint()..color = Colors.white;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black54;
    for (final p in [
      r.topLeft,
      r.topCenter,
      r.topRight,
      r.centerLeft,
      r.centerRight,
      r.bottomLeft,
      r.bottomCenter,
      r.bottomRight,
    ]) {
      final square = Rect.fromCenter(center: p, width: 10, height: 10);
      canvas.drawRect(square, handle);
      canvas.drawRect(square, edge);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.box != box || old.scale != scale;
}
