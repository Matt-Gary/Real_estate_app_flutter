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
  final _notesCtrl = TextEditingController();

  late List<TextEditingController> _bodyCtrl;
  late List<DateTime?> _sendAt;

  List<dynamic> _templates = [];
  List<String?> _selectedTemplateIds = List.generate(5, (_) => null);
  final List<GlobalKey<FormFieldState<String?>>> _dropdownKeys = List.generate(
    5,
    (_) => GlobalKey<FormFieldState<String?>>(),
  );

  List<dynamic> _propertyLinks = [];
  // Positions 1-5; index 0 = position 1
  final List<String?> _selectedLinkIds = List.filled(5, null);

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
      _notesCtrl.text = c['notes'] ?? '';
      // Pre-fill assigned property links sorted by position
      final links = (c['client_property_links'] as List<dynamic>? ?? [])
        ..sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int),
        );
      for (final link in links) {
        final pos = (link['position'] as int) - 1; // convert to 0-based index
        if (pos >= 0 && pos < 5) {
          _selectedLinkIds[pos] = link['property_link_id'] as String?;
        }
      }
    }

    try {
      // Always load agent templates and property links for the dropdowns
      final results = await Future.wait([
        ApiService.getTemplates(),
        ApiService.getPropertyLinks(),
      ]);
      final templates = results[0];
      _templates = templates;
      _propertyLinks = results[1];

      if (_isEdit) {
        final msgs = await ApiService.getMessages(widget.client['id']);
        for (final m in msgs) {
          final seq = (m['seq'] as int) - 1;
          if (seq < 0 || seq > 4) continue;
          _bodyCtrl[seq].text = m['body'] ?? '';
          final rawSendAt = m['send_at'] as String?;
          final parsed = rawSendAt == null ? null : DateTime.tryParse(rawSendAt);
          _sendAt[seq] = (parsed ?? DateTime.now()).toLocal();
        }
      } else {
        // Pre-fill slots with templates in order
        for (int i = 0; i < templates.length && i < 5; i++) {
          _bodyCtrl[i].text = templates[i]['body'] ?? '';
          _selectedTemplateIds[i] = templates[i]['id'] as String;
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loadingData = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
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

    // Validate that selected time is not in the past
    if (picked.isBefore(DateTime.now())) {
      if (!mounted) return;
      await _showScheduleError(
        'Horário inválido',
        'O horário selecionado já passou. Escolha um horário futuro.',
      );
      return;
    }

    // Anti-ban: enforce 08:00–20:00 send window (Meta/WhatsApp policy).
    // Backend re-validates in APP_TZ; frontend uses browser-local as a preview.
    if (picked.hour < 8 || picked.hour >= 20) {
      if (!mounted) return;
      await _showScheduleError(
        'Fora do horário permitido',
        'Por política do WhatsApp/Meta, mensagens só podem ser agendadas '
            'entre 08:00 e 20:00.',
      );
      return;
    }

    // Anti-ban: enforce 48-hour minimum gap between messages to the same client.
    const minGap = Duration(hours: 48);
    for (int i = 0; i < 5; i++) {
      if (i == index || _sendAt[i] == null) continue;
      final diff = picked.difference(_sendAt[i]!).abs();
      if (diff < minGap) {
        if (!mounted) return;
        await _showScheduleError(
          'Intervalo muito curto',
          'Mensagens ao mesmo cliente precisam ter pelo menos 48 horas de '
              'intervalo.\n\n'
              'Mensagem ${i + 1} está agendada para:\n'
              '${DateFormat('dd/MM/yyyy HH:mm').format(_sendAt[i]!)}',
        );
        return;
      }
    }

    setState(() => _sendAt[index] = picked);
  }

  Future<void> _showScheduleError(String title, String body) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.schedule, color: Colors.orange, size: 40),
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Translate backend 422 validation error codes to Portuguese UI text.
  String _translateBackendError(String raw) {
    if (raw.contains('OUTSIDE_SEND_WINDOW')) {
      return 'Uma das mensagens está fora do horário permitido (08:00–20:00).';
    }
    if (raw.contains('MIN_GAP_VIOLATION')) {
      return 'Mensagens ao mesmo cliente precisam ter pelo menos 48 horas de intervalo.';
    }
    if (raw.contains('DAILY_LIMIT_EXCEEDED')) {
      return 'Limite diário de 100 mensagens por agente seria excedido. '
          'Redistribua mensagens para outros dias.';
    }
    return raw;
  }

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Anti-ban safety net: enforce window + 48h gap again before submitting
    // (picker already enforces these per-message, but a re-check catches any
    // state mutations that bypassed the picker).
    const minGap = Duration(hours: 48);
    for (int i = 0; i < 5; i++) {
      if (_sendAt[i] == null) continue;
      final t = _sendAt[i]!;
      if (t.hour < 8 || t.hour >= 20) {
        setState(() => _error =
            'Mensagem ${i + 1} está fora do horário permitido (08:00–20:00).');
        return;
      }
      for (int j = i + 1; j < 5; j++) {
        if (_sendAt[j] == null) continue;
        if (_sendAt[j]!.difference(t).abs() < minGap) {
          setState(() => _error =
              'Mensagens ${i + 1} e ${j + 1} precisam ter pelo menos 48 horas de intervalo.');
          return;
        }
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      late String clientId;

      // Build property_links array from non-null slots
      final propertyLinksData = <Map<String, dynamic>>[];
      for (int i = 0; i < 5; i++) {
        if (_selectedLinkIds[i] != null) {
          propertyLinksData.add({
            'property_link_id': _selectedLinkIds[i],
            'position': i + 1,
          });
        }
      }

      final clientData = {
        'name': _nameCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'property_links': propertyLinksData,
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
          if (_bodyCtrl[i].text.trim().isEmpty) {
            setState(
              () =>
                  _error = 'Mensagem ${i + 1} está agendada mas sem conteúdo.',
            );
            return;
          }
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
      final raw = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = _translateBackendError(raw));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obrigatório';

    final phone = value.trim();

    if (!phone.startsWith('+')) {
      return 'O número deve começar com + e o código do país (ex: +44, +55, +1)';
    }

    // E.164: + followed by 7–15 digits
    if (!RegExp(r'^\+\d{7,15}$').hasMatch(phone)) {
      return 'Formato inválido. Use + código do país + número (ex: +447911123456)';
    }

    return null;
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
                          hintText: '+55999785487',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: _validatePhone,
                      ),
                    ),
                    _field(_emailCtrl, 'Email', hint: 'client@email.com'),
                    ..._buildLinkSlots(),
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
                      'Placeholders: {name}  {email}  {link_1}  {link_2}  {link_3}',
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

  /// Returns the visible link slot dropdowns.
  /// Always shows all filled slots + one empty slot (up to 5).
  List<Widget> _buildLinkSlots() {
    // Determine how many slots to show: last filled index + 1 empty, min 1
    int lastFilled = -1;
    for (int i = 0; i < 5; i++) {
      if (_selectedLinkIds[i] != null) lastFilled = i;
    }
    final visibleCount = (lastFilled + 2).clamp(1, 5);

    return List.generate(visibleCount, (i) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String?>(
          initialValue: _selectedLinkIds[i],
          decoration: InputDecoration(
            labelText: 'Imóvel ${i + 1}',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.home_work_outlined, size: 18),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('— nenhum —'),
            ),
            ..._propertyLinks.map(
              (pl) => DropdownMenuItem<String?>(
                value: pl['id'] as String,
                child: Text(pl['description'] as String),
              ),
            ),
          ],
          onChanged: (id) => setState(() {
            _selectedLinkIds[i] = id;
            // Clear downstream slots when a slot is cleared
            if (id == null) {
              for (int j = i + 1; j < 5; j++) {
                _selectedLinkIds[j] = null;
              }
            }
          }),
        ),
      );
    });
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
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('— nenhum —'),
                  ),
                  ..._templates.map(
                    (t) => DropdownMenuItem<String>(
                      value: t['id'] as String,
                      child: Text(t['name'] as String),
                    ),
                  ),
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
                      MaterialPageRoute(
                        builder: (_) => const TemplatesScreen(),
                      ),
                    );
                    if (!mounted) return;
                    final fresh = await ApiService.getTemplates();
                    if (!mounted) return;
                    setState(() => _templates = fresh);
                    return;
                  }
                  setState(() {
                    _selectedTemplateIds[index] = id;
                    if (id != null) {
                      final template = _templates
                          .cast<Map<String, dynamic>>()
                          .firstWhere((t) => t['id'] == id, orElse: () => {});
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
                  color: _sendAt[index] != null
                      ? Colors.grey
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sendAt[index] != null
                        ? fmt.format(_sendAt[index]!)
                        : 'Não agendado',
                    style: TextStyle(
                      fontSize: 13,
                      color: _sendAt[index] != null ? null : Colors.grey,
                      fontStyle: _sendAt[index] != null
                          ? FontStyle.normal
                          : FontStyle.italic,
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
