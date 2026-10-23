import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shop_model.dart';
import 'bill_text_parser.dart';
import 'party_name_matcher.dart';
import 'supabase_service.dart';
import 'ocr/ocr_stub_bridge.dart'
    if (dart.library.html) 'ocr/ocr_web_bridge.dart';

class BillOcrResult {
  final bool success;
  final String? errorMessage;
  final String rawOcrText;
  final String? billNumber;
  final DateTime? billDate;
  final double? amount;
  final String? extractedPartyName;
  final ShopModel? matchedShop;
  final double matchScore;
  final String? matchExplanation;
  final List<ShopMatchResult> rankedShops;
  final bool usedCloudAi;

  const BillOcrResult({
    required this.success,
    this.errorMessage,
    required this.rawOcrText,
    this.billNumber,
    this.billDate,
    this.amount,
    this.extractedPartyName,
    this.matchedShop,
    this.matchScore = 0.0,
    this.matchExplanation,
    this.rankedShops = const [],
    this.usedCloudAi = false,
  });

  bool get hasAnyExtractedField =>
      (billNumber != null && billNumber!.isNotEmpty) ||
      billDate != null ||
      (amount != null && amount! > 0) ||
      (matchedShop != null) ||
      (extractedPartyName != null && extractedPartyName!.isNotEmpty);
}

class BillOcrService {
  static const String _keyGeminiKey = 'gemini_api_key_v1';
  static String? _cachedApiKey;

