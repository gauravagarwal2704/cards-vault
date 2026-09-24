import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../models/card_data.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import '../services/auth_service.dart';
import '../services/app_log_service.dart';
import '../services/secure_card_storage.dart';
import '../providers/theme_provider.dart';
import '../widgets/backup_password_dialog.dart';
import '../widgets/card_attachments.dart';
import '../widgets/wallet_card_face.dart';
import '../widgets/wallet_card_hero.dart';
import '../widgets/card_background_surface.dart';
import '../widgets/wallet_card.dart';
import '../utils/card_contrast.dart';
import '../utils/card_network_utils.dart';
import 'card_edit_screen.dart';
import '../theme/app_typography.dart';
import '../theme/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class CardDetailScreen extends StatefulWidget {
  final CardData card;
  final int cardIndex;

  const CardDetailScreen({
    super.key,
    required this.card,
    required this.cardIndex,
  });

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final SecureCardStorage _cardStorage = SecureCardStorage();
  bool _isCardNumberVisible = false;
  bool _isExpiryVisible = false;
  bool _isCvvVisible = false;
  late CardData _card;

  /// Held in state rather than resolved with a FutureBuilder so the card face
  /// does not flash placeholder text on every rebuild.
  String? _cardholderName;
  String? _expiryDate;
  CardNetwork _network = CardNetwork.unknown;
  Timer? _hideSensitiveTimer;
  int? _cardDragPointer;
  Offset? _cardDragStart;
  VelocityTracker? _cardDragVelocityTracker;
  double _cardDragExtent = 0;
  bool _isDraggingCard = false;
  bool _isDismissingCard = false;

  static const double _cardDragSlop = 10;
  static const double _cardDismissDistance = 88;
  static const double _cardDismissVelocity = 800;

  @override
  void initState() {
    super.initState();
    AppLogService.instance.action('Navigation', 'Opened card details');
    _card = widget.card;
    _loadCardFaceDetails();
  }

  @override
  void dispose() {
    _hideSensitiveTimer?.cancel();
    super.dispose();
  }

  void _scheduleSensitiveHide() {
    _hideSensitiveTimer?.cancel();
    _hideSensitiveTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      setState(() {
        _isCardNumberVisible = false;
        _isExpiryVisible = false;
        _isCvvVisible = false;
      });
    });
  }

  Future<void> _loadCardFaceDetails() async {
    final name = await _card.getDecryptedCardholderName();
    final expiry = await _card.getDecryptedExpiryDate();
    final network = await _resolveNetwork();
    if (!mounted) return;
    setState(() {
      _cardholderName = name;
      _expiryDate = expiry;
      _network = network;
    });
  }

  /// Older builds stored inconsistent `cardType` labels, and some cards were
  /// saved as "Unknown" by detectors that missed their BIN range. Falling back
  /// to the card number recovers the network, and the corrected label is written
  /// back so list views pick it up too.
  Future<CardNetwork> _resolveNetwork() async {
    final fromType = CardNetworkUtils.networkFromCardType(_card.cardType);
    if (fromType != CardNetwork.unknown) return fromType;

    final number = await _card.getDecryptedCardNumber();
    final fromNumber = CardNetworkUtils.detectNetwork(number);
    if (fromNumber == CardNetwork.unknown) return fromNumber;

    final cardId = _card.id;
    if (cardId != null) {
      try {
        final repaired = await _cardStorage.updateCardById(
          cardId,
          (current) => current.copyWith(
            cardType: CardNetworkUtils.getNetworkName(fromNumber),
          ),
        );
        if (repaired != null) _card = repaired;
      } catch (_) {
        // A failed metadata repair must not expose storage paths or card data.
      }
    }
    return fromNumber;
  }

  Future<bool> _ensureAuthenticated({
    required ProtectedAction action,
    required String reason,
  }) async {
    final authentication =
        context.read<AuthenticationCoordinator?>() ??
        AuthenticationCoordinator();
    final authenticated = await authentication.authorize(
      action,
      reason: reason,
    );
    if (!authenticated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authentication.lastErrorMessage ?? 'Authentication required',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return authenticated;
  }

  Future<void> _toggleCardNumberVisibility() async {
    if (_isCardNumberVisible) {
      setState(() => _isCardNumberVisible = false);
      AppLogService.instance.action('Card details', 'Hid card number');
      return;
    }
    if (await _ensureAuthenticated(
          action: ProtectedAction.revealCardDetails,
          reason: 'Authenticate to view card number',
        ) &&
        mounted) {
      HapticFeedback.selectionClick();
      setState(() => _isCardNumberVisible = true);
      AppLogService.instance.action('Card details', 'Revealed card number');
      _scheduleSensitiveHide();
    }
  }

  Future<void> _toggleExpiryVisibility() async {
    if (_isExpiryVisible) {
      setState(() => _isExpiryVisible = false);
      AppLogService.instance.action('Card details', 'Hid expiry date');
      return;
    }
    if (await _ensureAuthenticated(
          action: ProtectedAction.revealCardDetails,
          reason: 'Authenticate to view expiry date',
        ) &&
        mounted) {
      HapticFeedback.selectionClick();
      setState(() => _isExpiryVisible = true);
      AppLogService.instance.action('Card details', 'Revealed expiry date');
      _scheduleSensitiveHide();
    }
  }

  Future<void> _toggleCvvVisibility() async {
    if (_isCvvVisible) {
      setState(() => _isCvvVisible = false);
      AppLogService.instance.action('Card details', 'Hid CVV');
      return;
    }
    if (await _ensureAuthenticated(
          action: ProtectedAction.revealCardDetails,
          reason: 'Authenticate to view CVV',
        ) &&
        mounted) {
      HapticFeedback.selectionClick();
      setState(() => _isCvvVisible = true);
      AppLogService.instance.action('Card details', 'Revealed CVV');
      _scheduleSensitiveHide();
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    AppLogService.instance.action(
      'Card details',
      'Copied protected field',
      details: {'field': label},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppSemanticColors.of(context).success,
        ),
      );
    }
  }

  Future<void> _copyCardNumber() async {
    final ok = await _ensureAuthenticated(
      action: ProtectedAction.copyCardDetails,
      reason: 'Authenticate to copy card number',
    );
    if (!ok) return;
    final number = await _card.getDecryptedCardNumber();
    if (!mounted) return;
    await _copyToClipboard(number, 'Card number');
  }

  Future<void> _copyExpiry() async {
    final ok = await _ensureAuthenticated(
      action: ProtectedAction.copyCardDetails,
      reason: 'Authenticate to copy expiry date',
    );
    if (!ok) return;
    final expiry = await _card.getDecryptedExpiryDate();
    if (!mounted) return;
    await _copyToClipboard(expiry, 'Expiry date');
  }

  Future<void> _copyCvv() async {
    final ok = await _ensureAuthenticated(
      action: ProtectedAction.copyCardDetails,
      reason: 'Authenticate to copy CVV',
    );
    if (!ok) return;
    final cvv = await _card.getDecryptedCvv();
    if (!mounted) return;
    if (cvv == null || cvv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No CVV saved for this card'),
          backgroundColor: AppSemanticColors.of(context).warning,
        ),
      );
      return;
    }
    if (!_isCvvVisible) {
      setState(() => _isCvvVisible = true);
    }
    await _copyToClipboard(cvv, 'CVV');
  }

  Future<void> _deleteCard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: Text('Delete card ending in ${_card.lastFourDigits}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _card.id != null) {
      try {
        await _cardStorage.deleteCard(_card.id!);
        AppLogService.instance.action('Cards', 'Deleted card');
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (_) {
        AppLogService.instance.record('Cards', 'Card deletion failed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('The card could not be deleted.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _editCard({
    CardEditInitialSection initialSection = CardEditInitialSection.cardDetails,
  }) async {
    final authenticated = await _ensureAuthenticated(
      action: ProtectedAction.editCardDetails,
      reason: 'Authenticate to edit protected card details',
    );
    if (!authenticated || !mounted) return;

    AppLogService.instance.action(
      'Card details',
      'Opened card editor',
      details: {'section': initialSection.name},
    );

    final result = await Navigator.push<CardData>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CardEditScreen(card: _card, initialSection: initialSection),
      ),
    );
    if (result != null && mounted) {
      AppLogService.instance.action('Card details', 'Card edit completed');
      setState(() => _card = result);
      Navigator.pop(context, true);
    }
  }

  void _handleCardPointerDown(PointerDownEvent event) {
    if (_cardDragPointer != null || _isDismissingCard) return;
    _cardDragPointer = event.pointer;
    _cardDragStart = event.position;
    _cardDragVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handleCardPointerMove(PointerMoveEvent event) {
    if (event.pointer != _cardDragPointer || _cardDragStart == null) return;
    _cardDragVelocityTracker?.addPosition(event.timeStamp, event.position);

    final delta = event.position - _cardDragStart!;
    // Listening to pointer events instead of claiming the vertical gesture
    // keeps upward drags available to the surrounding scroll view.
    if (delta.dy <= _cardDragSlop || delta.dy < delta.dx.abs()) {
      if (_isDraggingCard) _resetCardDrag();
      return;
    }

    final extent = delta.dy - _cardDragSlop;
    if ((_cardDragExtent - extent).abs() < 0.5) return;
    setState(() {
      _isDraggingCard = true;
      _cardDragExtent = extent;
    });
  }

  void _handleCardPointerUp(PointerUpEvent event) {
    if (event.pointer != _cardDragPointer) return;
    _cardDragVelocityTracker?.addPosition(event.timeStamp, event.position);
    final velocity =
        _cardDragVelocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    final shouldDismiss =
        _cardDragExtent >= _cardDismissDistance ||
        (_cardDragExtent >= 24 && velocity >= _cardDismissVelocity);

    _clearCardPointerTracking();
    if (shouldDismiss) {
      _dismissCardFromSwipe();
    } else {
      _settleCardBack();
    }
  }

  void _handleCardPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _cardDragPointer) return;
    _clearCardPointerTracking();
    _settleCardBack();
  }

  void _clearCardPointerTracking() {
    _cardDragPointer = null;
    _cardDragStart = null;
    _cardDragVelocityTracker = null;
  }

  void _resetCardDrag() {
    if (!mounted || (!_isDraggingCard && _cardDragExtent == 0)) return;
    setState(() {
      _isDraggingCard = false;
      _cardDragExtent = 0;
    });
  }

  void _settleCardBack() {
    if (!mounted) return;
    setState(() {
      _isDraggingCard = false;
      _cardDragExtent = 0;
    });
  }

  Future<void> _dismissCardFromSwipe() async {
    if (_isDismissingCard || !mounted) return;
    _isDismissingCard = true;
    HapticFeedback.lightImpact();
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      _isDismissingCard = false;
      _settleCardBack();
    }
  }

  Future<void> _showShareBottomSheet() async {
    final authenticated = await _ensureAuthenticated(
      action: ProtectedAction.shareCardDetails,
      reason: 'Authenticate to choose protected card details to share',
    );
    if (!authenticated || !mounted) return;
    AppLogService.instance.action('Card sharing', 'Opened share options');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShareBottomSheet(card: _card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bank = _card.bankId != null ? Banks.getById(_card.bankId!) : null;
    final design = _card.designId != null
        ? CardDesigns.getById(_card.designId!)
        : null;
    final primaryColor = _card.customGradientStartColor != null
        ? Color(_card.customGradientStartColor!)
        : design?.primaryColor ?? bank?.primaryColor ?? scheme.primary;
    final secondaryColor = _card.customGradientEndColor != null
        ? Color(_card.customGradientEndColor!)
        : design?.secondaryColor ??
              bank?.secondaryColor ??
              scheme.primaryContainer;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _showShareBottomSheet,
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (value) {
              if (value == 'edit') _editCard();
              if (value == 'delete') _deleteCard();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit card'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: Text(
                    'Delete card',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: _buildCardWidget(
                      primaryColor,
                      secondaryColor,
                      design,
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _buildDetailsSection(),
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCardWidget(primaryColor, secondaryColor, design),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildDetailsSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardWidget(
    Color primaryColor,
    Color secondaryColor,
    CardDesign? design,
  ) {
    final bank = _card.bankId != null ? Banks.getById(_card.bankId!) : null;

    final textColor =
        design?.foregroundColor ??
        (_card.customBackgroundImagePath?.isNotEmpty == true
            ? CardContrast.ivory
            : CardContrast.bestForeground([primaryColor, secondaryColor]));

    final card = AspectRatio(
      aspectRatio: 1.586,
      child: CardBackgroundSurface(
        design: design,
        customGradientStartColor: _card.customGradientStartColor,
        customGradientEndColor: _card.customGradientEndColor,
        customGradientAngle: _card.customGradientAngle,
        customBackgroundImagePath: _card.customBackgroundImagePath,
        backgroundImageBlur: _card.backgroundImageBlur,
        fallbackPrimaryColor: primaryColor,
        fallbackSecondaryColor: secondaryColor,
        borderRadius: BorderRadius.circular(20),
        child: WalletCardFace(
          bank: bank,
          network: _network,
          categoryName: _card.categoryName,
          nickname: _card.cardNickname ?? '',
          cardNumber: _card.maskedCardNumber,
          cardholderName: _cardholderName ?? '—',
          // Mirrors the reveal state below, so the card face can never leak
          // the expiry date ahead of authentication.
          expiryDate: _isExpiryVisible
              ? (_expiryDate ?? CardData.hiddenExpiryDate)
              : CardData.hiddenExpiryDate,
          backgroundColor: primaryColor,
          foregroundColor: textColor,
        ),
      ),
    );

    final cardWithHero = _card.id == null || AppMotion.reduceMotion(context)
        ? card
        : WalletCardHero(tag: 'wallet-card-${_card.id}', child: card);
    final dragProgress = (_cardDragExtent / 360).clamp(0.0, 1.0);

    return Listener(
      key: const ValueKey('card-detail-swipe-target'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleCardPointerDown,
      onPointerMove: _handleCardPointerMove,
      onPointerUp: _handleCardPointerUp,
      onPointerCancel: _handleCardPointerCancel,
      child: AnimatedContainer(
        duration: _isDraggingCard
            ? Duration.zero
            : AppMotion.resolve(context, AppMotion.quick),
        curve: AppMotion.standardCurve,
        transformAlignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(0, _cardDragExtent, 0, 1)
          ..scaleByDouble(
            1 - (0.035 * dragProgress),
            1 - (0.035 * dragProgress),
            1,
            1,
          ),
        child: cardWithHero,
      ),
    );
  }

  Widget _buildDetailsSection() {
    final themeProvider = context.watch<ThemeProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEditableSectionHeader(
          title: 'Card Details',
          iconKey: const ValueKey('edit-card-details'),
          onEdit: () => _editCard(),
          textStyle: AppTypography.appBarTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 16),
        _buildDetailCard([
          _buildDetailRow(
            icon: Icons.credit_card,
            label: 'Card Number',
            value: _isCardNumberVisible ? null : _card.maskedCardNumber,
            futureValue: _isCardNumberVisible
                ? _card.getFormattedCardNumber()
                : null,
            isVisible: _isCardNumberVisible,
            onToggle: _toggleCardNumberVisibility,
            onCopy: _copyCardNumber,
          ),
          const Divider(height: 1),
          _buildDetailRow(
            icon: Icons.calendar_today,
            label: 'Expiry Date',
            value: _isExpiryVisible ? null : CardData.hiddenExpiryDate,
            futureValue: _isExpiryVisible
                ? _card.getDecryptedExpiryDate()
                : null,
            isVisible: _isExpiryVisible,
            onToggle: _toggleExpiryVisibility,
            onCopy: _copyExpiry,
          ),
          const Divider(height: 1),
          _buildDetailRow(
            icon: Icons.lock_outline,
            label: 'Security code',
            value: _isCvvVisible ? null : CardData.hiddenCvv,
            futureValue: _isCvvVisible ? _card.getDecryptedCvv() : null,
            isVisible: _isCvvVisible,
            onToggle: _toggleCvvVisibility,
            onCopy: _copyCvv,
          ),
        ]),
        _buildAdditionalInfoSection(),
      ],
    );
  }

  Widget _buildAdditionalInfoSection() {
    final themeProvider = context.watch<ThemeProvider>();
    final hasPhotos = _card.id != null && _card.attachmentIds.isNotEmpty;

    return FutureBuilder<List<String?>>(
      future: Future.wait([
        _card.getDecryptedAccountNumber(),
        _card.getDecryptedIfscCode(),
        _card.getDecryptedUpiId(),
      ]),
      builder: (context, snapshot) {
        final accountNumber = snapshot.data?[0];
        final ifscCode = snapshot.data?[1];
        final upiId = snapshot.data?[2];
        final notes = _card.notes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildEditableSectionHeader(
              title: 'Additional Information',
              iconKey: const ValueKey('edit-additional-information'),
              onEdit: () => _editCard(
                initialSection: CardEditInitialSection.additionalInformation,
              ),
              textStyle: AppTypography.sectionTitle(
                color: themeProvider.getPrimaryTextColor(),
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailCard([
              _buildInfoRowWithCopy(
                Icons.account_balance_wallet,
                'Account Number',
                (accountNumber == null || accountNumber.isEmpty)
                    ? 'Not set'
                    : accountNumber,
                allowCopy: accountNumber != null && accountNumber.isNotEmpty,
              ),
              const Divider(height: 24),
              _buildInfoRowWithCopy(
                Icons.code,
                'IFSC Code',
                (ifscCode == null || ifscCode.isEmpty) ? 'Not set' : ifscCode,
                allowCopy: ifscCode != null && ifscCode.isNotEmpty,
              ),
              const Divider(height: 24),
              _buildInfoRowWithCopy(
                Icons.qr_code,
                'UPI ID',
                (upiId == null || upiId.isEmpty) ? 'Not set' : upiId,
                allowCopy: upiId != null && upiId.isNotEmpty,
              ),
              const Divider(height: 24),
              _buildInfoRow(
                Icons.note,
                'Notes',
                (notes == null || notes.isEmpty) ? 'Not set' : notes,
              ),
            ]),
            if (hasPhotos)
              CardAttachmentsGallery(
                cardId: _card.id!,
                attachmentIds: _card.attachmentIds,
              ),
          ],
        );
      },
    );
  }

  Widget _buildEditableSectionHeader({
    required String title,
    required Key iconKey,
    required TextStyle textStyle,
    required VoidCallback onEdit,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: textStyle),
        const SizedBox(width: 4),
        IconButton(
          key: iconKey,
          tooltip: 'Edit card',
          visualDensity: VisualDensity.compact,
          iconSize: 19,
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }

  Widget _buildInfoRowWithCopy(
    IconData icon,
    String label,
    String value, {
    bool allowCopy = true,
  }) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption(
                  color: themeProvider.getSecondaryTextColor(),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.title(
                  color: themeProvider.getPrimaryTextColor(),
                ),
              ),
            ],
          ),
        ),
        if (allowCopy)
          IconButton(
            icon: Icon(
              Icons.copy,
              color: themeProvider.getSecondaryTextColor(),
              size: 20,
            ),
            onPressed: () => _copyToClipboard(value, label),
          ),
      ],
    );
  }

  Widget _buildDetailCard(List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    String? value,
    Future<String?>? futureValue,
    required bool isVisible,
    required VoidCallback onToggle,
    required VoidCallback onCopy,
  }) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: themeProvider.getSecondaryTextColor(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.caption(
                    color: themeProvider.getSecondaryTextColor(),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: AppMotion.resolve(context, AppMotion.quick),
                  child: futureValue != null
                      ? FutureBuilder<String?>(
                          key: ValueKey('visible-$label'),
                          future: futureValue,
                          builder: (context, snapshot) => Text(
                            snapshot.data ?? '…',
                            style: AppTypography.title(
                              color: themeProvider.getPrimaryTextColor(),
                            ),
                          ),
                        )
                      : Text(
                          value ?? '',
                          key: ValueKey('hidden-$label'),
                          style: AppTypography.title(
                            color: themeProvider.getPrimaryTextColor(),
                          ),
                        ),
                ),
              ],
            ),
          ),
          _buildCompactIconButton(
            icon: isVisible ? Icons.visibility_off : Icons.visibility,
            tooltip: isVisible ? 'Hide' : 'Show',
            onPressed: onToggle,
          ),
          _buildCompactIconButton(
            icon: Icons.copy,
            tooltip: 'Copy',
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final themeProvider = context.watch<ThemeProvider>();

    return IconButton(
      icon: Icon(icon, color: themeProvider.getSecondaryTextColor(), size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption(
                  color: themeProvider.getSecondaryTextColor(),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.title(
                  color: themeProvider.getPrimaryTextColor(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareBottomSheet extends StatefulWidget {
  final CardData card;

  const _ShareBottomSheet({required this.card});

  @override
  State<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<_ShareBottomSheet> {
  bool _shareCardNumber = false;
  bool _shareExpiry = false;
  bool _shareCvv = false;
  bool _shareCardholder = false;
  bool _shareAccountNumber = false;
  bool _shareIfscCode = false;
  bool _shareUpiId = false;
  bool _isLoading = false;
  bool _isExportingFile = false;

  Future<bool> _authorize(ProtectedAction action, String reason) async {
    final authentication =
        context.read<AuthenticationCoordinator?>() ??
        AuthenticationCoordinator();
    final authenticated = await authentication.authorize(
      action,
      reason: reason,
    );
    if (!authenticated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authentication.lastErrorMessage ?? 'Authentication required',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return authenticated;
  }

  /// Shares the whole card as an encrypted `.cwbak` file: every field, the
  /// notes and the photos, so the recipient can import it as a real card.
  Future<void> _shareCardFile() async {
    final authenticated = await _authorize(
      ProtectedAction.exportCard,
      'Authenticate to export this card as an encrypted file',
    );
    if (!authenticated || !mounted) return;

    final password = await promptBackupPassword(
      context,
      title: 'Share Card File',
      confirmLabel: 'Share',
      requireConfirm: true,
      description:
          'This file carries every detail of the card, including notes and photos. '
          'Choose a password and share it separately — the other person needs it to import the card.',
    );
    if (password == null || !mounted) return;

    setState(() => _isExportingFile = true);

    try {
      final filePath = await SecureCardStorage().exportSingleCard(
        widget.card,
        password,
      );

      if (mounted) {
        Navigator.pop(context);
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Card from CardVault',
          text: 'Import this file in CardVault under Settings > Import Backup.',
        );
        AppLogService.instance.action(
          'Card sharing',
          'Encrypted card share sheet opened',
        );
      }
    } catch (error) {
      AppLogService.instance.record(
        'Card sharing',
        'Encrypted card export failed: $error',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('The encrypted card file could not be shared.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingFile = false);
    }
  }

  Future<void> _shareDetails() async {
    if (!_shareCardNumber &&
        !_shareExpiry &&
        !_shareCvv &&
        !_shareCardholder &&
        !_shareAccountNumber &&
        !_shareIfscCode &&
        !_shareUpiId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one detail to share'),
        ),
      );
      return;
    }

    final authenticated = await _authorize(
      ProtectedAction.shareCardDetails,
      'Authenticate to share the selected protected card details',
    );
    if (!authenticated || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final List<String> details = [];
      final bank = widget.card.bankId != null
          ? Banks.getById(widget.card.bankId!)
          : null;

      if (bank != null) {
        details.add('Bank: ${bank.name}');
      }

      if (_shareCardholder) {
        final name = await widget.card.getDecryptedCardholderName();
        if (name != null) details.add('Name: $name');
      }

      if (_shareCardNumber) {
        final number = await widget.card.getDecryptedCardNumber();
        final formatted = _formatCardNumber(number);
        details.add('Card Number: $formatted');
      }

      if (_shareExpiry) {
        final expiry = await widget.card.getDecryptedExpiryDate();
        details.add('Expiry: $expiry');
      }

      if (_shareCvv) {
        final cvv = await widget.card.getDecryptedCvv();
        if (cvv != null) details.add('CVV: $cvv');
      }

      if (_shareAccountNumber) {
        final account = await widget.card.getDecryptedAccountNumber();
        if (account != null) details.add('Account Number: $account');
      }

      if (_shareIfscCode) {
        final ifsc = await widget.card.getDecryptedIfscCode();
        if (ifsc != null) details.add('IFSC Code: $ifsc');
      }

      if (_shareUpiId) {
        final upi = await widget.card.getDecryptedUpiId();
        if (upi != null) details.add('UPI ID: $upi');
      }

      final shareText = details.join('\n');

      if (mounted) {
        Navigator.pop(context);
        await Share.share(shareText, subject: 'Card Details');
        AppLogService.instance.action(
          'Card sharing',
          'Protected-details share sheet opened',
          details: {'fieldCount': details.length},
        );
      }
    } catch (error) {
      AppLogService.instance.record(
        'Card sharing',
        'Protected-details sharing failed: $error',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'The selected card details could not be shared.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCardNumber(String number) {
    if (number.length >= 16) {
      return '${number.substring(0, 4)} ${number.substring(4, 8)} ${number.substring(8, 12)} ${number.substring(12)}';
    }
    return number;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Share Card Details',
              style: AppTypography.pageTitle(color: scheme.onSurface)
                  .copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Select the details you want to share',
              style: AppTypography.subtitle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _buildShareOption(
              'Card Number',
              Icons.credit_card,
              _shareCardNumber,
              (value) => setState(() => _shareCardNumber = value ?? false),
            ),
            _buildShareOption(
              'Expiry Date',
              Icons.calendar_today,
              _shareExpiry,
              (value) => setState(() => _shareExpiry = value ?? false),
            ),
            _buildShareOption(
              'CVV',
              Icons.lock_outline,
              _shareCvv,
              (value) => setState(() => _shareCvv = value ?? false),
            ),
            _buildShareOption(
              'Cardholder Name',
              Icons.person_outline,
              _shareCardholder,
              (value) => setState(() => _shareCardholder = value ?? false),
            ),
            FutureBuilder<String?>(
              future: widget.card.getDecryptedAccountNumber(),
              builder: (context, snapshot) {
                if (snapshot.data == null) return const SizedBox.shrink();
                return _buildShareOption(
                  'Account Number',
                  Icons.account_balance_wallet,
                  _shareAccountNumber,
                  (value) =>
                      setState(() => _shareAccountNumber = value ?? false),
                );
              },
            ),
            FutureBuilder<String?>(
              future: widget.card.getDecryptedIfscCode(),
              builder: (context, snapshot) {
                if (snapshot.data == null) return const SizedBox.shrink();
                return _buildShareOption(
                  'IFSC Code',
                  Icons.code,
                  _shareIfscCode,
                  (value) => setState(() => _shareIfscCode = value ?? false),
                );
              },
            ),
            FutureBuilder<String?>(
              future: widget.card.getDecryptedUpiId(),
              builder: (context, snapshot) {
                if (snapshot.data == null) return const SizedBox.shrink();
                return _buildShareOption(
                  'UPI ID',
                  Icons.qr_code,
                  _shareUpiId,
                  (value) => setState(() => _shareUpiId = value ?? false),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _shareDetails,
                icon: _isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: scheme.onPrimary,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.share_outlined),
                label: const Text('Share selected details'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: _isExportingFile ? null : _shareCardFile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.primary,
                ),
                child: _isExportingFile
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: scheme.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.ios_share, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Share Full Card File',
                            style: AppTypography.button(
                              fontSize: 16,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sends an encrypted file with all details, notes and photos that the '
              'recipient can import into CardVault.',
              style: AppTypography.caption(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareOption(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: AppTypography.listItem(color: scheme.onSurface)),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      activeColor: scheme.primary,
    );
  }
}
