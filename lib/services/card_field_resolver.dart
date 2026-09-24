import 'dart:math';

class NormalizedTextBox {
  final double left;
  final double top;
  final double width;
  final double height;

  const NormalizedTextBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get centerY => top + (height / 2);
  double get centerX => left + (width / 2);
  double get right => left + width;
  double get bottom => top + height;
}

/// A single line observed by an on-device recognizer.
///
/// Keeping the text and its geometry together lets the resolver distinguish a
/// probable cardholder name from issuer and product labels without relying on
/// fixed card-layout rectangles.
class CardTextObservation {
  final String text;
  final int frameIndex;
  final String? sourceId;
  final bool isComposite;
  final double recognizerConfidence;
  final NormalizedTextBox? box;

  const CardTextObservation({
    required this.text,
    required this.frameIndex,
    this.sourceId,
    this.isComposite = false,
    required this.recognizerConfidence,
    this.box,
  });
}

class ResolvedCardField {
  final String? value;
  final double confidence;
  final int supportingFrames;
  final bool isAmbiguous;
  final String? sourceId;

  const ResolvedCardField({
    required this.value,
    required this.confidence,
    required this.supportingFrames,
    this.isAmbiguous = false,
    this.sourceId,
  });

  bool get needsReview => value == null || isAmbiguous || confidence < 0.82;
}

class CardFieldResolution {
  final ResolvedCardField cardNumber;
  final ResolvedCardField expiryDate;
  final ResolvedCardField cardholderName;

  const CardFieldResolution({
    required this.cardNumber,
    required this.expiryDate,
    required this.cardholderName,
  });
}

class CardFieldResolver {
  static final RegExp _issuerOrProductWords = RegExp(
    r'\b(VISA|MASTERCARD|MASTER\s*CARD|AMEX|AMERICAN\s*EXPRESS|DISCOVER|RUPAY|MAESTRO|UNIONPAY|JCB|DINERS|DEBIT|CREDIT|CARD|BANK|VALID|THRU|THROUGH|EXPIRES?|EXPIRY|MEMBER|SINCE|PLATINUM|GOLD|SILVER|CLASSIC|SIGNATURE|INFINITE|WORLD|ELITE|REWARDS?|POINTS?|CASHBACK|CONTACTLESS|INTERNATIONAL|ISSUED|ISSUER|DESIGNED|AUTHORIZED|SECURITY|CODE|CUSTOMER|PROPERTY)\b',
    caseSensitive: false,
  );

  CardFieldResolution resolve(
    List<CardTextObservation> observations, {
    int minimumPanSupportingFrames = 1,
  }) {
    final panCandidates = <String, _CandidateAggregate>{};
    final expiryCandidates = <String, _CandidateAggregate>{};
    final nameCandidates = <String, _CandidateAggregate>{};

    for (final observation in observations) {
      _collectPanCandidates(observation, panCandidates);
      _collectExpiryCandidates(observation, expiryCandidates);
      _collectNameCandidates(observation, nameCandidates);
    }
    _collectSplitPanCandidates(observations, panCandidates);

    return CardFieldResolution(
      cardNumber: _best(
        panCandidates,
        minimumSupportingFrames: minimumPanSupportingFrames,
      ),
      expiryDate: _best(expiryCandidates),
      cardholderName: _best(nameCandidates),
    );
  }

  /// Payment cards sometimes print the PAN as four stacked groups instead of
  /// one horizontal line. ML Kit correctly returns those groups as separate
  /// observations, so join geometrically adjacent digit groups before Luhn
  /// validation rather than treating them as unrelated text.
  void _collectSplitPanCandidates(
    List<CardTextObservation> observations,
    Map<String, _CandidateAggregate> output,
  ) {
    final bySource = <({int frameIndex, String sourceId}), List<_DigitGroup>>{};
    for (final observation in observations) {
      if (observation.isComposite) continue;
      final box = observation.box;
      if (box == null) continue;
      final digits = _standaloneDigitGroup(observation.text);
      if (digits == null) continue;
      final key = (
        frameIndex: observation.frameIndex,
        sourceId: observation.sourceId ?? 'frame-${observation.frameIndex}',
      );
      bySource
          .putIfAbsent(key, () => <_DigitGroup>[])
          .add(_DigitGroup(digits: digits, observation: observation));
    }

    for (final entry in bySource.entries) {
      _collectAlignedPanRuns(
        entry.value,
        entry.key.frameIndex,
        output,
        vertical: true,
      );
      _collectAlignedPanRuns(
        entry.value,
        entry.key.frameIndex,
        output,
        vertical: false,
      );
    }
  }

  String? _standaloneDigitGroup(String text) {
    final corrected = _correctDigitLikeCharacters(text.trim());
    if (!RegExp(r'^[0-9\s-]+$').hasMatch(corrected)) return null;
    final digits = corrected.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 4 && digits.length <= 8 ? digits : null;
  }

