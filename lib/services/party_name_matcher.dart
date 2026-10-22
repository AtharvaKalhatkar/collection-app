import '../models/shop_model.dart';
import '../utils/marathi_search_helper.dart';

class ShopMatchResult {
  final ShopModel shop;
  final double score; // 0.0 to 1.0
  final String matchedExplanation;

  const ShopMatchResult({
    required this.shop,
    required this.score,
    required this.matchedExplanation,
  });
}

class PartyNameMatcher {
  // Common billing noise words to filter out when matching customer names
  static final RegExp _noiseWordsRegExp = RegExp(
    r'\b(m/s|ms|messrs|to|customer|cust|party|buyer|consignee|client|name|prop|proprietor|shri|shree|mr|mrs|c/o|gstin|gst|ph|mob|phone|bill|inv|tax|invoice|cash|credit|memo)\b',
    caseSensitive: false,
  );

  /// Cleans English party name from bill text
  static String cleanPartyName(String raw) {
    var cleaned = raw
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .trim();

    // Remove noise words
    cleaned = cleaned.replaceAll(_noiseWordsRegExp, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  /// Matches extracted English party name against a list of shops (which may be in Marathi or English)
  static ShopMatchResult? findBestMatch({
    required String rawExtractedName,
    required List<ShopModel> candidateShops,
  }) {
    if (candidateShops.isEmpty) return null;

    final cleanedQuery = cleanPartyName(rawExtractedName);
    if (cleanedQuery.isEmpty) return null;

    final queryTokens = cleanedQuery
        .toLowerCase()
        .split(' ')
        .where((t) => t.length >= 2)
        .toList();

    if (queryTokens.isEmpty) return null;

    final List<ShopMatchResult> results = [];

    for (final shop in candidateShops) {
      double score = 0.0;
      final matchedReasons = <String>[];

      // 1. Direct contains check
      final shopNameLower = shop.name.toLowerCase();
      if (shopNameLower.contains(cleanedQuery.toLowerCase())) {
        score += 0.85;
        matchedReasons.add('Exact name contains');
      }

      // 2. Transliterated Marathi -> Latin phonetic representation
      final latinPhonetic = MarathiSearchHelper.toLatinPhonetic(shop.name);
      final normLatin = MarathiSearchHelper.normalize(latinPhonetic);
      final normQuery = MarathiSearchHelper.normalize(cleanedQuery);

      if (normLatin.contains(normQuery) || normQuery.contains(normLatin)) {
        score += 0.80;
        matchedReasons.add('Phonetic match');
      }

      // 3. Token-by-token comparison
      int matchedTokens = 0;
      for (final qToken in queryTokens) {
        final normQToken = MarathiSearchHelper.normalize(qToken);

        // Check against Marathi Search Helper matches
        if (MarathiSearchHelper.matches(shop.name, qToken)) {
          matchedTokens++;
          matchedReasons.add('Keyword "$qToken"');
          continue;
        }

        // Check phonetic token
        if (normLatin.contains(normQToken)) {
          matchedTokens++;
          matchedReasons.add('Phonetic "$qToken"');
          continue;
        }

        // Substring / Levenshtein fuzzy match on shop tokens
        final shopTokens = latinPhonetic.split(' ');
        for (final sToken in shopTokens) {
          final normSToken = MarathiSearchHelper.normalize(sToken);
          if (normSToken == normQToken) {
            matchedTokens++;
            matchedReasons.add('Word "$qToken"');
            break;
          } else if (normSToken.length >= 4 && normQToken.length >= 4) {
            if (normSToken.contains(normQToken) || normQToken.contains(normSToken)) {
              matchedTokens += 1;
              matchedReasons.add('Similar "$qToken"');
              break;
            }
          }
        }
      }

      if (queryTokens.isNotEmpty) {
        final tokenRatio = matchedTokens / queryTokens.length;
        score += tokenRatio * 0.70;
      }

      // Cap score at 1.0
      score = score.clamp(0.0, 1.0);

      if (score > 0.25) {
        results.add(ShopMatchResult(
          shop: shop,
          score: score,
          matchedExplanation: matchedReasons.join(', '),
        ));
      }
    }

    if (results.isEmpty) return null;

    // Sort descending by score
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.first;
  }

  /// Returns sorted candidates with scores
  static List<ShopMatchResult> getRankedCandidates({
    required String rawExtractedName,
    required List<ShopModel> candidateShops,
  }) {
    if (candidateShops.isEmpty) return [];

    final cleanedQuery = cleanPartyName(rawExtractedName);
    if (cleanedQuery.isEmpty) return [];

    final queryTokens = cleanedQuery
        .toLowerCase()
        .split(' ')
        .where((t) => t.length >= 2)
        .toList();

    final List<ShopMatchResult> results = [];

    for (final shop in candidateShops) {
      double score = 0.0;
      final matchedReasons = <String>[];

      final shopNameLower = shop.name.toLowerCase();
      if (shopNameLower.contains(cleanedQuery.toLowerCase())) {
        score += 0.85;
        matchedReasons.add('Exact match');
      }

      final latinPhonetic = MarathiSearchHelper.toLatinPhonetic(shop.name);
      final normLatin = MarathiSearchHelper.normalize(latinPhonetic);
      final normQuery = MarathiSearchHelper.normalize(cleanedQuery);

      if (normLatin.contains(normQuery) || normQuery.contains(normLatin)) {
        score += 0.80;
        matchedReasons.add('Phonetic match');
      }

      int matchedTokens = 0;
      for (final qToken in queryTokens) {
        if (MarathiSearchHelper.matches(shop.name, qToken)) {
          matchedTokens++;
          matchedReasons.add('"$qToken"');
          continue;
        }

        final normQToken = MarathiSearchHelper.normalize(qToken);
        if (normLatin.contains(normQToken)) {
          matchedTokens++;
          matchedReasons.add('"$qToken"');
          continue;
        }
      }

      if (queryTokens.isNotEmpty) {
        score += (matchedTokens / queryTokens.length) * 0.70;
      }

      score = score.clamp(0.0, 1.0);
      if (score > 0.20) {
        results.add(ShopMatchResult(
          shop: shop,
          score: score,
          matchedExplanation: matchedReasons.join(', '),
        ));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
}
