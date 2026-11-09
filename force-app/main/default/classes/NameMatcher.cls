/**
 * KYC rule R5: normalised, token-based name similarity (TDD 7.2) – ignores case, word order and initials,
 * and tolerates one OCR character error in tokens of 5+ letters. Score = Dice coefficient over tokens.
 */
public with sharing class NameMatcher {
    public static Decimal similarity(String a, String b) {
        List<String> ta = tokens(a), tb = tokens(b);
        if (ta.isEmpty() || tb.isEmpty()) {
            return 0;
        }
        List<String> remaining = new List<String>(tb);
        Integer matches = 0;
        for (String t : ta) {
            for (Integer i = 0; i < remaining.size(); i++) {
                if (same(t, remaining[i])) {
                    matches++;
                    remaining.remove(i);
                    break;
                }
            }
        }
        return (Decimal.valueOf(2 * matches) / (ta.size() + tb.size())).setScale(4, System.RoundingMode.HALF_UP);
    }

    private static Boolean same(String x, String y) {
        if (x == y) {
            return true;
        }
        return x.length() >= 5 && y.length() >= 5 && x.getLevenshteinDistance(y) <= 1;
    }

    @TestVisible
    private static List<String> tokens(String value) {
        List<String> result = new List<String>();
        if (String.isBlank(value)) {
            return result;
        }
        for (String t : value.toUpperCase().replaceAll('[^A-Z ]', ' ').split(' ')) {
            if (t.length() > 1) {
                result.add(t); // single letters are initials -> ignored
            }
        }
        return result;
    }
}