import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import '../models/card_data.dart';
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';
import 'bank_logo.dart';
import 'card_tiles_grid.dart';

const _tileAspectRatio = 1.586;
const _tileSpacing = 12.0;

/// Larger than [_tileSpacing] because each tile ends in a title label, so rows
/// need extra room to keep a label off the card below it.
const _rowSpacing = 20.0;

/// Vertical room each card behind the front one takes up, and how many of them
/// are drawn. Peeking layers are what make a stack read as a stack at a glance.
const _peekOffset = 9.0;
const _maxPeekLayers = 2;

/// A set of cards that share a value on the current grouping axis.
class CardStack {
  final String key;
  final String title;
  final List<CardData> cards;

  /// Set when the stack represents a bank, so the caption can carry its logo.
  final String? bankId;

  /// Set when the stack represents a custom group, which is what makes it a
  /// drop target that cards can be added to.
  final String? groupId;

  /// Set when the stack represents something with no logo of its own, such as
  /// a card category.
  final IconData? icon;

  const CardStack({
    required this.key,
    required this.title,
    required this.cards,
    this.bankId,
    this.groupId,
    this.icon,
  });

  bool get isSingle => cards.length == 1;
  bool get hasLeading => bankId != null || icon != null;

  /// A single card belonging to no group. Distinguishing these from a group
  /// that happens to hold one card is what lets a drag create a new group
  /// without silently pulling a card out of an existing one.
  bool get isLooseCard => groupId == null && cards.length == 1;
}

/// A grid of card stacks. Tapping a stack opens its member cards in a dialog;
/// tapping a single-card stack opens that card directly.
class StackedCardGrid extends StatefulWidget {
  final List<CardStack> stacks;

  /// Identifies the grouping the [stacks] were built from. When it changes the
  /// grid replays its regroup animation instead of cutting to the new layout.
  final String axisKey;

  /// Enables long-press dragging a loose card onto another tile to group them.
  /// Only meaningful on the custom axis, where stacks map to real groups.
  final bool canGroupByDrag;

  final ValueChanged<CardData>? onCardTap;
  final ValueChanged<CardData>? onCardLongPress;

  /// A loose card was dropped onto [target]. Adding to an existing group and
  /// creating a new one are both the caller's business.
  final void Function(CardData card, CardStack target)? onDropOnStack;

  const StackedCardGrid({
    super.key,
    required this.stacks,
    required this.axisKey,
    this.canGroupByDrag = false,
    this.onCardTap,
    this.onCardLongPress,
    this.onDropOnStack,
  });

  @override
  State<StackedCardGrid> createState() => _StackedCardGridState();
}

class _StackedCardGridState extends State<StackedCardGrid> {
  /// Lives for the duration of one drag, so a drag that reaches the top or
  /// bottom edge can scroll the grid to tiles that are off screen.
  EdgeDraggingAutoScroller? _autoScroller;

  void _onDragStarted(BuildContext tileContext) {
    final scrollable = Scrollable.maybeOf(tileContext);
    if (scrollable == null) return;
    _autoScroller = EdgeDraggingAutoScroller(scrollable, velocityScalar: 50);
  }

  void _onDragUpdate(DragUpdateDetails details, Size tileSize) {
    _autoScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(
        center: details.globalPosition,
        width: tileSize.width,
        height: tileSize.height,
      ),
    );
  }

  void _onDragEnded() {
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
  }

  Future<void> _onStackTap(CardStack stack) async {
    if (stack.isSingle) {
      widget.onCardTap?.call(stack.cards.first);
      return;
    }

    final action = await showDialog<_StackAction>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: _StackDialog(stack: stack),
      ),
    );

    if (action == null) return;
    if (action.isLongPress) {
      widget.onCardLongPress?.call(action.card);
    } else {
      widget.onCardTap?.call(action.card);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keying on the axis rebuilds the subtree from scratch when the grouping
    // changes, which is what restarts the per-tile entry animations.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(widget.axisKey),
        child: _buildGrid(),
      ),
    );
  }

  Widget _buildGrid() {
    final rows = <List<CardStack>>[];
    for (var i = 0; i < widget.stacks.length; i += 2) {
      rows.add(widget.stacks.sublist(
        i,
        i + 2 > widget.stacks.length ? widget.stacks.length : i + 2,
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 0 ? _tileSpacing : 0),
                      child: i < rows[rowIndex].length
                          ? _RegroupEntry(
                              key: ValueKey(rows[rowIndex][i].key),
                              index: rowIndex * 2 + i,
                              child: _StackTile(
                                stack: rows[rowIndex][i],
                                onTap: () => _onStackTap(rows[rowIndex][i]),
                                onCardLongPress: widget.onCardLongPress,
                                canGroupByDrag: widget.canGroupByDrag,
                                onDropOnStack: widget.onDropOnStack,
                                onDragStarted: _onDragStarted,
                                onDragUpdate: _onDragUpdate,
                                onDragEnded: _onDragEnded,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: _rowSpacing),
          ],
        ],
      ),
    );
  }
}

