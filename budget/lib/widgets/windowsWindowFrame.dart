// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

bool isTilingWindowManager() {
  if (kIsWeb || !Platform.isLinux) return false;

  final env = Platform.environment;

  // Direct socket or instance detections
  if (env.containsKey('HYPRLAND_INSTANCE_SIGNATURE') ||
      env.containsKey('SWAYSOCK') ||
      env.containsKey('I3SOCK') ||
      env.containsKey('BSPWM_SOCKET') ||
      env.containsKey('RIVER_SOCKET')) {
    return true;
  }

  // Desktop environment or session string detections
  final desktop = (env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
  final session = (env['DESKTOP_SESSION'] ?? '').toLowerCase();
  final sessionDesktop = (env['XDG_SESSION_DESKTOP'] ?? '').toLowerCase();

  const tilingKeywords = [
    'hyprland',
    'i3',
    'sway',
    'bspwm',
    'dwm',
    'awesome',
    'qtile',
    'xmonad',
    'river',
    'niri',
    'leftwm',
    'herbstluftwm',
    'omarchy',
  ];

  for (final keyword in tilingKeywords) {
    if (desktop.contains(keyword) ||
        session.contains(keyword) ||
        sessionDesktop.contains(keyword)) {
      return true;
    }
  }

  return false;
}

class WindowsWindowFrame extends StatelessWidget {
  final Widget child;

  const WindowsWindowFrame({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) {
      return child;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final outerBgColor =
        isDark ? const Color(0xFF111317) : const Color(0xFFE8EBF0);
    final cardBgColor = theme.canvasColor;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);

    return ColoredBox(
      color: outerBgColor,
      child: Column(
        children: [
          const WindowsTitleBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 10,
                right: 10,
                bottom: 10,
                top: 0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                      child: RepaintBoundary(
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WindowsTitleBar extends StatefulWidget {
  const WindowsTitleBar({Key? key}) : super(key: key);

  @override
  State<WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<WindowsTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = max);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isTiling = isTilingWindowManager();

    if (isTiling) {
      return Container(
        height: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DragToMoveArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            child: Container(
              color: Colors.transparent,
              height: double.infinity,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 10, right: 12),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () async {
                  if (_isMaximized) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                child: Container(
                  color: Colors.transparent,
                  height: double.infinity,
                ),
              ),
            ),
          ),
          _MacOsWindowButtons(isMaximized: _isMaximized),
        ],
      ),
    );
  }
}

class _MacOsWindowButtons extends StatefulWidget {
  final bool isMaximized;

  const _MacOsWindowButtons({
    Key? key,
    required this.isMaximized,
  }) : super(key: key);

  @override
  State<_MacOsWindowButtons> createState() => _MacOsWindowButtonsState();
}

class _MacOsWindowButtonsState extends State<_MacOsWindowButtons> {
  bool _isGroupHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isGroupHovered = true),
      onExit: (_) => setState(() => _isGroupHovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minimize (Yellow)
          _MacOsDotButton(
            color: const Color(0xFFFFBD2E),
            borderColor: const Color(0xFFDEA123),
            icon: Icons.remove_rounded,
            iconColor: const Color(0xFF5A3C00),
            showGlyph: _isGroupHovered,
            onTap: () => windowManager.minimize(),
          ),
          const SizedBox(width: 8),
          // Maximize / Restore (Green)
          _MacOsDotButton(
            color: const Color(0xFF27C93F),
            borderColor: const Color(0xFF1AAB29),
            icon: widget.isMaximized
                ? Icons.unfold_less_rounded
                : Icons.unfold_more_rounded,
            iconColor: const Color(0xFF004D11),
            showGlyph: _isGroupHovered,
            onTap: () async {
              if (widget.isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          const SizedBox(width: 8),
          // Close (Red)
          _MacOsDotButton(
            color: const Color(0xFFFF5F56),
            borderColor: const Color(0xFFE0443E),
            icon: Icons.close_rounded,
            iconColor: const Color(0xFF4A0002),
            showGlyph: _isGroupHovered,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _MacOsDotButton extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final bool showGlyph;
  final VoidCallback onTap;

  const _MacOsDotButton({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.showGlyph,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor,
            width: 0.6,
          ),
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: showGlyph ? 0.9 : 0.0,
          child: Center(
            child: Icon(
              icon,
              size: 8.5,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
