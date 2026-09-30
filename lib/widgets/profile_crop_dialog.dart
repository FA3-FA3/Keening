import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ProfileCropDialog extends StatefulWidget {
  const ProfileCropDialog({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<ProfileCropDialog> createState() => _ProfileCropDialogState();
}

class _ProfileCropDialogState extends State<ProfileCropDialog> {
  ui.Image? _image;
  String? _error;
  double _zoom = 1;
  Offset _center = Offset.zero;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      // Encoded ImageDescriptor dimensions are unavailable on Flutter web.
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: 1024,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        if (!mounted) {
          frame.image.dispose();
          return;
        }
        if (frame.image.width * frame.image.height > 40000000) {
          frame.image.dispose();
          throw StateError('Choose a smaller image.');
        }
        setState(() {
          _image = frame.image;
          _center = Offset(frame.image.width / 2, frame.image.height / 2);
        });
      } finally {
        codec.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : 'Unable to read this image. Choose another picture.',
        );
      }
    }
  }

  double get _side => math.min(_image!.width, _image!.height) / _zoom;
  Rect get _crop =>
      Rect.fromCenter(center: _center, width: _side, height: _side);
  void _clampCenter() {
    final half = _side / 2;
    _center = Offset(
      _center.dx.clamp(half, _image!.width - half),
      _center.dy.clamp(half, _image!.height - half),
    );
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        _image!,
        _crop,
        const Rect.fromLTWH(0, 0, 256, 256),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final result = await picture.toImage(256, 256);
        try {
          final data = await result.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Unable to crop this picture.');
          if (mounted) {
            Navigator.pop(
              context,
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          }
        } finally {
          result.dispose();
        }
      } finally {
        picture.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = 'Unable to crop this picture. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_applying,
    child: AlertDialog(
      title: const Text('Crop profile picture'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_image == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              if (_image != null) ...[
                const Text('Drag to reposition. Use the slider to zoom.'),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) => AspectRatio(
                    aspectRatio: 1,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: GestureDetector(
                        key: const ValueKey('profile-crop-preview'),
                        onPanUpdate: _applying
                            ? null
                            : (details) => setState(() {
                                _center -=
                                    details.delta *
                                    (_side / constraints.maxWidth);
                                _clampCenter();
                              }),
                        child: CustomPaint(
                          painter: _CropPainter(_image!, _crop),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.zoom_out),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('profile-crop-zoom'),
                        min: 1,
                        max: 4,
                        value: _zoom,
                        label: '${_zoom.toStringAsFixed(1)}x',
                        semanticFormatterCallback: (value) =>
                            'Zoom ${value.toStringAsFixed(1)} times',
                        onChanged: _applying
                            ? null
                            : (value) => setState(() {
                                _zoom = value;
                                _clampCenter();
                              }),
                      ),
                    ),
                    const Icon(Icons.zoom_in),
                  ],
                ),
                TextButton(
                  onPressed: _applying
                      ? null
                      : () => setState(() {
                          _zoom = 1;
                          _center = Offset(
                            _image!.width / 2,
                            _image!.height / 2,
                          );
                        }),
                  child: const Text('Reset crop'),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _image == null || _applying ? null : _apply,
          child: Text(_applying ? 'Applying...' : 'Apply'),
        ),
      ],
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);
  final ui.Image image;
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    canvas.drawImageRect(
      image,
      crop,
      bounds,
      Paint()..filterQuality = FilterQuality.high,
    );
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(bounds),
      Path()..addOval(bounds),
    );
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: .5));
    canvas.drawOval(
      bounds.deflate(1),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      image != oldDelegate.image || crop != oldDelegate.crop;
}
