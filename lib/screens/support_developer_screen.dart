import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_icon_provider.dart';
import '../services/app_log_service.dart';
import '../services/support_purchase_service.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_design_system.dart';
import '../widgets/app_icon_artwork.dart';

class SupportDeveloperScreen extends StatefulWidget {
  const SupportDeveloperScreen({super.key, this.controller});

  final SupportPurchaseController? controller;

  @override
  State<SupportDeveloperScreen> createState() => _SupportDeveloperScreenState();
}

class _SupportDeveloperScreenState extends State<SupportDeveloperScreen> {
  static final Uri _buyMeACoffeeUrl = Uri.parse(
    'https://buymeacoffee.com/gauravagarwal',
  );
  static final Uri _buyMeAChaiUrl = Uri.parse(
    'https://buymeachai.in/gauravagarwal',
  );

  late final SupportPurchaseController _controller;
  late int _observedSuccessSerial;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SupportPurchaseService.instance;
    _observedSuccessSerial = _controller.purchaseSuccessSerial;
    _controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.initialize();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    if (_controller.purchaseSuccessSerial != _observedSuccessSerial) {
      _observedSuccessSerial = _controller.purchaseSuccessSerial;
      final price = _controller.lastPurchasedPrice;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              price == null
                  ? 'Thank you! Your Supporter Star is ready.'
                  : 'Thank you for your $price support! You earned a Supporter Star.',
            ),
          ),
        );
    }
    setState(() {});
  }

  List<ProductDetails> get _quickTips {
    final products = _controller.products;
    if (products.length <= 3) return products;

    final indexes = <int>{
      0,
      math.min(2, products.length - 1),
      math.min(4, products.length - 1),
    };
    return [for (final index in indexes) products[index]];
  }

  Future<void> _purchase(ProductDetails product) async {
    await _controller.purchase(product);
  }

  Future<void> _showMoreAmounts() async {
    final product = await showModalBottomSheet<ProductDetails>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MoreAmountsSheet(products: _controller.products),
    );
    if (product != null && mounted) await _purchase(product);
  }

  Future<void> _openExternalSupport(Uri url, String destination) async {
    AppLogService.instance.action(
      'Support',
      'External support link requested',
      details: {'destination': destination},
    );
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (opened || !mounted) return;
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Open $destination',
        error,
        stackTrace,
        category: 'Failure/Support',
      );
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $destination')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appIcon = context.watch<AppIconProvider>().selected;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('close-support-developer'),
          tooltip: 'Close',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal(MediaQuery.sizeOf(context).width),
            AppSpacing.xs,
            AppSpacing.pageHorizontal(MediaQuery.sizeOf(context).width),
            AppSpacing.xxxl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: AppIconArtwork(
                        option: appIcon,
                        size: 104,
                        borderRadius: 28,
                        addSurfaceShadow: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'CardVault',
                      textAlign: TextAlign.center,
                      style: AppTypography.pageTitle(color: scheme.onSurface),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Enjoying the app? An optional Supporter Star helps keep it growing.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(color: scheme.onSurfaceVariant),
                    ),
                    if (_controller.supporterStars > 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: Chip(
                          key: const ValueKey('supporter-stars'),
                          avatar: Icon(
                            Icons.star_rounded,
                            color: scheme.onSecondaryContainer,
                          ),
                          backgroundColor: scheme.secondaryContainer,
                          label: Text(
                            '${_controller.supporterStars} Supporter ${_controller.supporterStars == 1 ? 'Star' : 'Stars'}',
                            style: TextStyle(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppSurface(
                      child: Column(
                        children: const [
                          _SupportReason(
                            icon: Icons.favorite_outline_rounded,
                            label: 'Support independent development',
                          ),
                          Divider(height: 25),
                          _SupportReason(
                            icon: Icons.auto_awesome_outlined,
                            label: 'Help fund future feature enhancements for everyone',
                          ),
                          Divider(height: 25),
                          _SupportReason(
                            icon: Icons.star_outline_rounded,
                            label: 'Receive a Supporter Star on this page as our thank-you',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Support with Google Play',
                      style: AppTypography.sectionTitle(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_controller.isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_controller.products.isNotEmpty) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final product in _quickTips)
                            FilledButton.tonal(
                              key: ValueKey('tip-${product.id}'),
                              onPressed: _controller.isPurchasing
                                  ? null
                                  : () => _purchase(product),
                              child: Text(product.price),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        key: const ValueKey('more-amounts'),
                        onPressed: _controller.isPurchasing
                            ? null
                            : _showMoreAmounts,
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('More amounts'),
                      ),
                    ],
                    if (_controller.message != null) ...[
                      if (!_controller.isLoading)
                        AppStatusMessage(
                          kind: AppStatusKind.info,
                          message: _controller.message!,
                          action: IconButton(
                            tooltip: 'Retry',
                            onPressed: () =>
                                _controller.initialize(forceRefresh: true),
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                    ],
                    if (_controller.isPurchasing) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppStatusMessage(
                        kind: AppStatusKind.info,
                        message: 'Waiting for Google Play…',
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Other ways to support',
                      style: AppTypography.sectionTitle(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'These options open in your browser. External contributions '
                      'do not add a Supporter Star.',
                      style: AppTypography.caption(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          flex: 9,
                          child: _BrandSupportButton(
                            key: const ValueKey('buy-me-a-coffee-link'),
                            semanticLabel: 'Buy me a coffee',
                            assetPath: 'assets/branding/bmc-button.svg',
                            onPressed: () => _openExternalSupport(
                              _buyMeACoffeeUrl,
                              'Buy Me a Coffee',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 11,
                          child: _ExternalSupportButton(
                            key: const ValueKey('buy-me-a-chai-link'),
                            label: 'Buy me a Chai',
                            icon: const Icon(
                              Icons.emoji_food_beverage_rounded,
                              key: ValueKey('buy-me-a-chai-icon'),
                              size: 18,
                            ),
                            backgroundColor: const Color(0xFFDE6B35),
                            foregroundColor: Colors.white,
                            onPressed: () => _openExternalSupport(
                              _buyMeAChaiUrl,
                              'Buy Me a Chai',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Support is entirely optional. Each purchase adds one cosmetic '
                      'Supporter Star here; every CardVault feature remains available to everyone. '
                      'Google Play processes Supporter Star purchases. Coffee and Chai '
                      'contributions are handled by their respective websites and do not add '
                      'a Star. CardVault never receives your payment-card details.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption(
                        color: scheme.onSurfaceVariant,
                      ),
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

class _BrandSupportButton extends StatelessWidget {
  const _BrandSupportButton({
    super.key,
    required this.semanticLabel,
    required this.assetPath,
    required this.onPressed,
  });

  final String semanticLabel;
  final String assetPath;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: SvgPicture.asset(
              assetPath,
              key: const ValueKey('buy-me-a-coffee-brand-artwork'),
              fit: BoxFit.contain,
              semanticsLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalSupportButton extends StatelessWidget {
  const _ExternalSupportButton({
    super.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportReason extends StatelessWidget {
  const _SupportReason({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: AppShapes.mediumRadius,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTypography.body(color: scheme.onSurface)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _MoreAmountsSheet extends StatefulWidget {
  const _MoreAmountsSheet({required this.products});

  final List<ProductDetails> products;

  @override
  State<_MoreAmountsSheet> createState() => _MoreAmountsSheetState();
}

class _MoreAmountsSheetState extends State<_MoreAmountsSheet> {
  ProductDetails? _selectedProduct;

  void _selectProduct(ProductDetails product) {
    setState(() => _selectedProduct = product);
  }

  void _submit() {
    final product = _selectedProduct;
    if (product != null) Navigator.pop(context, product);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'More amounts',
            style: AppTypography.dialogTitle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose an amount to receive one Supporter Star.',
            style: AppTypography.body(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final product in widget.products)
                ChoiceChip(
                  key: ValueKey('more-amounts-${product.id}'),
                  label: Text(product.price),
                  selected: _selectedProduct?.id == product.id,
                  onSelected: (_) => _selectProduct(product),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const ValueKey('submit-more-amounts'),
            onPressed: _selectedProduct == null ? null : _submit,
            child: Text(
              _selectedProduct == null
                  ? 'Choose an amount'
                  : 'Purchase for ${_selectedProduct!.price}',
            ),
          ),
        ],
      ),
    );
  }
}