  /// Saves user-provided Gemini API key for high-speed cloud vision and syncs across devices
  static Future<void> saveApiKey(String key) async {
    final cleanKey = key.trim();
    _cachedApiKey = cleanKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGeminiKey, cleanKey);
    try {
      await SupabaseService().syncGeminiApiKey(cleanKey);
    } catch (e) {
      debugPrint('Cloud sync error for Gemini key: $e');
    }
  }

  /// Gets stored Gemini API key, syncing from cloud if not present locally
  static Future<String?> getApiKey() async {
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_keyGeminiKey);
    if (key != null && key.trim().isNotEmpty) {
      _cachedApiKey = key.trim();
      return _cachedApiKey;
    }

    try {
      final cloudKey = await SupabaseService().fetchGeminiApiKey();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        _cachedApiKey = cloudKey;
        await prefs.setString(_keyGeminiKey, cloudKey);
        return cloudKey;
      }
    } catch (e) {
      debugPrint('Error loading cloud Gemini key: $e');
    }
    return null;
  }

  /// Explicitly pulls latest Gemini key from cloud Supabase
  static Future<String?> syncFromCloud() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cloudKey = await SupabaseService().fetchGeminiApiKey();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        _cachedApiKey = cloudKey;
        await prefs.setString(_keyGeminiKey, cloudKey);
        return cloudKey;
      }
    } catch (e) {
      debugPrint('Error syncing Gemini key from cloud: $e');
    }
    final localKey = prefs.getString(_keyGeminiKey);
    _cachedApiKey = localKey;
    return localKey;
  }

  /// Check whether an API key is configured
  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Extracts bill details from base64 image and matches English party name against route shops
  static Future<BillOcrResult> processBillImage({
    required String base64Image,
    required List<ShopModel> candidateShops,
  }) async {
    try {
      // 1. Try Gemini Vision if an API key is configured
      final apiKey = await getApiKey();
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          final cloudResult = await _extractWithGeminiVision(base64Image, apiKey, candidateShops);
          if (cloudResult != null && cloudResult.hasAnyExtractedField) {
            return cloudResult;
          }
        } catch (e) {
          debugPrint('Gemini Vision fallback to client OCR: $e');
        }
      }

      // 2. Client-side browser OCR (Tesseract.js via OcrBridge) with multi-slice spatial extraction
      OcrExtractedText? ocrPayload;
      try {
        ocrPayload = await OcrBridge.extractTextFromBase64(base64Image);
      } catch (e) {
        debugPrint('OcrBridge error: $e');
      }

      if (ocrPayload == null || ocrPayload.isEmpty) {
        return const BillOcrResult(
          success: false,
          errorMessage: 'Could not extract text from bill image. Please ensure good lighting and clear text.',
          rawOcrText: '',
        );
      }

      // 3. Spatially-aware parse of raw OCR text (header, footer, and full slices)
      final parsed = BillTextParser.parse(
        ocrPayload.fullText,
        headerText: ocrPayload.headerText,
        footerText: ocrPayload.footerText,
      );

      // 4. Match extracted party name against candidate shops in beat route
      ShopMatchResult? bestMatch;
      List<ShopMatchResult> ranked = const [];

      if (parsed.partyName != null && parsed.partyName!.isNotEmpty) {
        bestMatch = PartyNameMatcher.findBestMatch(
          rawExtractedName: parsed.partyName!,
          candidateShops: candidateShops,
        );
        ranked = PartyNameMatcher.getRankedCandidates(
          rawExtractedName: parsed.partyName!,
          candidateShops: candidateShops,
        );
      }

      // If no party name was explicitly tagged, search header slice lines for shop matches
      if (bestMatch == null && candidateShops.isNotEmpty) {
        final searchSource = ocrPayload.headerText.isNotEmpty ? ocrPayload.headerText : ocrPayload.fullText;
        for (final line in searchSource.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.length >= 4) {
            final testMatch = PartyNameMatcher.findBestMatch(
              rawExtractedName: trimmed,
              candidateShops: candidateShops,
            );
            if (testMatch != null && testMatch.score > 0.60) {
              bestMatch = testMatch;
              break;
            }
          }
        }
      }

      return BillOcrResult(
        success: true,
        rawOcrText: ocrPayload.fullText,
        billNumber: parsed.billNumber,
        billDate: parsed.billDate,
        amount: parsed.amount,
        extractedPartyName: parsed.partyName,
        matchedShop: bestMatch?.shop,
        matchScore: bestMatch?.score ?? 0.0,
        matchExplanation: bestMatch?.matchedExplanation,
        rankedShops: ranked,
        usedCloudAi: false,
      );
    } catch (e) {
      debugPrint('BillOcrService error: $e');
      return BillOcrResult(
        success: false,
        errorMessage: 'OCR Processing Error: $e',
        rawOcrText: '',
      );
    }
  }

  /// Gemini Vision API call for instant structured invoice extraction
  static Future<BillOcrResult?> _extractWithGeminiVision(
    String base64Image,
    String apiKey,
    List<ShopModel> candidateShops,
  ) async {
    final cleanB64 = base64Image.contains(',') ? base64Image.split(',').last : base64Image;

    // Use Gemini 3.5 Flash-Lite with minimal thinking for ultra-fast (2-3 second) multimodal extraction
    final models = [
      'gemini-3.5-flash-lite',
      'gemini-flash-lite-latest',
      'gemini-3.8-flash',
      'gemini-flash-latest',
    ];

    final candidateList = candidateShops.isNotEmpty
        ? '\nCandidate beat shops (match party name to one of these if close):\n${candidateShops.take(60).map((s) => s.name).join(", ")}'
        : '';

    for (final model in models) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        final payload = {
          'contents': [
            {
              'parts': [
                {
                  'text': '''You are an ultra-fast Indian wholesale & FMCG bill invoice analyzer.
Analyze this invoice/bill photo and extract these fields in strict JSON format:
{
  "bill_number": "invoice or bill number (e.g. PE-2024-0412 or 1042)",
  "bill_date": "YYYY-MM-DD",
  "amount": total bill amount as a number (e.g. 1450.00),
  "party_name": "customer / shop / buyer name printed on bill (English)",
  "matched_shop_name": "exact match from Candidate beat shops list if matching, otherwise null"
}
Look for:
- Invoice number in header area (near Inv No, Bill No, Tax Invoice)
- Date in header area (near Date, Dt, Dated)
- Total amount at the bottom of the bill (Grand Total, Net Payable, Total Amount)
- Party name under M/s, To, Customer, Billed To (ignore distributor firm name)
$candidateList
Return ONLY pure JSON without markdown code fences.'''
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': cleanB64,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'responseMimeType': 'application/json',
            'thinkingConfig': {
              'thinkingLevel': 'minimal',
            },
          }
        };

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode != 200) {
          debugPrint('Gemini API ($model) returned code: ${response.statusCode}');
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) continue;

        final parts = candidates[0]['content']?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) continue;

        final text = parts[0]['text'] as String?;
        if (text == null || text.trim().isEmpty) continue;

        // Clean any accidental markdown backticks
        var jsonText = text.trim();
        if (jsonText.startsWith('```json')) jsonText = jsonText.substring(7);
        if (jsonText.startsWith('```')) jsonText = jsonText.substring(3);
        if (jsonText.endsWith('```')) jsonText = jsonText.substring(0, jsonText.length - 3);
        jsonText = jsonText.trim();

        final parsedJson = jsonDecode(jsonText) as Map<String, dynamic>;

        final billNo = parsedJson['bill_number']?.toString();
        final dateStr = parsedJson['bill_date']?.toString();
        final amtVal = parsedJson['amount'];
        final party = parsedJson['party_name']?.toString();
        final matchedName = parsedJson['matched_shop_name']?.toString();

        DateTime? parsedDate;
        if (dateStr != null && dateStr.isNotEmpty) {
          parsedDate = DateTime.tryParse(dateStr);
        }

        double? parsedAmt;
        if (amtVal is num) {
          parsedAmt = amtVal.toDouble();
        } else if (amtVal is String) {
          parsedAmt = double.tryParse(amtVal.replaceAll(',', ''));
        }

        ShopMatchResult? bestMatch;
        List<ShopMatchResult> ranked = const [];

        // Check if Gemini matched directly with high precision
        if (matchedName != null && matchedName.isNotEmpty) {
          for (final s in candidateShops) {
            if (s.name.trim().toLowerCase() == matchedName.trim().toLowerCase()) {
              bestMatch = ShopMatchResult(
                shop: s,
                score: 0.99,
                matchedExplanation: 'AI Direct Match: ${s.name}',
              );
              break;
            }
          }
        }

        // Fallback to phonetic and token matcher
        if (bestMatch == null && party != null && party.isNotEmpty) {
          bestMatch = PartyNameMatcher.findBestMatch(
            rawExtractedName: party,
            candidateShops: candidateShops,
          );
          ranked = PartyNameMatcher.getRankedCandidates(
            rawExtractedName: party,
            candidateShops: candidateShops,
          );
        }

        return BillOcrResult(
          success: true,
          rawOcrText: jsonText,
          billNumber: billNo,
          billDate: parsedDate,
          amount: parsedAmt,
          extractedPartyName: party,
          matchedShop: bestMatch?.shop,
          matchScore: bestMatch?.score ?? 0.0,
          matchExplanation: bestMatch?.matchedExplanation,
          rankedShops: ranked,
          usedCloudAi: true,
        );
      } catch (e) {
        debugPrint('Gemini attempt with $model failed: $e');
      }
    }

    return null;
  }
}
