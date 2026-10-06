class MarathiSearchHelper {
  // Dictionary mapping of Marathi words/roots to common English spellings
  static const Map<String, List<String>> _dictionary = {
    // Business keywords
    'जनरल': ['general', 'genral', 'gnrl'],
    'स्टोअर्स': ['stores', 'store', 'stors', 'stor'],
    'स्टोअर': ['store', 'stores'],
    'प्रोव्हिजन': ['provision', 'provisn', 'provison', 'provishen'],
    'सुपर': ['super', 'supr'],
    'मार्केट': ['market', 'mrkt'],
    'ट्रेडर्स': ['traders', 'trader', 'trdr', 'tredars'],
    'ट्रेडर': ['trader', 'traders'],
    'ट्रेडिंग': ['trading', 'treding'],
    'कंपनी': ['company', 'cmpny', 'co'],
    'शॉपी': ['shopee', 'shoppee', 'shopy', 'shoppy', 'shopi'],
    'शॉप': ['shop', 'shops'],
    'किराणा': ['kirana', 'kirna'],
    'माल': ['maal', 'mal'],
    'व्हरायटी': ['variety', 'verayti'],
    'मार्ट': ['mart'],
    'मॉल': ['mall'],
    'डेअरी': ['dairy', 'dery'],
    'दुध': ['dudh', 'doodh', 'milk'],
    'दूध': ['dudh', 'doodh', 'milk'],
    'स्मार्ट': ['smart'],
    'नॅशनल': ['national', 'nashnal'],
    'न्यू': ['new', 'nyu'],
    'हॉटेल': ['hotel'],

    // Proper names commonly used in Marathi shop names
    'श्री': ['shree', 'shri', 'sree', 'sri'],
    'साई': ['sai', 'sayi'],
    'विशाल': ['vishal', 'wishal'],
    'प्रकाश': ['prakash', 'prkash'],
    'हनुमान': ['hanuman', 'maruti'],
    'साहिल': ['sahil'],
    'सहारा': ['sahara'],
    'संगम': ['sangam'],
    'श्रुती': ['shruti', 'sruti'],
    'रामदेव': ['ramdev', 'ramdeo'],
    'राम': ['ram', 'shriram'],
    'राजेश्वर': ['rajeshwar'],
    'युवराज': ['yuvraj'],
    'यश': ['yash'],
    'वाघजाई': ['vaghjai', 'waghjai', 'waghai'],
    'माता': ['mata'],
    'माऊली': ['mauli', 'mowli', 'mouli'],
    'कृपा': ['krupa', 'kripa'],
    'महादेव': ['mahadev'],
    'भाग्यलक्ष्मी': ['bhagyalaxmi', 'bhagyalakshmi'],
    'लक्ष्मी': ['laxmi', 'lakshmi'],
    'भवानी': ['bhavani', 'bhawani'],
    'बालाजी': ['balaji'],
    'पुरबजी': ['purabji', 'purbaji'],
    'निखिल': ['nikhil'],
    'नागेश्वर': ['nageshwar'],
    'तुळजाभवानी': ['tuljabhavani', 'tulja'],
    'तुळजा': ['tulja'],
    'तुलसी': ['tulsi'],
    'जय': ['jay', 'jai'],
    'मल्लिनाथजी': ['mallinathji', 'malinathji'],
    'छत्रपती': ['chhatrapati', 'chatrapati', 'shivaji'],
    'चौधरी': ['chaudhary', 'choudhary', 'choudhari', 'chaudhari'],
    'कृष्णकला': ['krishnakala'],
    'कृष्णा': ['krishna'],
    'काव्या': ['kavya'],
    'आर्यन': ['aryan'],
    'आई': ['aai', 'ai'],
    'अरिहंत': ['arihant'],
    'सतीश': ['satish', 'sateesh'],
    'गणेश': ['ganesh', 'ganpati'],
    'ओम': ['om'],
    'मल्हार': ['malhar', 'khandoba'],
  };

  static const Map<String, String> _consonants = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
    'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l', 'क्ष': 'ksh', 'ज्ञ': 'dny',
  };

  static const Map<String, String> _vowels = {
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u',
    'ऊ': 'oo', 'ऋ': 'ru', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o',
    'औ': 'au', 'अं': 'am', 'अः': 'ah', 'ऑ': 'o', 'ॲ': 'a',
  };

  static const Map<String, String> _matras = {
    'ा': 'a', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo',
    'ृ': 'ru', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au',
    'ं': 'n', 'ँ': 'n', 'ः': 'h', 'ॅ': 'a', 'ॉ': 'o', '्': '',
  };

  /// Transliterates Devanagari characters into Latin phonetic string
  static String toLatinPhonetic(String text) {
    final buffer = StringBuffer();
    final chars = text.split('');
    final n = chars.length;

    for (int i = 0; i < n; i++) {
      final c = chars[i];
      if (_vowels.containsKey(c)) {
        buffer.write(_vowels[c]);
      } else if (_consonants.containsKey(c)) {
        final base = _consonants[c]!;
        if (i + 1 < n && chars[i + 1] == '्') {
          buffer.write(base);
          i++; // skip halant
        } else if (i + 1 < n && _matras.containsKey(chars[i + 1])) {
          buffer.write(base);
          buffer.write(_matras[chars[i + 1]]);
          i++; // skip matra
        } else {
          buffer.write('${base}a');
        }
      } else if (_matras.containsKey(c)) {
        buffer.write(_matras[c]);
      } else {
        buffer.write(c);
      }
    }

    return buffer.toString().toLowerCase();
  }

  /// Normalizes English text for flexible matching:
  /// - 'w' -> 'v'
  /// - 'ee' -> 'i'
  /// - 'oo' -> 'u'
  /// - 'sh' -> 's'
  /// - 'aa' -> 'a'
  static String normalize(String s) {
    return s.toLowerCase()
        .replaceAll('w', 'v')
        .replaceAll('ee', 'i')
        .replaceAll('oo', 'u')
        .replaceAll('sh', 's')
        .replaceAll('aa', 'a')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Checks if [target] matches [query] using:
  /// 1. Direct contains (case insensitive)
  /// 2. Dictionary keyword lookup
  /// 3. Phonetic transliteration
  /// 4. Normalized phonetic fuzzy match
  static bool matches(String target, String query) {
    if (query.trim().isEmpty) return true;
    final cleanQuery = query.trim().toLowerCase();
    final cleanTarget = target.trim().toLowerCase();

    // 1. Direct match (covers Marathi-to-Marathi and exact English matches)
    if (cleanTarget.contains(cleanQuery)) return true;

    // Collect all search representations of target
    final targetWords = <String>[cleanTarget];

    // Add dictionary mappings
    for (final entry in _dictionary.entries) {
      if (cleanTarget.contains(entry.key)) {
        targetWords.addAll(entry.value);
      }
    }

    // Add algorithmic transliteration
    final latin = toLatinPhonetic(cleanTarget);
    targetWords.add(latin);

    // Also add words of the transliteration individually
    targetWords.addAll(latin.split(RegExp(r'\s+')));

    // Build normalized versions
    final normalizedTargets = targetWords.map(normalize).where((s) => s.isNotEmpty).toList();
    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // Every token in query must match at least one token/keyword of target
    return queryTokens.every((qToken) {
      final normQ = normalize(qToken);
      // Check in raw target words
      for (final w in targetWords) {
        if (w.contains(qToken)) return true;
      }
      // Check in normalized forms
      for (final nw in normalizedTargets) {
        if (nw.contains(normQ)) return true;
      }
      return false;
    });
  }
}
