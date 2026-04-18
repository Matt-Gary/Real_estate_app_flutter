import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  bool _waConnecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await ApiService.getDashboardStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    try {
      final res = await ApiService.sendNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent ${res['sent']} message(s)')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onConnectWhatsApp() async {
    if (_waConnecting) return;
    setState(() => _waConnecting = true);
    try {
      await ApiService.whatsappConnect();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => _QrCodeDialog(
          onConnected: () {
            Navigator.of(ctx).pop();
            _load();
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao conectar: $e')));
      }
    } finally {
      if (mounted) setState(() => _waConnecting = false);
    }
  }

  Future<void> _onDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar WhatsApp?'),
        content: const Text('O número será desvinculado desta conta.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.whatsappDisconnect();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Atualizar'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_stats != null)
            _buildStats(),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final s = _stats!;
    final waState =
        (s['waStatus']?['instance']?['state'] ??
                s['waStatus']?['state'] ??
                'unknown')
            as String;

    final statCards = [
      _StatData('Total de Clientes', s['total'], const Color(0xFF7F77DD)),
      _StatData('Ativos', s['active'], Colors.green),
      _StatData('Respondidos', s['replied'], Colors.grey),
      _StatData('Enviados', s['sent'], const Color(0xFF3B8BD4)),
      _StatData('Pendentes', s['pending'], Colors.orange),
      _StatData('Falhas', s['failed'], Colors.red),
    ];

    final queuePaused = s['queuePaused'] == true;
    final queueReason = s['queuePausedReason'] as String?;
    final alerts = (s['alerts'] as List?) ?? const [];
    final quota = (s['dailyQuota'] as Map?) ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (queuePaused) _buildQueuePausedBanner(queueReason),
        if (alerts.isNotEmpty) _buildAlertsBanner(alerts),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ...statCards.map((d) => _StatCard(data: d)),
            _QuotaCard(
              used: (quota['used'] as num?)?.toInt() ?? 0,
              limit: (quota['limit'] as num?)?.toInt() ?? 100,
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildWhatsAppSection(waState),
        const SizedBox(height: 8),
        const Text(
          'Agendador: rodando — dispara automaticamente quando as mensagens estão prontas.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildQueuePausedBanner(String? reason) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_filled, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fila pausada automaticamente',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                if (reason != null && reason.isNotEmpty)
                  Text(
                    'Motivo: $reason. Resolva o problema (ex: reconectar WhatsApp) e retome.',
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ApiService.resumeQueue();
                if (mounted) await _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retomar fila'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsBanner(List alerts) {
    return Column(
      children: [
        for (final a in alerts) _buildSingleAlert(a as Map),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSingleAlert(Map a) {
    final severity = a['severity'] as String? ?? 'warning';
    final isCritical = severity == 'critical';
    final bg = isCritical ? Colors.red.shade50 : Colors.orange.shade50;
    final fg = isCritical ? Colors.red : Colors.orange.shade900;
    final border = isCritical ? Colors.red.shade300 : Colors.orange.shade300;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              a['message'] as String? ?? '',
              style: TextStyle(color: fg),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: fg,
            tooltip: 'Dispensar',
            onPressed: () async {
              try {
                await ApiService.dismissAlert(a['id'] as String);
                if (mounted) await _load();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppSection(String waState) {
    if (waState == 'open') {
      return Row(
        children: [
          const Text(
            'WhatsApp: ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Icon(Icons.circle, size: 12, color: Colors.green),
          const SizedBox(width: 6),
          const Text('Conectado', style: TextStyle(color: Colors.green)),
          const SizedBox(width: 16),
          TextButton(
            onPressed: _onDisconnect,
            child: const Text('Desconectar'),
          ),
        ],
      );
    }

    if (waState == 'connecting' || _waConnecting) {
      return const Row(
        children: [
          Text('WhatsApp: ', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Conectando...', style: TextStyle(color: Colors.orange)),
        ],
      );
    }

    // not_configured, close, unknown, error
    return Row(
      children: [
        const Text('WhatsApp: ', style: TextStyle(fontWeight: FontWeight.bold)),
        if (waState != 'not_configured') ...[
          const Icon(Icons.circle, size: 12, color: Colors.red),
          const SizedBox(width: 6),
          Text(waState, style: const TextStyle(color: Colors.red)),
          const SizedBox(width: 12),
        ],
        ElevatedButton.icon(
          onPressed: _waConnecting ? null : _onConnectWhatsApp,
          icon: const Icon(Icons.phone_android, size: 16),
          label: const Text('Conectar WhatsApp'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ── QR Code Dialog ────────────────────────────────────────────────────────────

class _QrCodeDialog extends StatefulWidget {
  final VoidCallback onConnected;
  const _QrCodeDialog({required this.onConnected});

  @override
  State<_QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<_QrCodeDialog> {
  Timer? _timer;
  Uint8List? _qrBytes;
  String _status = 'Gerando QR code...';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _poll(); // fetch immediately, then every 3s
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final data = await ApiService.getWhatsAppQrCode();
      if (!mounted) return;

      final state = data['state'] as String? ?? 'unknown';

      if (state == 'open') {
        _timer?.cancel();
        widget.onConnected();
        return;
      }

      // Evolution API returns QR as base64 string (may include data URI prefix)
      final raw = data['base64'] as String? ?? data['qrcode'] as String? ?? '';
      Uint8List? bytes;
      if (raw.isNotEmpty) {
        final stripped = raw.contains(',') ? raw.split(',').last : raw;
        bytes = base64Decode(stripped);
      }

      setState(() {
        _qrBytes = bytes;
        _status = 'Escaneie o QR code com seu WhatsApp';
        _error = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Erro ao obter QR code: $e';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conectar WhatsApp'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(color: _error ? Colors.red : null),
            ),
            const SizedBox(height: 16),
            if (_qrBytes != null)
              Image.memory(_qrBytes!, width: 240, height: 240)
            else if (!_error)
              const SizedBox(
                width: 240,
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 12),
            const Text(
              'Abra o WhatsApp → Dispositivos conectados → Conectar dispositivo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

// ── Stat card helpers ─────────────────────────────────────────────────────────

class _StatData {
  final String label;
  final dynamic value;
  final Color color;
  const _StatData(this.label, this.value, this.color);
}

class _QuotaCard extends StatelessWidget {
  final int used;
  final int limit;
  const _QuotaCard({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final pct = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final Color color;
    if (pct >= 0.95) {
      color = Colors.red;
    } else if (pct >= 0.80) {
      color = Colors.orange;
    } else {
      color = const Color(0xFF3B8BD4);
    }

    return Container(
      width: 140,
      height: 90,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$used / $limit',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Enviados hoje',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 90,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data.value}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: data.color,
            ),
          ),
          Text(
            data.label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
