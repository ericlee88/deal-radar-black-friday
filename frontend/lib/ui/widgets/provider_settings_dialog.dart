import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deal_models.dart';
import '../../providers/deal_providers.dart';

class ProviderSettingsDialog extends ConsumerStatefulWidget {
  final ProviderSettings settings;

  const ProviderSettingsDialog({
    super.key,
    required this.settings,
  });

  @override
  ConsumerState<ProviderSettingsDialog> createState() => _ProviderSettingsDialogState();
}

class _ProviderSettingsDialogState extends ConsumerState<ProviderSettingsDialog> {
  late String _llmProvider;
  late String _priceProvider;
  late String _webhookProvider;
  late TextEditingController _geminiKeyCtrl;
  late TextEditingController _geminiModelCtrl;
  late TextEditingController _openaiKeyCtrl;
  late TextEditingController _openaiModelCtrl;
  late TextEditingController _keepaKeyCtrl;
  late TextEditingController _webhookUrlCtrl;
  late TextEditingController _telegramTokenCtrl;
  late TextEditingController _telegramChatCtrl;
  late TextEditingController _pollIntervalCtrl;
  bool _saving = false;
  String? _statusBanner;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _llmProvider = s.llmProvider;
    _priceProvider = s.priceProvider;
    _webhookProvider = s.webhookProvider;
    _geminiKeyCtrl = TextEditingController();
    _geminiModelCtrl = TextEditingController(text: s.geminiModel);
    _openaiKeyCtrl = TextEditingController();
    _openaiModelCtrl = TextEditingController(text: s.openaiModel);
    _keepaKeyCtrl = TextEditingController();
    _webhookUrlCtrl = TextEditingController(text: s.webhookUrl ?? '');
    _telegramTokenCtrl = TextEditingController();
    _telegramChatCtrl = TextEditingController(text: s.telegramChatId ?? '');
    _pollIntervalCtrl = TextEditingController(text: s.pollIntervalMinutes.toString());
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    _geminiModelCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _openaiModelCtrl.dispose();
    _keepaKeyCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _telegramTokenCtrl.dispose();
    _telegramChatCtrl.dispose();
    _pollIntervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
      _statusBanner = null;
    });

    final patch = <String, dynamic>{
      'llm_provider': _llmProvider,
      'gemini_model': _geminiModelCtrl.text.trim(),
      'openai_model': _openaiModelCtrl.text.trim(),
      'price_provider': _priceProvider,
      'webhook_provider': _webhookProvider,
      'webhook_url': _webhookUrlCtrl.text.trim(),
      'telegram_chat_id': _telegramChatCtrl.text.trim(),
      'poll_interval_minutes': int.tryParse(_pollIntervalCtrl.text.trim()) ?? 30,
    };

    if (_geminiKeyCtrl.text.trim().isNotEmpty) {
      patch['gemini_api_key'] = _geminiKeyCtrl.text.trim();
    }
    if (_openaiKeyCtrl.text.trim().isNotEmpty) {
      patch['openai_api_key'] = _openaiKeyCtrl.text.trim();
    }
    if (_keepaKeyCtrl.text.trim().isNotEmpty) {
      patch['keepa_api_key'] = _keepaKeyCtrl.text.trim();
    }
    if (_telegramTokenCtrl.text.trim().isNotEmpty) {
      patch['telegram_bot_token'] = _telegramTokenCtrl.text.trim();
    }

    try {
      await ref.read(dealDashboardProvider.notifier).updateProviderSettings(patch);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusBanner = 'Settings saved and active across Deal Radar backend!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusBanner = 'Error saving settings: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings =
        ref.watch(dealDashboardProvider).valueOrNull?.providerSettings ?? widget.settings;

    return Dialog(
      backgroundColor: const Color(0xFF111621),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Live Price Poller, LLM & Webhook Provider Settings',
                            style: TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Active LLM: ${currentSettings.activeLlmMode.toUpperCase()} | '
                            'Active Price Feed: ${currentSettings.activePriceMode.toUpperCase()} | '
                            'Webhook: ${currentSettings.webhookProvider.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF4ADE80),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 22),

              if (_statusBanner != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _statusBanner!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4ADE80)),
                  ),
                ),

              Expanded(
                child: ListView(
                  children: [
                    // 1. LLM Intent Translation Provider
                    _sectionHeader(
                      Icons.auto_awesome_rounded,
                      '1. LLM Intent-to-DAG Resolver (Gemini / OpenAI / Deterministic Fallback)',
                      const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _dropdownField(
                            label: 'LLM Provider Mode',
                            value: _llmProvider,
                            items: const ['auto', 'gemini', 'openai', 'mock'],
                            onChanged: (v) => setState(() => _llmProvider = v ?? 'auto'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _textField(
                            controller: _geminiModelCtrl,
                            label: 'Gemini Model',
                            hint: 'gemini-2.5-flash',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _textField(
                            controller: _geminiKeyCtrl,
                            label: 'Gemini API Key (${currentSettings.geminiApiKeyPreview})',
                            hint: 'Enter AIza... key to override',
                            obscure: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _textField(
                            controller: _openaiKeyCtrl,
                            label: 'OpenAI API Key (${currentSettings.openaiApiKeyPreview})',
                            hint: 'Enter sk-... key to override',
                            obscure: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 2. Keepa Live Price Poller
                    _sectionHeader(
                      Icons.trending_down_rounded,
                      '2. Amazon Price & 90-Day History Poller (Keepa API / Simulation Engine)',
                      const Color(0xFFF59E0B),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _dropdownField(
                            label: 'Price Feed Mode',
                            value: _priceProvider,
                            items: const ['auto', 'keepa', 'mock'],
                            onChanged: (v) => setState(() => _priceProvider = v ?? 'auto'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _textField(
                            controller: _keepaKeyCtrl,
                            label: 'Keepa API Key (${currentSettings.keepaApiKeyPreview})',
                            hint: 'Enter Keepa API key for live ASIN polling',
                            obscure: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 130,
                          child: _textField(
                            controller: _pollIntervalCtrl,
                            label: 'Poll Interval (min)',
                            hint: '30',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 3. Webhook & Push Notification Channel
                    _sectionHeader(
                      Icons.notifications_active_rounded,
                      '3. Strike-Price Webhook & Push Alerts (ntfy.sh / Discord / Slack / Telegram)',
                      const Color(0xFFEC4899),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 180,
                          child: _dropdownField(
                            label: 'Alert Channel',
                            value: _webhookProvider,
                            items: const ['none', 'ntfy', 'discord', 'slack', 'telegram', 'generic'],
                            onChanged: (v) => setState(() => _webhookProvider = v ?? 'none'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _textField(
                            controller: _webhookUrlCtrl,
                            label: 'Webhook URL (Discord / Slack / ntfy.sh topic URL)',
                            hint: 'https://ntfy.sh/my-black-friday-radar',
                          ),
                        ),
                      ],
                    ),
                    if (_webhookProvider == 'telegram') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: _telegramTokenCtrl,
                              label: 'Telegram Bot Token',
                              hint: '123456:ABC-DEF...',
                              obscure: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _textField(
                              controller: _telegramChatCtrl,
                              label: 'Telegram Chat ID',
                              hint: '-100123456789',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 22),

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(dealDashboardProvider.notifier)
                              .runPoller(simulateDrop: false);
                          if (!mounted) return;
                          setState(() {
                            _statusBanner = 'Executed price poll cycle across all active ASINs.';
                          });
                        },
                        icon: const Icon(Icons.sync_rounded, size: 15),
                        label: const Text('Run Poll Cycle Now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref.read(dealDashboardProvider.notifier).sendTestAlert(
                                customMessage: 'Test Strike Alert from Provider Settings UI',
                              );
                          if (!mounted) return;
                          setState(() {
                            _statusBanner = 'Dispatched test strike alert to active webhook log!';
                          });
                        },
                        icon: const Icon(Icons.send_rounded, size: 15),
                        label: const Text('Send Test Alert'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveSettings,
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text(_saving ? 'Saving...' : 'Save Provider Settings'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161C28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF161C28),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase())))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Colors.white30),
            filled: true,
            fillColor: const Color(0xFF161C28),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12),
            ),
          ),
        ),
      ],
    );
  }
}
