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
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _templates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = _templates[i] as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                      ],
                    ),
                  ),
                );
              },
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

  bool get _isEdit => widget.template != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.template!;
      _nameCtrl.text = t['name'] ?? '';
      _bodyCtrl.text = t['body'] ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
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
      if (_isEdit) {
        await ApiService.updateTemplate(widget.template!['id'], payload);
      } else {
        await ApiService.createTemplate(payload);
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
                      const SizedBox(height: 20),
                      Text(
                        'Mensagem',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Placeholders: {name}  {property_link}  {email}',
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
                                      '{property_link}',
                                      '{email}',
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