  void _collectAlignedPanRuns(
    List<_DigitGroup> groups,
    int frameIndex,
    Map<String, _CandidateAggregate> output, {
    required bool vertical,
  }) {
    final ordered = List<_DigitGroup>.from(groups)
      ..sort(
        (a, b) => vertical
            ? a.box.top.compareTo(b.box.top)
            : a.box.left.compareTo(b.box.left),
      );

    for (var start = 0; start < ordered.length; start++) {
      var digits = ordered[start].digits;
      var confidence = ordered[start].observation.recognizerConfidence;
      var count = 1;
      var previous = ordered[start];

      for (
        var index = start + 1;
        index < ordered.length && count < 5;
        index++
      ) {
        final next = ordered[index];
        if (!_areAdjacent(previous.box, next.box, vertical: vertical)) continue;

        digits += next.digits;
        confidence += next.observation.recognizerConfidence;
        count++;
        previous = next;

        if (digits.length > 19) break;
        if (digits.length < 13 || !_isValidLuhn(digits)) continue;

        final averageConfidence = confidence / count;
        var score = averageConfidence * 0.62 + 0.25;
        if (digits.length == 15 || digits.length == 16) score += 0.05;
        if (count >= 3) score += 0.03;
        _add(
          output,
          digits,
          score,
          frameIndex,
          sourceId: ordered[start].observation.sourceId,
        );
      }
    }
  }

  bool _areAdjacent(
    NormalizedTextBox previous,
    NormalizedTextBox next, {
    required bool vertical,
  }) {
    if (vertical) {
      final centerTolerance = max(previous.width, next.width) * 0.8 + 0.015;
      final gap = next.top - previous.bottom;
      return (next.centerX - previous.centerX).abs() <= centerTolerance &&
          gap >= -0.025 &&
          gap <= 0.14;
    }

    final centerTolerance = max(previous.height, next.height) * 0.9 + 0.01;
    final gap = next.left - previous.right;
    return (next.centerY - previous.centerY).abs() <= centerTolerance &&
        gap >= -0.035 &&
        gap <= 0.14;
  }

  void _collectPanCandidates(
    CardTextObservation observation,
    Map<String, _CandidateAggregate> output,
  ) {
    // ML Kit block text can reorder lines for unconventional/vertical card
    // layouts. Only line observations may directly produce a PAN; split lines
    // are reconstructed using geometry within one preprocessing source.
    if (observation.isComposite) return;
    final original = observation.text.trim();
    if (original.isEmpty) return;

    final corrected = _correctDigitLikeCharacters(original);
    final runs = RegExp(r'[0-9][0-9\s\-]{11,27}[0-9]').allMatches(corrected);

    for (final match in runs) {
      final raw = match.group(0)!;
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      for (final candidate in _validPanWindows(digits)) {
        var score = observation.recognizerConfidence * 0.62 + 0.25;
        if (RegExp(r'[\s\-]').hasMatch(raw)) score += 0.06;
        if (candidate.length == 15 || candidate.length == 16) score += 0.04;
        final centerY = observation.box?.centerY;
        if (centerY != null && centerY >= 0.25 && centerY <= 0.82) {
          score += 0.03;
        }
        _add(
          output,
          candidate,
          score,
          observation.frameIndex,
          sourceId: observation.sourceId,
        );
      }
    }
  }

  Iterable<String> _validPanWindows(String digits) sync* {
    if (digits.length >= 13 && digits.length <= 19 && _isValidLuhn(digits)) {
      yield digits;
      return;
    }

    if (digits.length <= 19) return;
    final seen = <String>{};
    for (var length = 19; length >= 13; length--) {
      for (var start = 0; start + length <= digits.length; start++) {
        final candidate = digits.substring(start, start + length);
        if (seen.add(candidate) && _isValidLuhn(candidate)) yield candidate;
      }
    }
  }

  void _collectExpiryCandidates(
    CardTextObservation observation,
    Map<String, _CandidateAggregate> output,
  ) {
    final original = observation.text.trim();
    if (original.isEmpty) return;
    final corrected = _correctDigitLikeCharacters(original);
    final hasLabel = RegExp(
      r'VALID\s*(?:THRU|THROUGH)?|EXP(?:IRY|IRES?)?|GOOD\s*THRU',
      caseSensitive: false,
    ).hasMatch(original);

    final patterns = <RegExp>[
      RegExp(
        r'(?:^|[^0-9])(0[1-9]|1[0-2])\s*[/\-]\s*(?:20)?([0-9]{2})(?:[^0-9]|$)',
      ),
      if (hasLabel)
        RegExp(r'(?:^|[^0-9])(0[1-9]|1[0-2])\s*(?:20)?([0-9]{2})(?:[^0-9]|$)'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(corrected)) {
        final month = match.group(1)!;
        final year = match.group(2)!;
        if (!_isPlausibleExpiry(month, year)) continue;

        var score = observation.recognizerConfidence * 0.58 + 0.18;
        if (hasLabel) score += 0.12;
        if (RegExp(r'[/\-]').hasMatch(match.group(0)!)) score += 0.07;
        final centerY = observation.box?.centerY;
        if (centerY != null && centerY >= 0.35 && centerY <= 0.9) {
          score += 0.03;
        }
        _add(
          output,
          '$month/$year',
          score,
          observation.frameIndex,
          sourceId: observation.sourceId,
        );
      }
    }
  }

