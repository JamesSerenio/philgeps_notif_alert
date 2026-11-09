part of '../../main.dart';

class _ScraperSignIn extends StatefulWidget {
  const _ScraperSignIn();
  @override
  State<_ScraperSignIn> createState() => _ScraperSignInState();
}

class _ScraperSignInState extends State<_ScraperSignIn> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (!_sent) {
        await SupabaseConfig.client.auth.signInWithOtp(
          email: _email.text.trim(), shouldCreateUser: false,
        );
        if (mounted) setState(() => _sent = true);
      } else {
        await SupabaseConfig.client.auth.verifyOTP(
          email: _email.text.trim(), token: _code.text.trim(), type: OtpType.email,
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _email.dispose(); _code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in to check PhilGEPS'),
    content: SizedBox(width: 360, child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Use your authorized email address to request a fresh check.'),
        const SizedBox(height: 16),
        TextField(controller: _email, enabled: !_sent && !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email')),
        if (_sent) TextField(controller: _code, enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Email verification code'),
          onSubmitted: (_) => _submit()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.red))),
      ],
    )),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Please wait...' : _sent ? 'Verify and check' : 'Send code')),
    ],
  );
}
