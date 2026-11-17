import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../services/settings_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late AppSettings _draft;
  late final TextEditingController _gemini;
  late final TextEditingController _groq;
  late final TextEditingController _openRouter;
  late final TextEditingController _finnhub;
  late final TextEditingController _balance;
  late final TextEditingController _risk;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(settingsProvider);
    _gemini = TextEditingController(text: _draft.geminiKey);
    _groq = TextEditingController(text: _draft.groqKey);
    _openRouter = TextEditingController(text: _draft.openRouterKey);
    _finnhub = TextEditingController(text: _draft.finnhubKey);
    _balance = TextEditingController(text: _draft.balance.toStringAsFixed(0));
    _risk = TextEditingController(text: _draft.riskPercent.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _gemini.dispose();
    _groq.dispose();
    _openRouter.dispose();
    _finnhub.dispose();
    _balance.dispose();
    _risk.dispose();
    super.dispose();
  }

  void _patch(AppSettings next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final next = _draft.copyWith(
      geminiKey: _gemini.text.trim(),
      groqKey: _groq.text.trim(),
      openRouterKey: _openRouter.text.trim(),
      finnhubKey: _finnhub.text.trim(),
      balance: double.tryParse(_balance.text) ?? _draft.balance,
      riskPercent: double.tryParse(_risk.text) ?? _draft.riskPercent,
    );
    await ref.read(settingsProvider.notifier).update(next);
    if (!mounted) return;
    ref.read(dashboardProvider.notifier).applySettings(next);
    setState(() {
      _draft = next;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved — analysis engines reloaded')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = <AiBackend>{
      for (final b in AiBackend.values)
        if (_draft.hasKey(b)) b,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (_dirty)
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
                child: const Text('Save'),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ------------------------------------------------------------- feed
        SectionCard(
          title: 'Market data',
          subtitle: 'Demo mode needs no account and no network',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.demoMode,
                activeThumbColor: AppColors.gold,
                title: const Text('Demo feed (simulated ticks)', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Turn off for real gold prices (Yahoo Finance, or Finnhub websocket if a key is set)',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                onChanged: (v) => _patch(_draft.copyWith(demoMode: v)),
              ),
              const SizedBox(height: 6),
              _KeyField(
                controller: _finnhub,
                label: 'Finnhub API key (optional · real ticks)',
                hint: 'finnhub.io → free plan',
                url: 'https://finnhub.io/register',
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Text('Timeframe', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  const Spacer(),
                  ...<String>['1m', '5m', '15m', '30m', '1h'].map(
                    (tf) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => _patch(_draft.copyWith(interval: tf)),
                        child: Pill(
                          label: tf,
                          color: _draft.interval == tf ? AppColors.gold : AppColors.muted,
                          dense: true,
                          filled: _draft.interval == tf,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // --------------------------------------------------------------- AI
        SectionCard(
          title: 'AI models (free tiers)',
          subtitle: 'Every configured model votes; consensus drives the signal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _KeyField(
                controller: _gemini,
                label: 'Gemini API key',
                hint: 'aistudio.google.com/apikey',
                url: 'https://aistudio.google.com/apikey',
              ),
              const SizedBox(height: 10),
              _KeyField(
                controller: _groq,
                label: 'Groq API key',
                hint: 'console.groq.com/keys',
                url: 'https://console.groq.com/keys',
              ),
              const SizedBox(height: 10),
              _KeyField(
                controller: _openRouter,
                label: 'OpenRouter API key',
                hint: 'openrouter.ai/keys (":free" models)',
                url: 'https://openrouter.ai/keys',
              ),
              const Divider(height: 26),
              ...kAiModels.map((spec) {
                final backendOk = _draft.hasKey(spec.backend);
                final disabled = _draft.disabledModels.contains(spec.id);
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: !disabled && backendOk,
                  activeThumbColor: AppColors.gold,
                  title: Text(
                    spec.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: backendOk ? AppColors.text : AppColors.muted,
                    ),
                  ),
                  subtitle: Text(
                    backendOk ? '${spec.model} · ${spec.note}' : 'Add a ${spec.backend.name} key to enable · ${spec.note}',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.35),
                  ),
                  onChanged: !backendOk
                      ? null
                      : (v) {
                          final set = <String>{..._draft.disabledModels};
                          if (v) {
                            set.remove(spec.id);
                          } else {
                            set.add(spec.id);
                          }
                          _patch(_draft.copyWith(disabledModels: set));
                        },
                );
              }),
              const Divider(height: 26),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Minimum AI confidence to confirm',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    '${(_draft.minConfidence * 100).round()}%',
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ],
              ),
              Slider(
                value: _draft.minConfidence,
                min: 0.5,
                max: 0.9,
                divisions: 8,
                activeColor: AppColors.gold,
                label: '${(_draft.minConfidence * 100).round()}%',
                onChanged: (v) => _patch(_draft.copyWith(minConfidence: v)),
              ),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'News blackout window',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    '±${_draft.blackoutMinutes} min',
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ],
              ),
              Slider(
                value: _draft.blackoutMinutes.toDouble(),
                min: 0,
                max: 120,
                divisions: 8,
                activeColor: AppColors.gold,
                label: '±${_draft.blackoutMinutes}m',
                onChanged: (v) => _patch(_draft.copyWith(blackoutMinutes: v.round())),
              ),
              Text(
                'Active sources: ${enabled.isEmpty ? 'none' : enabled.map((e) => e.name).join(', ')} · '
                'Rules engine always on',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---------------------------------------------------------- alerts
        SectionCard(
          title: 'Alerts & risk',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.notificationsEnabled,
                activeThumbColor: AppColors.gold,
                title: const Text('Local notifications', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Fires on this device when a setup becomes confirmed, and 45 min before high-impact releases',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                onChanged: (v) => _patch(_draft.copyWith(notificationsEnabled: v)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref.read(notificationServiceProvider).showTest(),
                  icon: const Icon(Icons.notifications_active_rounded, size: 16),
                  label: const Text('Send test notification', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                ),
              ),
              const Divider(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _NumberField(controller: _balance, label: 'Account balance (USD)'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(controller: _risk, label: 'Risk per trade (%)'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Used only to show suggested lot size (XAUUSD: 1 lot = 100 oz).',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'About',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'XAUUSD AI Trader · v1.0.0\n'
                'Multi-model analysis (Gemini, Groq, OpenRouter free tiers + on-device rules) '
                'combined with classical technicals and a news-risk filter.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _link('Free model keys', 'https://openrouter.ai/models?max_price=0'),
                  _link('Gold news', 'https://www.kitco.com/news/'),
                  _link('Economic calendar', 'https://www.forexfactory.com/calendar'),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.sell.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.sell.withValues(alpha: .3)),
                ),
                child: const Text(
                  'RISK WARNING: this app produces analysis and alerts only. It does not place orders '
                  'and it is not financial advice. Trading XAUUSD with leverage can wipe out your account.',
                  style: TextStyle(color: AppColors.sell, fontSize: 10.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _link(String label, String url) => GestureDetector(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Pill(label: label, color: AppColors.gold, dense: true, icon: Icons.link_rounded),
      );
}

class _KeyField extends StatefulWidget {
  const _KeyField({required this.controller, required this.label, required this.hint, required this.url});

  final TextEditingController controller;
  final String label;
  final String hint;
  final String url;

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure && widget.controller.text.isNotEmpty,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(fontSize: 12, color: AppColors.muted),
        hintText: widget.hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.muted),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 16),
          color: AppColors.muted,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}
