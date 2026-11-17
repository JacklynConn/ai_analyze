import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null)
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title!.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          if (title != null) const SizedBox(height: 12),
          child,
        ],
      ),
    );

    // Material (not a DecoratedBox/Container): children such as
    // SwitchListTile / ListTile must paint their background and ink
    // splashes on the nearest Material ancestor — a DecoratedBox in
    // between triggers Flutter's "ListTile background color or ink
    // splashes may be invisible" assertion and hides the ink effects.
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: .18) : color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: filled ? .65 : .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10 : 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.icon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: AppColors.muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.text,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class LiveDot extends StatefulWidget {
  const LiveDot({super.key, required this.active, this.color = const Color(0xFF16C784)});

  final bool active;
  final Color color;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.active ? widget.color : AppColors.muted;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: c.withValues(alpha: .18 + .32 * _controller.value), blurRadius: 8, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 42, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
