import 'package:flutter/material.dart';
import '../utils/pad_model.dart';
import 'colour_picker.dart';
import 'app_dialog.dart';

/// Background colours offered in the page settings (any colour can be picked).
const padBackgrounds = [
  '#FFFFFF',
  padPaperColour,
  '#FFF8E1',
  '#E3F2FD',
  '#E8F5E9',
  '#E5E7EB',
  '#1F2937',
  '#000000',
];

/// Grid line colours offered in the page settings.
const padGridColours = ['#D1D5DB', '#9CA3AF', '#93C5FD', '#6B7280', '#FFFFFF'];

/// Asks for the pad's page size, background colour and grid. Returns the new
/// page, or null if cancelled. [minWidth] and [minHeight] are how far the
/// items on the pad reach, so the page cannot be made smaller than its content.
Future<PadPage?> showPadPageDialog(
  BuildContext context, {
  required PadPage page,
  double minWidth = 0,
  double minHeight = 0,
}) => showDialog<PadPage>(
  context: context,
  builder: (_) =>
      _PadPageDialog(page: page, minWidth: minWidth, minHeight: minHeight),
);

const _custom = 'custom';
const _standard = 'standard';

class _PadPageDialog extends StatefulWidget {
  const _PadPageDialog({
    required this.page,
    required this.minWidth,
    required this.minHeight,
  });
  final PadPage page;
  final double minWidth, minHeight;

  @override
  State<_PadPageDialog> createState() => _PadPageDialogState();
}

class _PadPageDialogState extends State<_PadPageDialog> {
  late String _size;
  late bool _landscape;
  PadUnit _unit = PadUnit.px;
  late final _width = TextEditingController();
  late final _height = TextEditingController();
  late final _gridSize = TextEditingController();
  late String _background = widget.page.background;
  late bool _grid = widget.page.grid;
  late String _gridColour = widget.page.gridColour;
  String? _error;

  @override
  void initState() {
    super.initState();
    final page = widget.page;
    final paper = padPaperOf(page);
    if (page.width == PadPage.standard.width &&
        page.height == PadPage.standard.height) {
      _size = _standard;
      _landscape = true;
    } else if (paper != null) {
      _size = paper.paper.name;
      _landscape = paper.landscape;
    } else {
      _size = _custom;
      _landscape = page.width > page.height;
    }
    _fill(page.width, page.height);
    _gridSize.text = _unit.format(page.gridSize);
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _gridSize.dispose();
    super.dispose();
  }

  void _fill(double w, double h) {
    _width.text = _unit.format(w);
    _height.text = _unit.format(h);
  }

  double? _parse(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v == null || !v.isFinite ? null : _unit.toPixels(v);
  }

  void _chooseSize(String value) {
    setState(() {
      _size = value;
      _error = null;
      if (value == _standard) {
        _fill(PadPage.standard.width, PadPage.standard.height);
        _landscape = true;
      } else if (value != _custom) {
        final paper = padPapers.firstWhere((p) => p.name == value);
        final px = paper.pixels(landscape: _landscape);
        _fill(px.width, px.height);
      }
    });
  }

  void _setOrientation(bool landscape) {
    if (landscape == _landscape) return;
    setState(() {
      _landscape = landscape;
      final w = _parse(_width), h = _parse(_height);
      if (w != null && h != null) _fill(h, w);
    });
  }

  void _changeUnit(PadUnit unit) {
    final w = _parse(_width), h = _parse(_height), g = _parse(_gridSize);
    setState(() {
      _unit = unit;
      if (w != null && h != null) _fill(w, h);
      if (g != null) _gridSize.text = _unit.format(g);
    });
  }

  Future<void> _pickBackground() async {
    final choice = await showColourPicker(
      context,
      title: 'Background colour',
      initial: _background,
    );
    if (choice?.hex != null && mounted) {
      setState(() => _background = choice!.hex!);
    }
  }

  Future<void> _pickGridColour() async {
    final choice = await showColourPicker(
      context,
      title: 'Grid line colour',
      initial: _gridColour,
    );
    if (choice?.hex != null && mounted) {
      setState(() => _gridColour = choice!.hex!);
    }
  }

