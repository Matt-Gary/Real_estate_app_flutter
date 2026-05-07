import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/batch_plan_table.dart';

/// 4-step wizard for launching a label-targeted campaign:
///   1. Audience  — pick label, see eligible client count
///   2. Message   — template body editor with mandatory {name} placeholder
///   3. Schedule  — start date/time + per-day quota slider
///   4. Review    — day-by-day batch plan, then Launch
class CampaignFormScreen extends StatefulWidget {
  const CampaignFormScreen({super.key});

  @override
  State<CampaignFormScreen> createState() => _CampaignFormScreenState();
}

class _CampaignFormScreenState extends State<CampaignFormScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  // Step 1
  List<dynamic> _labels = [];
  String? _labelId;
  bool _loadingLabels = true;

  // Step 2
  final _nameCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  // Step 3
  DateTime _startAt = _defaultStart();
  int _dailyQuota = 60;
  int _agentLimit = 200;

  // Step 4
  Map<String, dynamic>? _preview; // result of /preview after creation
  String? _draftId;

  static DateTime _defaultStart() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);
  }

  @override
  void initState() {
    super.initState();
    _loadLabels();
    _loadAgentLimit();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLabels() async {
    try {
      final data = await ApiService.getLabels();
      if (mounted) {
        setState(() {
          _labels = data;
          _loadingLabels = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLabels = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _loadAgentLimit() async {
    try {
      final stats = await ApiService.getDashboardStats();
      final limit = (stats['dailyQuota']?['limit'] as int?) ?? 200;
      if (mounted) {
        setState(() {
          _agentLimit = limit;
          if (_dailyQuota > limit) _dailyQuota = limit;
        });
      }
    } catch (_) {
      /* dashboard not critical for form */
    }
  }

  bool _bodyHasName() => _bodyCtrl.text.contains('{name}');

  /// Inserts [token] at the current caret in the message field. If the field
  /// has never been focused (selection.start = -1) we append at the end.
  void _insertPlaceholder(String token) {
    final value = _bodyCtrl.value;
    final sel = value.selection;
    final start = sel.start >= 0 ? sel.start : value.text.length;
    final end = sel.end >= 0 ? sel.end : value.text.length;
    final newText = value.text.replaceRange(start, end, token);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {}); // refresh the {name}-required validator
  }

  // Local validation per step. Returns null on pass, else an error to show.
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_labelId == null) return 'Selecione uma etiqueta';
        return null;
      case 1:
        if (_nameCtrl.text.trim().isEmpty) return 'Dê um nome para a campanha';
        if (_bodyCtrl.text.trim().isEmpty) return 'Escreva a mensagem';
        if (!_bodyHasName()) {
          return 'A mensagem precisa conter {name} para personalização (regra anti-banimento).';
        }
        return null;
      case 2:
        final h = _startAt.hour;
        if (h < 8 || h >= 20)
          return 'O horário de início deve estar entre 08:00 e 20:00.';
        if (_startAt.isBefore(DateTime.now()))
          return 'O início não pode estar no passado.';
        if (_dailyQuota < 1 || _dailyQuota > _agentLimit) {
          return 'Quota diária inválida (1–$_agentLimit).';
        }
        return null;
    }
    return null;
  }

  // Move from step N → N+1. On step 2 → 3 we create a draft + run /preview.
  Future<void> _advance() async {
    final err = _validateStep(_step);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });

    try {
      if (_step == 2) {
        // Materialize the draft so /preview can run against the real row.
        // If we already created one (agent stepped back and forward), update it.
        if (_draftId == null) {
          final draft = await ApiService.createCampaign(
            name: _nameCtrl.text.trim(),
            labelId: _labelId!,
            templateBody: _bodyCtrl.text,
            dailyQuota: _dailyQuota,
            startAt: _startAt.toUtc().toIso8601String(),
          );
          _draftId = draft['id'] as String;
        } else {
          await ApiService.updateCampaign(
            _draftId!,
            name: _nameCtrl.text.trim(),
            labelId: _labelId,
            templateBody: _bodyCtrl.text,
            dailyQuota: _dailyQuota,
            startAt: _startAt.toUtc().toIso8601String(),
          );
        }
        _preview = await ApiService.previewCampaign(_draftId!);
      }
      if (mounted) {
        setState(() {
          _step++;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _launch() async {
    if (_draftId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.launchCampaign(_draftId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Campanha lançada — envios começarão no horário agendado.',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _cancelDraft() async {
    if (_draftId != null) {
      try {
        await ApiService.deleteCampaign(_draftId!);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova campanha'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelDraft,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepperHeader(step: _step),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: switch (_step) {
                  0 => _buildAudience(),
                  1 => _buildMessage(),
                  2 => _buildSchedule(),
                  _ => _buildReview(),
                },
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _step--;
                              _error = null;
                            }),
                      child: const Text('Voltar'),
                    ),
                  const Spacer(),
                  if (_step < 3)
                    FilledButton.icon(
                      onPressed: _busy ? null : _advance,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(_step == 2 ? 'Revisar' : 'Avançar'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy ? null : _launch,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Lançar campanha'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Audience ──
  Widget _buildAudience() {
    if (_loadingLabels) return const Center(child: CircularProgressIndicator());
    if (_labels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Nenhuma etiqueta criada ainda.\nVá em Clientes → Editar e adicione etiquetas antes de criar uma campanha.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. Para quem enviar?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Escolha a etiqueta que define o público desta campanha.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        ..._labels.map(
          (l) => RadioListTile<String>(
            value: l['id'] as String,
            groupValue: _labelId,
            onChanged: (v) => setState(() => _labelId = v),
            title: Text(l['name'] as String),
            subtitle: Text('${l['client_count'] ?? 0} cliente(s)'),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Message ──
  Widget _buildMessage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '2. O que enviar?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nome da campanha',
            hintText: 'Ex: Lançamento abril 2026 — terrenos',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bodyCtrl,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Mensagem',
            hintText: 'Olá {name}, novidade do mercado: ...',
            border: const OutlineInputBorder(),
            errorText: _bodyCtrl.text.isNotEmpty && !_bodyHasName()
                ? 'A mensagem precisa conter {name} para personalização.'
                : null,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Toque para inserir um placeholder:',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final token in const [
              '{name}',
              '{email}',
              '{link_1}',
              '{link_2}',
              '{link_3}',
            ])
              ActionChip(
                label: Text(
                  token,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                avatar: const Icon(Icons.add, size: 16),
                onPressed: () => _insertPlaceholder(token),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade700, width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: Colors.amber.shade900,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personalização obrigatória',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mensagens idênticas em massa são o principal fator de banimento do WhatsApp. O placeholder {name} é obrigatório.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.brown.shade900,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 3: Schedule ──
  Widget _buildSchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '3. Quando começar e em que ritmo?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Início'),
            subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(_startAt)),
            trailing: TextButton(
              onPressed: _pickStart,
              child: const Text('Alterar'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Quota diária da campanha: $_dailyQuota envios/dia',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Slider(
          value: _dailyQuota.toDouble(),
          min: 1,
          max: _agentLimit.toDouble(),
          divisions: _agentLimit > 0 ? _agentLimit - 1 : 1,
          label: '$_dailyQuota',
          onChanged: (v) => setState(() => _dailyQuota = v.round()),
        ),
        Text(
          'Cap diário do agente: $_agentLimit. Outras mensagens (follow-up, frias) também usam essa cota.',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade300, width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade800, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'O sistema distribui os envios automaticamente entre 08:00 e 20:00 (São Paulo) com intervalo aleatório de 5–30s entre cada mensagem.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade900,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
    );
    if (t == null || !mounted) return;
    setState(
      () => _startAt = DateTime(d.year, d.month, d.day, t.hour, t.minute),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      '• $text',
      style: TextStyle(fontSize: 13, color: Colors.green.shade900, height: 1.3),
    ),
  );

  // ── Step 4: Review ──
  Widget _buildReview() {
    final p = _preview;
    if (p == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final batchPlan = p['batchPlan'] as List<dynamic>? ?? [];
    final total = batchPlan.fold<int>(
      0,
      (acc, d) => acc + ((d['count'] as int?) ?? 0),
    );
    final eligible = p['eligibleClients'] as int? ?? 0;
    final matched = p['matchedClients'] as int? ?? 0;
    final skipped = p['skipped'] as Map<String, dynamic>? ?? {};
    final unscheduled = p['unscheduledCount'] as int? ?? 0;

    final firstDay = batchPlan.isNotEmpty
        ? (batchPlan.first['date'] as String?)
        : null;
    final lastDay = batchPlan.isNotEmpty
        ? (batchPlan.last['date'] as String?)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '4. Revisar e lançar',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade700, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.green.shade900,
                ),
              ),
              const SizedBox(height: 10),
              _bullet(
                '$total mensagens serão enviadas para $eligible cliente(s).',
              ),
              if (matched > eligible)
                _bullet(
                  '${matched - eligible} cliente(s) com a etiqueta foram excluídos pelos filtros (ver detalhes abaixo).',
                ),
              if (firstDay != null && lastDay != null)
                _bullet(
                  'Período: $firstDay → $lastDay (${batchPlan.length} dia${batchPlan.length == 1 ? '' : 's'}).',
                ),
              _bullet(
                '$_dailyQuota envios/dia, entre 08:00 e 20:00 São Paulo.',
              ),
              if (unscheduled > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⚠ $unscheduled cliente(s) não couberam no plano (limite anual). Considere aumentar a quota ou dividir em campanhas.',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if ((skipped['optedOut'] ?? 0) > 0) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade500),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${skipped['optedOut']} cliente(s) pediram para parar (opt-out) e foram excluídos:',
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (skipped['optedOutClients'] as List<dynamic>? ?? [])
                      .map((c) => (c as Map)['name'] as String? ?? '')
                      .join(', '),
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
        if ((skipped['sameDayFollowUp'] ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade400),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${skipped['sameDayFollowUp']} cliente(s) pulado(s) por já terem mensagem agendada no mesmo dia:',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (skipped['sameDayFollowUpClients'] as List<dynamic>? ?? [])
                      .map((c) => (c as Map)['name'] as String? ?? '')
                      .join(', '),
                  style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Plano por dia',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        BatchPlanTable(batchPlan: batchPlan),
        const SizedBox(height: 16),
        if (p['sampleMessage'] != null) ...[
          const Text(
            'Exemplo de mensagem (com dados do primeiro cliente):',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade700, width: 1.5),
            ),
            child: Text(
              p['sampleMessage'] as String,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Colors.green.shade900,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepperHeader extends StatelessWidget {
  final int step;
  const _StepperHeader({required this.step});

  static const _labels = ['Público', 'Mensagem', 'Agenda', 'Revisar'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final active = i == step;
          final done = i < step;
          final color = done
              ? Colors.green
              : active
              ? Theme.of(context).colorScheme.primary
              : Colors.grey;
          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  radius: 14,
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      color: color,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (i < _labels.length - 1)
                  Container(
                    width: 12,
                    height: 2,
                    color: done ? Colors.green : Colors.grey.shade300,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
