import 'package:flutter/material.dart';
import '../utils/colour_library.dart';
import '../utils/rich_text.dart' show hexColor;

/// What the picker returns: a colour, or null [hex] for "no colour" (the
/// document's default text colour, or no highlight).
class ColourChoice {
  const ColourChoice(this.hex);
  final String? hex;
}

String _hexOf(Color c) {
  String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

/// Opens the colour picker. Cancelling returns null; choosing "no colour"
/// returns a [ColourChoice] without a colour.
Future<ColourChoice?> showColourPicker(
  BuildContext context, {
  required String title,
  String? initial,
  String? noneLabel,
  ColourLibrary? library,
}) => showDialog<ColourChoice>(
  context: context,
  builder: (_) => _ColourPicker(
    title: title,
    initial: initial,
    noneLabel: noneLabel,
    library: library ?? ColourLibrary.shared,
  ),
);

class _ColourPicker extends StatefulWidget {
  const _ColourPicker({
    required this.title,
    required this.initial,
    required this.noneLabel,
    required this.library,
  });
  final String title;
  final String? initial;
  final String? noneLabel;
  final ColourLibrary library;

  @override
  State<_ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<_ColourPicker> {
  late HSVColor _hsv = HSVColor.fromColor(
    hexColor(normalizeHex(widget.initial ?? '') ?? '#2563EB'),
  );
  late final _hexField = TextEditingController(text: _hex);
  String? _message;

  String get _hex => _hexOf(_hsv.toColor());

  @override
  void dispose() {
    _hexField.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _message = null;
      _hexField.text = _hex;
    });
  }

  void _typed(String value) {
    final hex = normalizeHex(value);
    if (hex != null) {
      setState(() {
        _hsv = HSVColor.fromColor(hexColor(hex));
        _message = null;
      });
    }
  }

  void _apply(String hex) {
    widget.library.use(hex);
    Navigator.pop(context, ColourChoice(hex));
  }

  void _submit() {
    final hex = normalizeHex(_hexField.text);
    if (hex == null) {
      setState(() => _message = 'Enter a colour like #2563EB.');
      return;
    }
    _apply(hex);
  }

  Widget _chip(String hex, String keyPrefix) => Tooltip(
    message: hex,
    child: InkResponse(
      key: ValueKey('$keyPrefix-$hex'),
      onTap: () => _apply(hex),
      radius: 16,
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: hexColor(hex),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade500),
        ),
      ),
    ),
  );

  Widget _row(
    String label,
    List<String> colours,
    String keyPrefix,
    String empty,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        if (colours.isEmpty)
          Text(empty, style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(children: [for (final hex in colours) _chip(hex, keyPrefix)]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 300,
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Saturation (across) and brightness (down) for the chosen hue.
              _SaturationValueBox(
                key: const ValueKey('colour-sv'),
                hsv: _hsv,
                onChanged: _set,
              ),
              const SizedBox(height: 8),
              _HueSlider(
                key: const ValueKey('colour-hue'),
                hue: _hsv.hue,
                onChanged: (h) => _set(_hsv.withHue(h)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    key: const ValueKey('colour-preview'),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _hsv.toColor(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('colour-hex'),
                      controller: _hexField,
                      decoration: InputDecoration(
                        labelText: 'Hex colour',
                        isDense: true,
                        errorText: _message,
                      ),
                      onChanged: _typed,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('colour-favourite'),
                    tooltip: library.isFavourite(_hex)
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    onPressed: () {
                      if (!library.toggleFavourite(_hex)) {
                        setState(
                          () => _message =
                              'You can keep up to ${ColourLibrary.maxFavourites} favourites.',
                        );
                      }
                    },
                    icon: Icon(
                      library.isFavourite(_hex)
                          ? Icons.star
                          : Icons.star_border,
                      color: library.isFavourite(_hex) ? Colors.amber : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _row(
                'Favourites',
                library.favourites,
                'colour-favourite-chip',
                'Star a colour to keep it here.',
              ),
              const SizedBox(height: 8),
              _row(
                'Recently used',
                library.recent,
                'colour-recent',
                'Colours you use appear here.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.noneLabel != null)
          TextButton(
            key: const ValueKey('colour-none'),
            onPressed: () => Navigator.pop(context, const ColourChoice(null)),
            child: Text(widget.noneLabel!),
          ),
        TextButton(
          key: const ValueKey('colour-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('colour-apply'),
          onPressed: _submit,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({
    super.key,
    required this.hsv,
    required this.onChanged,
  });
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _pick(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  static const size = Size(300, 160);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanDown: (d) => _pick(d.localPosition, size),
    onPanUpdate: (d) => _pick(d.localPosition, size),
    child: SizedBox.fromSize(
      size: size,
      child: CustomPaint(painter: _SvPainter(hsv)),
    ),
  );
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hue],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final at = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      at,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      at,
      9.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hsv != hsv;
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({super.key, required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(
              colors: [
                for (var h = 0; h <= 360; h += 60)
                  HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
              ],
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 0,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
          ),
          child: Slider(value: hue, min: 0, max: 360, onChanged: onChanged),
        ),
      ],
    ),
  );
}