  void _collectNameCandidates(
    CardTextObservation observation,
    Map<String, _CandidateAggregate> output,
  ) {
    var value = observation.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r"[^A-Z .'-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.length < 5 || value.length > 34) return;
    if (_issuerOrProductWords.hasMatch(value)) return;

    final words = value.split(' ');
    if (words.length < 2 || words.length > 5) return;
    if (!words.every(
      (word) => word.replaceAll(RegExp(r"[.'-]"), '').length >= 2,
    )) {
      return;
    }

    var score = observation.recognizerConfidence * 0.55 + 0.15;
    final centerY = observation.box?.centerY;
    if (centerY != null && centerY >= 0.52) score += 0.1;
    if (words.length == 2 || words.length == 3) score += 0.05;
    _add(
      output,
      value,
      score,
      observation.frameIndex,
      sourceId: observation.sourceId,
    );
  }

  void _add(
    Map<String, _CandidateAggregate> output,
    String value,
    double score,
    int frameIndex, {
    String? sourceId,
  }) {
    output
        .putIfAbsent(value, () => _CandidateAggregate())
        .add(score.clamp(0, 0.99), frameIndex, sourceId: sourceId);
  }

  ResolvedCardField _best(
    Map<String, _CandidateAggregate> candidates, {
    int minimumSupportingFrames = 1,
  }) {
    if (candidates.isEmpty) {
      return const ResolvedCardField(
        value: null,
        confidence: 0,
        supportingFrames: 0,
      );
    }

    final allRanked = candidates.entries.toList()
      ..sort((a, b) => b.value.confidence.compareTo(a.value.confidence));
    final ranked = allRanked
        .where((entry) => entry.value.frames.length >= minimumSupportingFrames)
        .toList();
    if (ranked.isEmpty) {
      final strongest = allRanked.first;
      return ResolvedCardField(
        value: null,
        confidence: strongest.value.confidence,
        supportingFrames: strongest.value.frames.length,
        sourceId: strongest.value.bestSourceId,
      );
    }

    final best = ranked.first;
    final isAmbiguous =
        ranked.length > 1 &&
        ranked[1].value.confidence >= best.value.confidence - 0.06;
    return ResolvedCardField(
      value: isAmbiguous ? null : best.key,
      confidence: best.value.confidence,
      supportingFrames: best.value.frames.length,
      isAmbiguous: isAmbiguous,
      sourceId: best.value.bestSourceId,
    );
  }

  static String _correctDigitLikeCharacters(String value) {
    return value
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('I', '1')
        .replaceAll('i', '1')
        .replaceAll('l', '1')
        .replaceAll('|', '1')
        .replaceAll('S', '5')
        .replaceAll('s', '5')
        .replaceAll('B', '8')
        .replaceAll('b', '8')
        .replaceAll('G', '6')
        .replaceAll('g', '9')
        .replaceAll('Z', '2')
        .replaceAll('z', '2');
  }

  static bool _isPlausibleExpiry(String month, String year) {
    final monthValue = int.tryParse(month) ?? 0;
    final yearValue = int.tryParse(year) ?? -1;
    if (monthValue < 1 || monthValue > 12 || yearValue < 0) return false;

    final now = DateTime.now();
    final currentYear = now.year % 100;
    if (yearValue < currentYear || yearValue > currentYear + 15) return false;
    return yearValue != currentYear || monthValue >= now.month;
  }

  static bool _isValidLuhn(String cardNumber) {
    if (cardNumber.length < 13 || cardNumber.length > 19) return false;
    var sum = 0;
    var doubleDigit = false;
    for (var index = cardNumber.length - 1; index >= 0; index--) {
      var digit = int.tryParse(cardNumber[index]);
      if (digit == null) return false;
      if (doubleDigit) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      doubleDigit = !doubleDigit;
    }
    return sum % 10 == 0;
  }
}

class _CandidateAggregate {
  double bestScore = 0;
  String? bestSourceId;
  int evidenceCount = 0;
  final Set<int> frames = <int>{};

  void add(double score, int frameIndex, {String? sourceId}) {
    if (score > bestScore) {
      bestScore = score;
      bestSourceId = sourceId;
    }
    evidenceCount++;
    frames.add(frameIndex);
  }

  double get confidence {
    final frameBonus = ((frames.length - 1) * 0.08).clamp(0, 0.16);
    final extraEvidence = (evidenceCount - frames.length).clamp(0, 3);
    final evidenceBonus = extraEvidence * 0.015;
    return (bestScore + frameBonus + evidenceBonus).clamp(0, 0.99);
  }
}

class _DigitGroup {
  final String digits;
  final CardTextObservation observation;

  const _DigitGroup({required this.digits, required this.observation});

  NormalizedTextBox get box => observation.box!;
}