  void _apply() {
    final w = _parse(_width), h = _parse(_height);
    String range(String what) =>
        '$what must be between ${_unit.format(padPageMin)} and '
        '${_unit.format(padPageMax)} ${_unit.label} '
        '(${padPageMin.round()}–${padPageMax.round()} px).';
    if (w == null || h == null) {
      setState(() => _error = 'Enter the page width and height as numbers.');
      return;
    }
    if (w < padPageMin || w > padPageMax) {
      setState(() => _error = range('The width'));
      return;
    }
    if (h < padPageMin || h > padPageMax) {
      setState(() => _error = range('The height'));
      return;
    }
    // Whole pixels, so nothing sits on a half pixel.
    final width = w.roundToDouble(), height = h.roundToDouble();
    if (width < widget.minWidth - 0.5 || height < widget.minHeight - 0.5) {
      setState(
        () => _error =
            'The items on the pad reach ${widget.minWidth.ceil()} × '
            '${widget.minHeight.ceil()} px, so the page cannot be smaller '
            'than that. Move or delete them first.',
      );
      return;
    }
    var spacing = widget.page.gridSize;
    if (_grid) {
      final g = _parse(_gridSize);
      if (g == null || g < padGridMin || g > padGridMax) {
        setState(
          () => _error =
              'The grid spacing must be between ${_unit.format(padGridMin)} '
              'and ${_unit.format(padGridMax)} ${_unit.label} '
              '(${padGridMin.round()}–${padGridMax.round()} px).',
        );
        return;
      }
      spacing = g;
    }
    Navigator.pop(
      context,
      PadPage(
        width: width,
        height: height,
        background: _background,
        grid: _grid,
        gridSize: spacing,
        gridColour: _gridColour,
      ),
    );
  }

  void _reset() {
    setState(() {
      const p = PadPage.standard;
      _size = _standard;
      _landscape = true;
      _unit = PadUnit.px;
      _fill(p.width, p.height);
      _gridSize.text = _unit.format(p.gridSize);
      _background = p.background;
      _grid = p.grid;
      _gridColour = p.gridColour;
      _error = null;
    });
  }

  Widget _swatch(Key key, String hex, String selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final on = hex.toUpperCase() == selected.toUpperCase();
    return Tooltip(
      message: hex,
      child: InkWell(
        key: key,
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: padColor(hex),
            shape: BoxShape.circle,
            border: Border.all(
              color: on ? scheme.primary : scheme.outline,
              width: on ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final named = _size != _custom && _size != _standard;
    final standard = PadPage.standard;
    return AppAlertDialog(
      width: 480,
      key: const ValueKey('page-dialog'),
      title: const Text('Page setup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('page-size'),
              initialValue: _size,
              decoration: const InputDecoration(labelText: 'Page size'),
              items: [
                DropdownMenuItem(
                  value: _standard,
                  child: Text(
                    'Default (${standard.width.round()} × ${standard.height.round()} px)',
                  ),
                ),
                for (final p in padPapers)
                  DropdownMenuItem(
                    value: p.name,
                    child: Text(
                      '${p.name} (${_mm(p.widthMm)} × ${_mm(p.heightMm)} mm)',
                    ),
                  ),
                const DropdownMenuItem(
                  value: _custom,
                  child: Text('Custom size'),
                ),
              ],
              onChanged: (v) => _chooseSize(v ?? _size),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const ValueKey('page-orientation'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.crop_portrait),
                  label: Text('Portrait'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.crop_landscape),
                  label: Text('Landscape'),
                ),
              ],
              selected: {_landscape},
              onSelectionChanged: (s) => _setOrientation(s.first),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('page-width'),
                    controller: _width,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Width'),
                    onChanged: (_) => setState(() {
                      if (named || _size == _standard) _size = _custom;
                    }),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 16, 8, 0),
                  child: Text('×'),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('page-height'),
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Height'),
                    onChanged: (_) => setState(() {
                      if (named || _size == _standard) _size = _custom;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  child: DropdownButtonFormField<PadUnit>(
                    key: const ValueKey('page-unit'),
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: [
                      for (final u in PadUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: (u) => _changeUnit(u ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Background colour',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final hex in padBackgrounds)
                  _swatch(
                    ValueKey('page-bg-$hex'),
                    hex,
                    _background,
                    () => setState(() => _background = hex),
                  ),
                TextButton.icon(
                  key: const ValueKey('page-bg-custom'),
                  onPressed: _pickBackground,
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Other…'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('page-grid'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show grid lines'),
              value: _grid,
              onChanged: (v) => setState(() => _grid = v),
            ),
            if (_grid) ...[
              TextField(
                key: const ValueKey('page-grid-size'),
                controller: _gridSize,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Grid spacing',
                  suffixText: _unit.label,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Line colour',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  for (final hex in padGridColours)
                    _swatch(
                      ValueKey('page-grid-colour-$hex'),
                      hex,
                      _gridColour,
                      () => setState(() => _gridColour = hex),
                    ),
                  TextButton(
                    key: const ValueKey('page-grid-colour-custom'),
                    onPressed: _pickGridColour,
                    child: const Text('Other…'),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('page-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('page-reset'),
          onPressed: _reset,
          child: const Text('Reset'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('page-apply'),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  static String _mm(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}