/// Settles one stack into place after a regroup. Tiles start slightly low,
/// small and transparent and arrive in reading order, so switching the grouping
/// reads as the cards rearranging rather than the grid cutting to a new layout.
class _RegroupEntry extends StatefulWidget {
  final int index;
  final Widget child;

  const _RegroupEntry({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<_RegroupEntry> createState() => _RegroupEntryState();
}

class _RegroupEntryState extends State<_RegroupEntry>
    with SingleTickerProviderStateMixin {
  static const _stagger = Duration(milliseconds: 30);

  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 260),
    vsync: this,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _startTimer = Timer(_stagger * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) {
        final t = _animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: Transform.scale(
              scale: 0.95 + t * 0.05,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// What the user picked inside [_StackDialog], handled once the dialog is gone
/// so the card screen or group sheet doesn't open behind it.
class _StackAction {
  final CardData card;
  final bool isLongPress;

  const _StackAction(this.card, {this.isLongPress = false});
}

/// The member cards of a stack, shown over a dimmed and blurred backdrop.
class _StackDialog extends StatelessWidget {
  final CardStack stack;

  const _StackDialog({required this.stack});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        decoration: BoxDecoration(
          color: themeProvider.getCardColor(),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (stack.hasLeading) ...[
                  _StackLeading(stack: stack, size: 22),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    stack.title,
                    style: AppTypography.sectionTitle(
                      color: themeProvider.getPrimaryTextColor(),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${stack.cards.length} cards',
                  style: AppTypography.caption(
                    color: themeProvider.getSecondaryTextColor(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: themeProvider.getSecondaryTextColor(),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: stack.cards.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: _tileSpacing,
                  mainAxisSpacing: _tileSpacing,
                  childAspectRatio: _tileAspectRatio,
                ),
                itemBuilder: (context, index) => CardTile(
                  card: stack.cards[index],
                  onTap: (card) => Navigator.pop(context, _StackAction(card)),
                  onLongPress: (card) => Navigator.pop(
                    context,
                    _StackAction(card, isLongPress: true),
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

/// The bank logo or category icon that identifies a stack.
class _StackLeading extends StatelessWidget {
  final CardStack stack;
  final double size;

  const _StackLeading({required this.stack, required this.size});

  @override
  Widget build(BuildContext context) {
    if (stack.bankId != null) {
      final bank = Banks.getById(stack.bankId!);
      if (bank != null) {
        return BankLogo(bank: bank, size: size, maxWidth: size);
      }
    }
    if (stack.icon != null) {
      return Icon(
        stack.icon,
        size: size,
        color: context.watch<ThemeProvider>().getSecondaryTextColor(),
      );
    }
    return const SizedBox.shrink();
  }
}

class _StackTile extends StatelessWidget {
  final CardStack stack;
  final VoidCallback onTap;
  final ValueChanged<CardData>? onCardLongPress;
  final bool canGroupByDrag;
  final void Function(CardData card, CardStack target)? onDropOnStack;
  final ValueChanged<BuildContext>? onDragStarted;
  final void Function(DragUpdateDetails details, Size tileSize)? onDragUpdate;
  final VoidCallback? onDragEnded;

  const _StackTile({
    required this.stack,
    required this.onTap,
    this.onCardLongPress,
    this.canGroupByDrag = false,
    this.onDropOnStack,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnded,
  });

  bool get _isDragSource => canGroupByDrag && stack.isLooseCard;

  @override
  Widget build(BuildContext context) {
    if (!canGroupByDrag) return _buildTile(context, isDropTarget: false);

    return DragTarget<CardData>(
      onWillAcceptWithDetails: (details) {
        // A card cannot be dropped onto the tile it came from.
        if (stack.cards.any((card) => card.id == details.data.id)) return false;
        HapticFeedback.selectionClick();
        return true;
      },
      onAcceptWithDetails: (details) =>
          onDropOnStack?.call(details.data, stack),
      builder: (context, candidateData, rejectedData) =>
          _buildTile(context, isDropTarget: candidateData.isNotEmpty),
    );
  }

  Widget _buildTile(BuildContext context, {required bool isDropTarget}) {
    final themeProvider = context.watch<ThemeProvider>();
    final peekLayers =
        (stack.cards.length - 1).clamp(0, _maxPeekLayers).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight = constraints.maxWidth / _tileAspectRatio;
            final cardSize = Size(constraints.maxWidth, cardHeight);

            return SizedBox(
              height: cardHeight + peekLayers * _peekOffset,
              child: Stack(
                children: [
                  // Drawn back to front so the real card sits on top. Each layer
                  // is only tall enough to cover the sliver that shows above the
                  // front card, which keeps the blur off a full card of pixels.
                  for (var layer = peekLayers; layer >= 1; layer--)
                    Positioned(
                      top: (peekLayers - layer) * _peekOffset,
                      left: layer * 6.0,
                      right: layer * 6.0,
                      height:
                          (layer * _peekOffset + 24).clamp(0.0, cardHeight),
                      child: _PeekLayer(
                        card: stack.cards[layer],
                        depth: layer,
                      ),
                    ),
                  Positioned(
                    top: peekLayers * _peekOffset,
                    left: 0,
                    right: 0,
                    height: cardHeight,
                    child: _buildFrontCard(context, cardSize: cardSize),
                  ),
                  if (isDropTarget)
                    Positioned(
                      top: peekLayers * _peekOffset,
                      left: 0,
                      right: 0,
                      height: cardHeight,
                      child: IgnorePointer(
                        child: _DropHighlight(
                          color: themeProvider.getPrimaryColor(),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (stack.hasLeading) ...[
              _StackLeading(stack: stack, size: 16),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                stack.title,
                style: AppTypography.label(
                  fontSize: 12,
                  color: themeProvider.getPrimaryTextColor(),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!stack.isSingle) ...[
              const SizedBox(width: 6),
              Text(
                '${stack.cards.length}',
                style: AppTypography.overline(
                  color: themeProvider.getSecondaryTextColor(),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: themeProvider.getSecondaryTextColor(),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The front card of the stack, made draggable when it is a loose card. Long
  /// press is the drag gesture there, so the group picker it would otherwise
  /// open stays reachable from inside the stack dialog instead.
  Widget _buildFrontCard(BuildContext context, {required Size cardSize}) {
    final card = stack.cards.first;
    final tile = CardTile(
      card: card,
      onTap: (_) => onTap(),
      onLongPress: _isDragSource
          ? null
          : (stack.isSingle ? onCardLongPress : null),
    );

    if (!_isDragSource) return tile;

    return LongPressDraggable<CardData>(
      data: card,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        HapticFeedback.mediumImpact();
        onDragStarted?.call(context);
      },
      onDragUpdate: (details) => onDragUpdate?.call(details, cardSize),
      onDragEnd: (_) => onDragEnded?.call(),
      onDraggableCanceled: (_, __) => onDragEnded?.call(),
      feedback: _DragFeedback(card: card, size: cardSize),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}

/// The lifted card that follows the finger during a drag. Centred under the
/// pointer via [pointerDragAnchorStrategy], since the grab point on the card
/// carries no meaning here.
class _DragFeedback extends StatelessWidget {
  final CardData card;
  final Size size;

  const _DragFeedback({required this.card, required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(-size.width / 2, -size.height / 2),
      child: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.06,
          child: Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.32),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: CardTile(card: card),
          ),
        ),
      ),
    );
  }
}

/// Ring drawn over the tile a card is hovering on, so it is obvious which tile
/// will take the drop.
class _DropHighlight extends StatelessWidget {
  final Color color;

  const _DropHighlight({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 2.5),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const Icon(Icons.add, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// A card peeking out from behind the front of a stack. Only the silhouette and
/// colours matter here, so it deliberately renders no card content.
///
/// [depth] is how many cards back this one sits; layers further back are blurred
/// and faded more, so the stack reads as having depth rather than being a set of
/// flat offset rectangles.
class _PeekLayer extends StatelessWidget {
  final CardData card;
  final int depth;

  const _PeekLayer({required this.card, required this.depth});

  @override
  Widget build(BuildContext context) {
    final bank = card.bankId != null ? Banks.getById(card.bankId!) : null;
    final design =
        card.designId != null ? CardDesigns.getById(card.designId!) : null;
    final primaryColor =
        design?.primaryColor ?? bank?.primaryColor ?? Colors.grey.shade600;
    final secondaryColor =
        design?.secondaryColor ?? bank?.secondaryColor ?? Colors.grey.shade700;

    final sigma = depth * 1.1;

    return Opacity(
      opacity: (1 - depth * 0.12).clamp(0.0, 1.0),
      child: ImageFiltered(
        // decal keeps the blur from sampling the transparent surround and
        // washing the card's edges into the background.
        imageFilter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primaryColor, secondaryColor],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
