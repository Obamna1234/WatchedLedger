import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lock/app_lock.dart';
import '../../core/lock/platform_lock.dart';

/// Covers the whole app while it is locked, and hides it in the app
/// switcher when that option is on.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.lock, required this.child});

  final AppLock lock;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lock.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    widget.lock.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _changed() {
    unawaited(SecureWindow.set(widget.lock.hideInSwitcher));
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = widget.lock;
    switch (state) {
      case AppLifecycleState.inactive:
        // iOS takes the app-switcher picture now. (Android uses FLAG_SECURE.)
        if (defaultTargetPlatform == TargetPlatform.iOS &&
            lock.hideInSwitcher &&
            !_covered) {
          setState(() => _covered = true);
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        lock.wentToBackground();
        if (lock.hideInSwitcher && !_covered) setState(() => _covered = true);
      case AppLifecycleState.resumed:
        lock.cameToForeground();
        if (_covered) setState(() => _covered = false);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.lock.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: locked,
          child: ExcludeSemantics(excluding: locked, child: widget.child),
        ),
        if (locked) LockScreen(lock: widget.lock),
        if (_covered && !locked) const _PrivacyCover(),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Icon(Icons.lock_outline, size: 48, color: scheme.primary),
      ),
    );
  }
}

/// PIN pad with optional fingerprint / Face ID.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});
  final AppLock lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _message;
  bool _checking = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // A keyboard left open would cover the PIN pad.
    FocusManager.instance.primaryFocus?.unfocus();
    _startTicker();
    if (widget.lock.useBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    if (widget.lock.waitRemaining == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (widget.lock.waitRemaining == null) t.cancel();
      setState(() {});
    });
  }

  Future<void> _biometric() async {
    if (!mounted || _checking) return;
    await widget.lock.unlockWithBiometrics();
  }

  Future<void> _submit() async {
    if (_checking || _pin.length < kMinPinLength) return;
    setState(() => _checking = true);
    final ok = await widget.lock.unlockWithPin(_pin);
    if (!mounted) return;
    if (!ok) unawaited(HapticFeedback.vibrate());
    setState(() {
      _checking = false;
      _pin = '';
      _message = ok ? null : 'Wrong PIN';
    });
    _startTicker();
  }

  void _digit(String d) {
    if (_checking || widget.lock.waitRemaining != null) return;
    if (_pin.length >= kMaxPinLength) return;
    setState(() {
      _pin += d;
      _message = null;
    });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wait = widget.lock.waitRemaining;
    final status = wait != null
        ? 'Too many tries. Try again in ${_formatWait(wait)}.'
        : _message ?? 'Enter your PIN';
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          // Scrolls on small screens or with large text, so the whole PIN
          // pad can always be reached.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('WatchedLedger is locked',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _message != null || wait != null
                        ? theme.colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                PinDots(length: _pin.length, checking: _checking),
                const SizedBox(height: 16),
                PinPad(
                  onDigit: _digit,
                  onBackspace: _backspace,
                  onSubmit: _submit,
                  extra: widget.lock.useBiometrics
                      ? IconButton(
                          tooltip: 'Use fingerprint or face',
                          icon: const Icon(Icons.fingerprint, size: 32),
                          onPressed: _biometric,
                        )
                      : null,
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

String _formatWait(Duration d) {
  final s = d.inSeconds + 1;
  if (s < 60) return '$s s';
  return '${(s / 60).ceil()} min';
}

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.checking = false});
  final int length;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (checking) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < length; i++)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration:
                  BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

/// 3x4 number pad. [extra] goes bottom-left (e.g. fingerprint).
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    this.extra,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _PadButton(
          label: d,
          onTap: () => onDigit(d),
        );
    Widget row(List<Widget> c) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final w in c) SizedBox(width: 80, height: 64, child: w),
          ],
        );
    return Column(
      children: [
        row([key('1'), key('2'), key('3')]),
        row([key('4'), key('5'), key('6')]),
        row([key('7'), key('8'), key('9')]),
        row([
          Center(
            child: extra ??
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: onBackspace,
                ),
          ),
          key('0'),
          Center(
            child: IconButton.filled(
              tooltip: 'OK',
              icon: const Icon(Icons.arrow_forward),
              onPressed: onSubmit,
            ),
          ),
        ]),
        if (extra != null)
          TextButton.icon(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined, size: 18),
            label: const Text('Delete'),
          ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(shape: const StadiumBorder()),
        child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}
