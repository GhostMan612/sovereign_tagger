// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';

class CyberNavItem {
  final IconData icon;
  final String label;

  const CyberNavItem(this.icon, this.label);
}

class CyberNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final Color accent;
  final List<CyberNavItem> items;

  const CyberNavBar({super.key, required this.index, required this.onTap, required this.accent, required this.items});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.35))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutBack,
                    left: index * itemWidth + 6,
                    width: itemWidth - 12,
                    top: 6,
                    height: 50,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: accent.withValues(alpha: 0.12),
                          border: Border.all(color: accent.withValues(alpha: 0.55)),
                          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 14)],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(child: _NavButton(item: items[i], selected: i == index, accent: accent, onTap: () => onTap(i))),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final CyberNavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.selected, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : Colors.white38;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.18 : 1.0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              child: Icon(item.icon, color: color, size: 22),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontFamily: 'ShareTechMono',
                fontSize: selected ? 11 : 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: color,
                letterSpacing: 0.5,
              ),
              child: Text(item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ],
        ),
      ),
    );
  }
}
