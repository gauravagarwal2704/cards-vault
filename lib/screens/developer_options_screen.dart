import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_typography.dart';
import '../theme/app_colors.dart';

class DeveloperOptionsScreen extends StatefulWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  State<DeveloperOptionsScreen> createState() => _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState extends State<DeveloperOptionsScreen> {
  final _authService = AuthService();
  bool _testingAuthentication = false;

  Future<void> _testAuthentication() async {
    if (_testingAuthentication) return;
    setState(() => _testingAuthentication = true);
    final authenticated = await _authService.authenticateForCardDetails();
    if (!mounted) return;
    setState(() => _testingAuthentication = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          authenticated
              ? 'Authentication successful!'
              : 'Authentication failed',
        ),
        backgroundColor: authenticated
            ? AppSemanticColors.of(context).success
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final primary = theme.getPrimaryTextColor();
    final secondary = theme.getSecondaryTextColor();

    return Scaffold(
      backgroundColor: theme.getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Developer options',
          style: AppTypography.appBarTitle(color: primary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Material(
            color: theme.getCardColor(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.getOutlineColor()),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const ValueKey('developer-options-enabled-toggle'),
              value: true,
              onChanged: (enabled) {
                if (!enabled) Navigator.pop(context, true);
              },
              secondary: Icon(Icons.developer_mode_outlined, color: secondary),
              title: Text(
                'Developer options',
                style: AppTypography.listItem(color: primary)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Turn off to hide these tools and require five version taps again.',
                style: AppTypography.caption(color: secondary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: theme.getCardColor(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.getOutlineColor()),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const ValueKey('test-authentication-developer-option'),
              onTap: _testingAuthentication ? null : _testAuthentication,
              leading: Icon(Icons.security, color: secondary),
              title: Text(
                'Test authentication',
                style: AppTypography.listItem(color: primary)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Run the device authentication prompt',
                style: AppTypography.caption(color: secondary),
              ),
              trailing: _testingAuthentication
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
