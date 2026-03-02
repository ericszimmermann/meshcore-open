import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'scanner_screen.dart';
import 'usb_screen.dart';

/// Entry point that lets the user choose between USB or Bluetooth.
class ConnectionChoiceScreen extends StatelessWidget {
  const ConnectionChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(l10n.appTitle, textAlign: TextAlign.center),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 600.0;
              final gap = math.max(
                8.0,
                math.min(20.0, availableHeight * 0.035),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    flex: 3,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                l10n.connectionChoiceTitle,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: math.max(4.0, gap * 0.5)),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                l10n.connectionChoiceSubtitle,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                  Expanded(
                    flex: 4,
                    child: _ConnectionMethodButton(
                      icon: Icons.usb,
                      label: l10n.connectionChoiceUsbLabel,
                      color: theme.colorScheme.primaryContainer,
                      iconColor: theme.colorScheme.onPrimaryContainer,
                      onPressed: () {
                        debugPrint(
                          'ConnectionChoiceScreen: USB selected, opening UsbScreen',
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const UsbScreen()),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: gap),
                  Expanded(
                    flex: 4,
                    child: _ConnectionMethodButton(
                      icon: Icons.bluetooth,
                      label: l10n.connectionChoiceBluetoothLabel,
                      color: theme.colorScheme.surfaceContainerHighest,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                      onPressed: () {
                        debugPrint(
                          'ConnectionChoiceScreen: Bluetooth selected, opening ScannerScreen',
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ScannerScreen(),
                          ),
                        );
                      },
                    ),
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

class _ConnectionMethodButton extends StatelessWidget {
  const _ConnectionMethodButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        minimumSize: const Size.fromHeight(0),
      ),
      onPressed: onPressed,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 200.0;
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 320.0;
          final isCompact = availableHeight < 72.0 || availableWidth < 180.0;
          final baseGap = isCompact ? 8.0 : 12.0;
          final content = Flex(
            direction: isCompact ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isCompact ? 24.0 : 60.0, color: iconColor),
              SizedBox(
                width: isCompact ? baseGap : 0,
                height: isCompact ? 0 : baseGap,
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style:
                    (isCompact
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.titleLarge)
                        ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          );

          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, availableWidth - 12),
                  maxHeight: math.max(0, availableHeight - 12),
                ),
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}
