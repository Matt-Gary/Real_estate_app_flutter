import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Multi-select chip input for client labels.
///
/// Shows the agent's full label catalogue as filter-style chips. Selected
/// chips are filled; unselected are outlined. A "+ Nova etiqueta" trailing
/// chip lets the agent create a label inline without leaving the form.
///
/// Pure controlled widget — caller owns the [selectedIds] list and is
/// notified via [onChanged] every time the selection mutates.
class LabelChipInput extends StatefulWidget {
  final List<dynamic> allLabels;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;
  final bool allowCreate;

  /// Called after a new label is created via the inline dialog. Lets the
  /// parent refresh its label catalogue.
  final ValueChanged<dynamic>? onLabelCreated;

  const LabelChipInput({
    super.key,
    required this.allLabels,
    required this.selectedIds,
    required this.onChanged,
    this.allowCreate = true,
    this.onLabelCreated,
  });

  @override
  State<LabelChipInput> createState() => _LabelChipInputState();
}

class _LabelChipInputState extends State<LabelChipInput> {
  Color _chipColor(dynamic label) {
    final hex = label['color'] as String?;
    if (hex == null) return Colors.blueGrey.shade400;
    return _parseHex(hex) ?? Colors.blueGrey.shade400;
  }

  Color? _parseHex(String hex) {
    final s = hex.replaceFirst('#', '');
    if (s.length == 3) {
      final r = int.tryParse(s[0] * 2, radix: 16);
      final g = int.tryParse(s[1] * 2, radix: 16);
      final b = int.tryParse(s[2] * 2, radix: 16);
      if (r == null || g == null || b == null) return null;
      return Color.fromARGB(255, r, g, b);
    }
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v == null) return null;
      return Color(0xFF000000 | v);
    }
    return null;
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => const _CreateLabelDialog(),
    );
    if (created != null && mounted) {
      widget.onLabelCreated?.call(created);
      widget.onChanged([...widget.selectedIds, created['id'] as String]);
    }
  }

  void _toggle(String id) {
    final next = [...widget.selectedIds];
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedIds.toSet();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...widget.allLabels.map((label) {
          final id = label['id'] as String;
          final isSelected = selected.contains(id);
          final color = _chipColor(label);
          return FilterChip(
            selected: isSelected,
            onSelected: (_) => _toggle(id),
            label: Text(label['name'] as String),
            avatar: CircleAvatar(backgroundColor: color, radius: 6),
            selectedColor: color.withValues(alpha: 0.18),
            checkmarkColor: color,
            side: BorderSide(color: color.withValues(alpha: isSelected ? 0.6 : 0.3)),
          );
        }),
        if (widget.allowCreate)
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Nova etiqueta'),
            onPressed: _openCreateDialog,
          ),
      ],
    );
  }
}

class _CreateLabelDialog extends StatefulWidget {
  const _CreateLabelDialog();

  @override
  State<_CreateLabelDialog> createState() => _CreateLabelDialogState();
}

class _CreateLabelDialogState extends State<_CreateLabelDialog> {
  final _ctrl = TextEditingController();
  String? _color;
  bool _saving = false;
  String? _error;

  static const _palette = <String>[
    '#1976D2', '#388E3C', '#D32F2F', '#F57C00', '#7B1FA2',
    '#00796B', '#5D4037', '#455A64', '#C2185B', '#0097A7',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _parse(String hex) => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nome obrigatório');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final created = await ApiService.createLabel(name: name, color: _color);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova etiqueta'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex: Compra de terreno',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            const Text('Cor', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette.map((hex) {
                final selected = _color == hex;
                return GestureDetector(
                  onTap: () => setState(() => _color = selected ? null : hex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _parse(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.black87 : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Criar'),
        ),
      ],
    );
  }
}

/// Compact read-only chip strip for label display on client tiles.
class LabelChipsDisplay extends StatelessWidget {
  final List<dynamic> labels;
  final int maxVisible;
  const LabelChipsDisplay({super.key, required this.labels, this.maxVisible = 3});

  Color _parseHex(String? hex) {
    if (hex == null) return Colors.blueGrey.shade400;
    final s = hex.replaceFirst('#', '');
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return Colors.blueGrey.shade400;
  }

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    final shown = labels.take(maxVisible).toList();
    final overflow = labels.length - shown.length;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...shown.map((l) {
          final color = _parseHex(l['color'] as String?);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              l['name'] as String? ?? '',
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          );
        }),
        if (overflow > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+$overflow',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
