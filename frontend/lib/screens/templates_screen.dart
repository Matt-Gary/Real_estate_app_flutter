import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<dynamic> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getTemplates();
      setState(() => _templates = data);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _openForm({Map<String, dynamic>? template}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplateFormDialog(template: template),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir template'),
        content: Text('Excluir "${template['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteTemplate(template['id']);
      _load();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // ReorderableListView quirk: when moving an item down, newIndex is
    // one past its real target.
    if (newIndex > oldIndex) newIndex -= 1;

    final previous = List<dynamic>.from(_templates);
    setState(() {
      final moved = _templates.removeAt(oldIndex);
      _templates.insert(newIndex, moved);
    });

    try {
      final ids = _templates.map((t) => t['id'] as String).toList();
      await ApiService.reorderTemplates(ids);
    } catch (e) {
      // Revert on failure.
      setState(() => _templates = previous);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Novo template'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum template criado',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clique em "Novo template" para começar.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _templates.length,
              buildDefaultDragHandles: false,
              onReorder: _onReorder,
              itemBuilder: (_, i) {
                final t = _templates[i] as Map<String, dynamic>;
                return Padding(
                  key: ValueKey(t['id']),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: _SlotBadge(slot: t['default_slot'] as int?),
                      title: Text(
                        t['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        t['body'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar',
                            onPressed: () => _openForm(template: t),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            tooltip: 'Excluir',
                            onPressed: () => _delete(t),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.drag_handle,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SlotBadge extends StatelessWidget {
  final int? slot;
  const _SlotBadge({required this.slot});

  static const _slotColors = <Color>[
    Color(0xFF1976D2), // 1 — blue
    Color(0xFF388E3C), // 2 — green
    Color(0xFFF57C00), // 3 — orange
    Color(0xFF7B1FA2), // 4 — purple
    Color(0xFFC2185B), // 5 — pink
  ];

  @override
  Widget build(BuildContext context) {
    if (slot == null) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey.shade200,
        child: Text(
          '–',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }
    final color = _slotColors[(slot! - 1).clamp(0, 4)];
    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Text(
        '$slot',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ── Template Create / Edit Dialog ─────────────────────────────────────────────

class _TemplateFormDialog extends StatefulWidget {
  final Map<String, dynamic>? template;
  const _TemplateFormDialog({this.template});

  @override
  State<_TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends State<_TemplateFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  int? _selectedSlot;
  int? _originalSlot;

  bool get _isEdit => widget.template != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.template!;
      _nameCtrl.text = t['name'] ?? '';
      _bodyCtrl.text = t['body'] ?? '';
      _originalSlot = t['default_slot'] as int?;
      _selectedSlot = _originalSlot;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// Assigns [slot] to template [id]. On 409 conflict, shows a confirmation
  /// dialog and retries with force=true. Returns true if the slot was
  /// applied (or no change needed); false if the user cancelled.
  Future<bool> _applySlot(String id, int? slot) async {
    try {
      await ApiService.reassignTemplateSlot(id, slot);
      return true;
    } on SlotConflictException catch (conflict) {
      if (!mounted) return false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Slot ${conflict.slot} já em uso'),
          content: Text(
            'O slot ${conflict.slot} já é usado pelo template '
            '"${conflict.conflictingTemplateName}". Deseja reatribuir o slot '
            '${conflict.slot} para este template? O outro template ficará '
            'sem slot padrão.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reatribuir'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
      await ApiService.reassignTemplateSlot(id, slot, force: true);
      return true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = {
        'name': _nameCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
      };

      String templateId;
      if (_isEdit) {
        await ApiService.updateTemplate(widget.template!['id'], payload);
        templateId = widget.template!['id'] as String;
      } else {
        final created = await ApiService.createTemplate(payload);
        templateId = created['id'] as String;
      }

      // Apply slot only if it changed (or it's a new template with a slot).
      final slotChanged = _isEdit
          ? _selectedSlot != _originalSlot
          : _selectedSlot != null;
      if (slotChanged) {
        final applied = await _applySlot(templateId, _selectedSlot);
        if (!applied) {
          // User cancelled the swap dialog. The name/body change stuck;
          // keep the dialog open so they can pick another slot.
          if (mounted) {
            setState(() => _saving = false);
          }
          return;
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _insertPlaceholder(TextEditingController ctrl, String ph) {
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, ph),
      selection: TextSelection.collapsed(offset: start + ph.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Editar template' : 'Novo template',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome do template *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int?>(
                        initialValue: _selectedSlot,
                        decoration: const InputDecoration(
                          labelText: 'Slot padrão (mensagem 1–5)',
                          border: OutlineInputBorder(),
                          helperText:
                              'Pré-preenche este slot ao criar um novo cliente',
                        ),
                        items: const [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Sem slot padrão'),
                          ),
                          DropdownMenuItem<int?>(value: 1, child: Text('Slot 1')),
                          DropdownMenuItem<int?>(value: 2, child: Text('Slot 2')),
                          DropdownMenuItem<int?>(value: 3, child: Text('Slot 3')),
                          DropdownMenuItem<int?>(value: 4, child: Text('Slot 4')),
                          DropdownMenuItem<int?>(value: 5, child: Text('Slot 5')),
                        ],
                        onChanged: (v) => setState(() => _selectedSlot = v),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Mensagem',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Placeholders: {name}  {property_link}  {email}  —  {property_link} → link encurtado do imóvel atribuído ao cliente',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _bodyCtrl,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  hintText: 'Corpo da mensagem...',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? 'Obrigatório'
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                children:
                                    [
                                      '{name}',
                                      '{email}',
                                      '{link_1}',
                                      '{link_2}',
                                      '{link_3}',
                                    ].map((ph) {
                                      return ActionChip(
                                        label: Text(
                                          ph,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _insertPlaceholder(_bodyCtrl, ph),
                                      );
                                    }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
