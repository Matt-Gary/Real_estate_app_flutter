import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

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
  late List<DateTime> _sendAt;

  bool _loading = false;
  bool _loadingData = true;
  String? _error;

  bool get _isEdit => widget.client != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _bodyCtrl = List.generate(5, (_) => TextEditingController());
    _sendAt = List.generate(
      5,
      (i) => DateTime(now.year, now.month, now.day + i + 1, 10, 0),
    );
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
      if (_isEdit) {
        final msgs = await ApiService.getMessages(widget.client['id']);
        for (final m in msgs) {
          final seq = (m['seq'] as int) - 1;
          if (seq < 0 || seq > 4) continue;
          _bodyCtrl[seq].text = m['body'] ?? '';
          _sendAt[seq] = DateTime.parse(m['send_at']).toLocal();
        }
      } else {
        final templates = await ApiService.getTemplates();
        for (final t in templates) {
          final seq = (t['seq'] as int) - 1;
          if (seq < 0 || seq > 4) continue;
          _bodyCtrl[seq].text = t['body'] ?? '';
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

    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    setState(() {
      _sendAt[index] = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
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

      final messages = List.generate(
        5,
        (i) => {
          'seq': i + 1,
          'body': _bodyCtrl[i].text,
          'send_at': _sendAt[i].toUtc().toIso8601String(),
        },
      );

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
                    const SizedBox(height: 16),
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
                const Icon(Icons.schedule, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  fmt.format(_sendAt[index]),
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _pickDateTime(index),
                  child: const Text('Alterar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
