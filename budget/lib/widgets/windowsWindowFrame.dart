// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/navigationFramework.dart';

class WindowsWindowFrame extends StatelessWidget {
  final Widget child;

  const WindowsWindowFrame({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isWindows) {
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
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 10, right: 12),
      child: Row(
        children: [
          const _SidebarToggleButton(),
          const SizedBox(width: 8),
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

class _SidebarToggleButton extends StatefulWidget {
  const _SidebarToggleButton();

  @override
  State<_SidebarToggleButton> createState() => _SidebarToggleButtonState();
}

class _SidebarToggleButtonState extends State<_SidebarToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isExpanded = appStateSettings["expandedNavigationSidebar"] == true;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (sidebarStateKey.currentState != null) {
            sidebarStateKey.currentState?.toggleSidebar();
          } else {
            appStateSettings["expandedNavigationSidebar"] =
                !(appStateSettings["expandedNavigationSidebar"] ?? true);
            updateSettings(
                "expandedNavigationSidebar",
                appStateSettings["expandedNavigationSidebar"],
                updateGlobalState: true);
          }
        },
        child: Container(
          width: 28,
          height: 24,
          decoration: BoxDecoration(
            color: _isHovered
                ? (isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.black.withOpacity(0.08))
                : (isExpanded
                    ? (isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04))
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isExpanded
                  ? (isDark ? Colors.white24 : Colors.black12)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Icon(
            Icons.view_sidebar_outlined,
            size: 15,
            color: isExpanded
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white60 : Colors.black45),
          ),
        ),
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
