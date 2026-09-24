import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static final Uri contactUri = Uri(
    scheme: 'mailto',
    path: 'agarwalgaurav.apps@gmail.com',
    queryParameters: const {'subject': 'CardVault privacy enquiry'},
  );

  Future<void> _contactDeveloper(BuildContext context) async {
    final opened = await launchUrl(contactUri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open an email app.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: SelectionArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal(MediaQuery.sizeOf(context).width),
            AppSpacing.md,
            AppSpacing.pageHorizontal(MediaQuery.sizeOf(context).width),
            AppSpacing.xxxl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CardVault Privacy Policy',
                      style: AppTypography.pageTitle(color: scheme.onSurface),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Effective 24 September 2026',
                      style: AppTypography.caption(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _PolicySection(
                      title: 'Overview',
                      body:
                          'CardVault is an offline card organizer developed by '
                          'Gaurav Agarwal. It does not require an account, run '
                          'advertising, use analytics, or sell personal data. '
                          'Your saved wallet is kept on your device.',
                    ),
                    const _PolicySection(
                      title: 'Data you choose to store',
                      body:
                          'You may enter cardholder names, payment-card numbers, '
                          'expiry dates, security codes, bank and card type, '
                          'nicknames, account details, UPI IDs, notes, groups, '
                          'card photographs, attachments, and custom background '
                          'images. CardVault uses this information only to '
                          'organize and display your cards and to provide the '
                          'features you request.',
                    ),
                    const _PolicySection(
                      title: 'Camera, photos, and NFC',
                      body:
                          'Camera or photo-library access is used only when you '
                          'choose to scan a card or add an image. Android card '
                          'recognition runs on the device; scan frames are '
                          'discarded after processing unless you explicitly '
                          'save an image. NFC is used only when you start an NFC '
                          'scan to read supported card data nearby.',
                    ),
                    const _PolicySection(
                      title: 'Storage and security',
                      body:
                          'Structured card records are stored in encrypted '
                          'platform storage. Card images and attachments remain '
                          'in CardVault\'s private app storage. Android system '
                          'backup is disabled. Optional app locking uses your '
                          'device authentication; CardVault does not receive or '
                          'store your biometric data.',
                    ),
                    const _PolicySection(
                      title: 'Sharing, backups, and support',
                      body:
                          'CardVault does not automatically transmit your wallet. '
                          'If you choose Share, Export Backup, or Send Feedback, '
                          'Android passes only the information you selected to '
                          'the app or service you choose. Backup and single-card '
                          'files are password-encrypted. Support emails may '
                          'contain your comments and, only if you opt in, '
                          'redacted diagnostics and device details. Do not put '
                          'card details in support messages. Support '
                          'correspondence is retained only as long as reasonably '
                          'needed to respond and investigate. You may ask for '
                          'its deletion using the contact below.',
                    ),
                    const _PolicySection(
                      title: 'Diagnostics',
                      body:
                          'CardVault keeps a bounded, encrypted diagnostic log '
                          'on the device for troubleshooting. It is designed to '
                          'redact card numbers, expiry dates, security codes, '
                          'account identifiers, email addresses, and file paths. '
                          'Local diagnostics expire after 72 hours and are not '
                          'sent unless you explicitly attach them to feedback.',
                    ),
                    const _PolicySection(
                      title: 'Retention and deletion',
                      body:
                          'Card records, groups, and their app-managed images '
                          'remain on your device until you delete a card or use '
                          'Settings > Data > Delete all cards. Your display name '
                          'and preferences remain until changed, app storage is '
                          'cleared, or CardVault is uninstalled. Files you export '
                          'or share are controlled by you and the receiving app. '
                          'CardVault has no server account or server-side wallet '
                          'data to delete.',
                    ),
                    const _PolicySection(
                      title: 'Children',
                      body:
                          'CardVault is a general-audience utility and is not '
                          'directed to children. It does not knowingly collect '
                          'children\'s data.',
                    ),
                    const _PolicySection(
                      title: 'Changes',
                      body:
                          'This policy may be updated when CardVault\'s features '
                          'or legal obligations change. The effective date above '
                          'will be updated with any revision.',
                    ),
                    Text(
                      'Contact',
                      style: AppTypography.sectionTitle(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'For privacy questions, contact Gaurav Agarwal at '
                      'agarwalgaurav.apps@gmail.com.',
                      style: AppTypography.body(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      key: const ValueKey('privacy-contact-link'),
                      onPressed: () => _contactDeveloper(context),
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email the developer'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.sectionTitle(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: AppTypography.body(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
