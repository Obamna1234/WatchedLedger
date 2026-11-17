import 'package:flutter/material.dart';

import '../../core/lock/app_lock.dart';
import 'lock_gate.dart';

/// Settings > App lock.
class LockSettingsPage extends StatelessWidget {
  const LockSettingsPage({super.key, required this.lock});
  final AppLock lock;

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));

  /// Asks for the current PIN. True if it was right.
  Future<bool> _confirmCurrent(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _VerifyPinPage(lock: lock),
    ));
    return ok ?? false;
  }

  Future<void> _turnOn(BuildContext context) async {
    final pin = await choosePin(context);
    if (pin == null || !context.mounted) return;
    await lock.setPin(pin);
    if (context.mounted) _toast(context, 'App lock is on');
  }

  Future<void> _turnOff(BuildContext context) async {
    if (!await _confirmCurrent(context) || !context.mounted) return;
    await lock.disable();
    if (context.mounted) _toast(context, 'App lock is off');
  }

  Future<void> _changePin(BuildContext context) async {
    if (!await _confirmCurrent(context) || !context.mounted) return;
    final pin = await choosePin(context);
    if (pin == null || !context.mounted) return;
    await lock.setPin(pin);
    if (context.mounted) _toast(context, 'PIN changed');
  }

  Future<void> _setBiometrics(BuildContext context, bool on) async {
    if (!on) {
      await lock.setUseBiometrics(false);
      return;
    }
    // Prove it works before relying on it.
    final bio = lock.biometrics;
    var ok = false;
    try {
      ok = await bio?.authenticate('Confirm to use fingerprint or face') ??
          false;
    } catch (_) {
      ok = false;
    }
    if (ok) {
      await lock.setUseBiometrics(true);
    } else if (context.mounted) {
      _toast(context, 'Fingerprint / face not confirmed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: ListenableBuilder(
        listenable: lock,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Lock with a PIN'),
              subtitle: const Text(
                  'Asks for your PIN when you open the app. Your library is '
                  'always encrypted either way.'),
              value: lock.enabled,
              onChanged: (on) => on ? _turnOn(context) : _turnOff(context),
            ),
            if (lock.enabled) ...[
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Change PIN'),
                onTap: () => _changePin(context),
              ),
              if (lock.biometricsAvailable)
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Unlock with fingerprint or face'),
                  subtitle: const Text('Your PIN still works too.'),
                  value: lock.useBiometrics,
                  onChanged: (on) => _setBiometrics(context, on),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide in recent apps'),
                subtitle: const Text(
                    'Shows a blank screen in the app switcher. On Android '
                    'this also blocks screenshots of the app.'),
                value: lock.hideInSwitcherSetting,
                onChanged: lock.setHideInSwitcher,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Lock again when the app is closed',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
              for (final a in LockAfter.values)
                ListTile(
                  title: Text(a.label),
                  trailing: lock.lockAfter == a
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => lock.setLockAfter(a),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text('Show private items'),
                subtitle: const Text('Items marked "Private" stay hidden until '
                    'you enter your PIN here, and hide again when the app '
                    'locks.'),
                value: lock.privateVisible,
                onChanged: (on) async {
                  if (!on) {
                    lock.hidePrivate();
                  } else if (await _confirmCurrent(context)) {
                    lock.revealPrivate();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_clock_outlined),
                title: const Text('Lock now'),
                onTap: lock.lockNow,
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Your PIN is stored only as a salted hash in the phone's "
                'secure storage. It is not in backups. After 5 wrong tries '
                'the app makes you wait, longer each time. If you forget '
                'your PIN, reinstalling the app is the only way in, and '
                'that erases your library, so keep a backup.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a new PIN twice. Returns it, or null if cancelled.
Future<String?> choosePin(BuildContext context) async {
  final first = await Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => const PinEntryPage(
      title: 'Choose a PIN',
      prompt: 'Enter 4 to 12 digits',
    ),
  ));
  if (first == null || !context.mounted) return null;
  final second = await Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => const PinEntryPage(
      title: 'Choose a PIN',
      prompt: 'Enter it again',
    ),
  ));
  if (second == null || !context.mounted) return null;
  if (second != first) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text("The PINs didn't match. Try again.")));
    return null;
  }
  return first;
}

/// Full-screen number pad that pops with the digits typed.
class PinEntryPage extends StatefulWidget {
  const PinEntryPage({super.key, required this.title, required this.prompt});
  final String title;
  final String prompt;

  @override
  State<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<PinEntryPage> {
  String _pin = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.prompt, style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                PinDots(length: _pin.length),
                const SizedBox(height: 16),
                PinPad(
                  onDigit: (d) {
                    if (_pin.length < kMaxPinLength) setState(() => _pin += d);
                  },
                  onBackspace: () {
                    if (_pin.isNotEmpty) {
                      setState(() => _pin = _pin.substring(0, _pin.length - 1));
                    }
                  },
                  onSubmit: () {
                    if (AppLock.validPin(_pin)) Navigator.of(context).pop(_pin);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifyPinPage extends StatefulWidget {
  const _VerifyPinPage({required this.lock});
  final AppLock lock;

  @override
  State<_VerifyPinPage> createState() => _VerifyPinPageState();
}

class _VerifyPinPageState extends State<_VerifyPinPage> {
  String _pin = '';
  String? _error;
  bool _checking = false;

  Future<void> _submit() async {
    if (_checking || _pin.length < kMinPinLength) return;
    setState(() => _checking = true);
    final ok = await widget.lock.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final wait = widget.lock.waitRemaining;
    setState(() {
      _checking = false;
      _pin = '';
      _error = wait == null
          ? 'Wrong PIN'
          : 'Too many tries. Wait ${wait.inSeconds + 1} s.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Current PIN')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? 'Enter your current PIN',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: _error == null ? null : theme.colorScheme.error)),
                const SizedBox(height: 16),
                PinDots(length: _pin.length, checking: _checking),
                const SizedBox(height: 16),
                PinPad(
                  onDigit: (d) {
                    if (_pin.length < kMaxPinLength && !_checking) {
                      setState(() {
                        _pin += d;
                        _error = null;
                      });
                    }
                  },
                  onBackspace: () {
                    if (_pin.isNotEmpty) {
                      setState(() => _pin = _pin.substring(0, _pin.length - 1));
                    }
                  },
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
