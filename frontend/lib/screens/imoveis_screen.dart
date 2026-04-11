import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ImobeisScreen extends StatefulWidget {
  const ImobeisScreen({super.key});

  @override
  State<ImobeisScreen> createState() => _ImobeisScreenState();
}

class _ImobeisScreenState extends State<ImobeisScreen> {
  List<dynamic> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getPropertyLinks();
      setState(() => _links = data);
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

  Future<void> _openForm({Map<String, dynamic>? link}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PropertyLinkFormDialog(link: link),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir imóvel'),
        content: Text('Excluir "${link['description']}"?'),
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
      await ApiService.deletePropertyLink(link['id']);
      _load();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imóveis'),
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
        label: const Text('Novo imóvel'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home_work_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum imóvel cadastrado',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clique em "Novo imóvel" para cadastrar.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _links.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final lk = _links[i] as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      lk['description'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      lk['link'] ?? '',
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
                          onPressed: () => _openForm(link: lk),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          tooltip: 'Excluir',
                          onPressed: () => _delete(lk),
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

// ── Property Link Create / Edit Dialog ────────────────────────────────────────

class _PropertyLinkFormDialog extends StatefulWidget {
  final Map<String, dynamic>? link;
  const _PropertyLinkFormDialog({this.link});

  @override
  State<_PropertyLinkFormDialog> createState() =>
      _PropertyLinkFormDialogState();
}

class _PropertyLinkFormDialogState extends State<_PropertyLinkFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.link != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final lk = widget.link!;
      _descriptionCtrl.text = lk['description'] ?? '';
      _linkCtrl.text = lk['link'] ?? '';
    }
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _linkCtrl.dispose();
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
        'description': _descriptionCtrl.text.trim(),
        'link': _linkCtrl.text.trim(),
      };
      if (_isEdit) {
        await ApiService.updatePropertyLink(widget.link!['id'], payload);
      } else {
        await ApiService.createPropertyLink(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                      _isEdit ? 'Editar imóvel' : 'Novo imóvel',
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
                        controller: _descriptionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descrição *',
                          hintText: 'Ex: Cond. Fortaleza 4 dormitórios',
                          helperText:
                              'Identificação interna — aparece na lista ao cadastrar clientes',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _linkCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Link do imóvel *',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
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
