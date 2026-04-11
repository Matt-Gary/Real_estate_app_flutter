import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'templates_screen.dart';

class ClientFormScreen extends StatefulWidget {
  final dynamic client; // null = new client
  const ClientFormScreen({super.key, this.client});

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late List<TextEditingController> _bodyCtrl;
  late List<DateTime?> _sendAt;

  List<dynamic> _templates = [];
  List<String?> _selectedTemplateIds = List.generate(5, (_) => null);
  final List<GlobalKey<FormFieldState<String?>>> _dropdownKeys =
      List.generate(5, (_) => GlobalKey<FormFieldState<String?>>());

  bool _loading = false;
  bool _loadingData = true;
  String? _error;

  bool get _isEdit => widget.client != null;

  @override
  void initState() {
    super.initState();
    _bodyCtrl = List.generate(5, (_) => TextEditingController());
    _sendAt = List.generate(5, (_) => null);
    _init();
  }

  Future<void> _init() async {
    if (_isEdit) {
      final c = widget.client;
      _nameCtrl.text = c['name'] ?? '';
      _phoneCtrl.text = c['phone_number'] ?? '';
      _emailCtrl.text = c['email'] ?? '';
      _linkCtrl.text = c['property_link'] ?? '';
      _notesCtrl.text = c['notes'] ?? '';
    }

    try {
      // Always load agent templates for the dropdown
      final templates = await ApiService.getTemplates();
      _templates = templates;

      if (_isEdit) {
        final msgs = await ApiService.getMessages(widget.client['id']);
        for (final m in msgs) {
          final seq = (m['seq'] as int) - 1;
          if (seq < 0 || seq > 4) continue;
          _bodyCtrl[seq].text = m['body'] ?? '';
          _sendAt[seq] = DateTime.parse(m['send_at']).toLocal();
        }
      } else {
        // Pre-fill slots with templates in order
        for (int i = 0; i < templates.length && i < 5; i++) {
          _bodyCtrl[i].text = templates[i]['body'] ?? '';
          _selectedTemplateIds[i] = templates[i]['id'] as String;
        }
      }
    } catch (_) {}

    setState(() => _loadingData = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _linkCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _bodyCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDateTime(int index) async {
    final current = _sendAt[index];
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // Validate against previous non-null message
    int prevIndex = -1;
    for (int i = index - 1; i >= 0; i--) {
      if (_sendAt[i] != null) {
        prevIndex = i;
        break;
      }
    }
    if (prevIndex != -1 && !picked.isAfter(_sendAt[prevIndex]!)) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.schedule, color: Colors.orange, size: 40),
          title: const Text('Horário inválido'),
          content: Text(
            'A mensagem ${index + 1} deve ser enviada depois da mensagem ${prevIndex + 1}.\n\n'
            'Mensagem ${prevIndex + 1} está agendada para:\n'
            '${DateFormat('dd/MM/yyyy HH:mm').format(_sendAt[prevIndex]!)}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Validate against next non-null message
    int nextIndex = -1;
    for (int i = index + 1; i < 5; i++) {
      if (_sendAt[i] != null) {
        nextIndex = i;
        break;
      }
    }
    if (nextIndex != -1 && !picked.isBefore(_sendAt[nextIndex]!)) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.schedule, color: Colors.orange, size: 40),
          title: const Text('Horário inválido'),
          content: Text(
            'A mensagem ${index + 1} deve ser enviada antes da mensagem ${nextIndex + 1}.\n\n'
            'Mensagem ${nextIndex + 1} está agendada para:\n'
            '${DateFormat('dd/MM/yyyy HH:mm').format(_sendAt[nextIndex]!)}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _sendAt[index] = picked);
  }

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) {
      final phone = _phoneCtrl.text.trim();
      if (phone.isNotEmpty && !phone.startsWith('+55')) {
        final suggestion = phone.startsWith('+')
            ? '+55${phone.substring(1)}'
            : '+55$phone';
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 48,
            ),
            title: const Text('Número inválido'),
            content: Text(
              'O número "$phone" não tem o código do Brasil (+55).\n\n'
              'Você quis dizer:\n$suggestion',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _phoneCtrl.text = suggestion;
                  Navigator.pop(ctx);
                },
                child: const Text('Sim, corrigir automaticamente'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Editar manualmente'),
              ),
            ],
          ),
        );
      }
      return;
    }
    // Validate message order before saving
    DateTime? lastDate;
    int lastIndex = -1;
    for (int i = 0; i < 5; i++) {
      if (_sendAt[i] != null) {
        if (lastDate != null && !_sendAt[i]!.isAfter(lastDate)) {
          setState(() {
            _error = 'Mensagem ${i + 1} deve ser agendada depois da mensagem ${lastIndex + 1}.';
          });
          return;
        }
        lastDate = _sendAt[i];
        lastIndex = i;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      late String clientId;

      final clientData = {
        'name': _nameCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'property_link': _linkCtrl.text.trim().isEmpty
            ? null
            : _linkCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };

      if (_isEdit) {
        await ApiService.updateClient(widget.client['id'], clientData);
        clientId = widget.client['id'];
      } else {
        final created = await ApiService.createClient(clientData);
        clientId = created['id'];
      }

      final messages = <Map<String, dynamic>>[];
      for (int i = 0; i < 5; i++) {
        if (_sendAt[i] != null) {
          messages.add({
            'seq': i + 1,
            'body': _bodyCtrl[i].text,
            'send_at': _sendAt[i]!.toUtc().toIso8601String(),
          });
        }
      }

      await ApiService.upsertMessages(clientId, messages);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateBrazilianPhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obrigatório';

    final phone = value.trim();

    // Must start with +
    if (!phone.startsWith('+')) {
      return 'O número deve começar com + (ex: +5585999713444)';
    }

    // Must start with +55 (Brazil country code)
    if (!phone.startsWith('+55')) {
      return 'Número inválido. Use o código do Brasil: +55\n'
          'Exemplo: ${_suggestBrazilianNumber(phone)}';
    }

    // After +55, must have DDD (2 digits) + number (8 or 9 digits) = 10 or 11 digits
    final afterCountry = phone.substring(3); // remove +55
    if (!RegExp(r'^\d{10,11}$').hasMatch(afterCountry)) {
      return 'Formato inválido. Exemplo: +5585999713444\n'
          '(+55 + DDD de 2 dígitos + número)';
    }

    return null; // valid
  }

  String _suggestBrazilianNumber(String phone) {
    // Try to suggest the correct number by prepending +55
    // e.g. user typed +85999713444 → suggest +5585999713444
    if (phone.startsWith('+')) {
      return '+55${phone.substring(1)}';
    }
    return '+55$phone';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar Cliente' : 'Adicionar Cliente'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Informações do Cliente'),
                    const SizedBox(height: 16),
                    _field(_nameCtrl, 'Nome completo *', required: true),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp phone *',
                          hintText: '+5511999999999',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: _validateBrazilianPhone,
                      ),
                    ),
                    _field(_emailCtrl, 'Email', hint: 'client@email.com'),
                    _field(
                      _linkCtrl,
                      'Link da propriedade',
                      hint: 'https://...',
                    ),
                    _field(_notesCtrl, 'Observações', maxLines: 3),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const Divider(height: 48),
                    _sectionTitle('Mensagens de Follow-up'),
                    const SizedBox(height: 4),
                    Text(
                      'Placeholders: {name}  {property_link}  {email}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(5, _messageBlock),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (v) => (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null
            : null,
      ),
    );
  }

  Widget _messageBlock(int index) {
    final fmt = DateFormat('MMM d, yyyy  HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_templates.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: _dropdownKeys[index],
                initialValue: _selectedTemplateIds[index],
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Usar template',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.article_outlined, size: 18),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('— nenhum —'),
                  ),
                  ..._templates.map((t) => DropdownMenuItem<String>(
                        value: t['id'] as String,
                        child: Text(t['name'] as String),
                      )),
                  const DropdownMenuItem<String>(
                    value: '__ADD_TEMPLATE__',
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 16, color: Colors.blue),
                        SizedBox(width: 6),
                        Text(
                          'Adicionar template',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                ],
                onChanged: (id) async {
                  if (id == '__ADD_TEMPLATE__') {
                    _dropdownKeys[index].currentState?.reset();
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TemplatesScreen()),
                    );
                    if (!mounted) return;
                    final fresh = await ApiService.getTemplates();
                    setState(() => _templates = fresh);
                    return;
                  }
                  setState(() {
                    _selectedTemplateIds[index] = id;
                    if (id != null) {
                      final template = _templates.cast<Map<String, dynamic>>().firstWhere(
                        (t) => t['id'] == id,
                        orElse: () => {},
                      );
                      if (template.isNotEmpty) {
                        _bodyCtrl[index].text = template['body'] ?? '';
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Mensagem ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyCtrl[index],
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Corpo da mensagem...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: _sendAt[index] != null ? Colors.grey : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sendAt[index] != null ? fmt.format(_sendAt[index]!) : 'Não agendado',
                    style: TextStyle(
                      fontSize: 13,
                      color: _sendAt[index] != null ? null : Colors.grey,
                      fontStyle: _sendAt[index] != null ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
                if (_sendAt[index] != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    color: Colors.red,
                    tooltip: 'Remover',
                    onPressed: () => setState(() => _sendAt[index] = null),
                  ),
                TextButton(
                  onPressed: () => _pickDateTime(index),
                  child: Text(_sendAt[index] != null ? 'Alterar' : 'Agendar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
