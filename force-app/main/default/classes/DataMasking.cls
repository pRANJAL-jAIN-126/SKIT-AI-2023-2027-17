/**
 * Masks driving-licence numbers before they reach the UI, logs or debug output (TDD NFR-03, 11.3).
 */
public with sharing class DataMasking {
    private static final Pattern LICENSE_PATTERN = Pattern.compile(
        '(?i)[A-Z]{2}[ -]?[0-9]{2}[ -]?(?:19|20)[0-9]{2}[ -]?[0-9]{7}'
    );
    private static final Pattern LONG_DIGITS = Pattern.compile('[0-9]{7,}');

    /** 'RJ1420150012345' -> 'XXXX2345'. */
    public static String maskLicense(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String compact = value.replaceAll('[\\s-]', '');
        return compact.length() <= 4 ? '****' : 'XXXX' + compact.right(4);
    }

    /** Replaces every licence-like token (and any 7+ digit run) inside free text. */
    public static String maskLicenseNumbersIn(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        return replaceAll(replaceAll(text, LICENSE_PATTERN), LONG_DIGITS);
    }

    private static String replaceAll(String text, Pattern p) {
        Matcher m = p.matcher(text);
        List<String> parts = new List<String>();
        Integer last = 0;
        while (m.find()) {
            parts.add(text.substring(last, m.start()));
            parts.add(maskLicense(m.group()));
            last = m.end();
        }
        parts.add(text.substring(last));
        return String.join(parts, '');
    }
}