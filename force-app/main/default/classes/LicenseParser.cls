/**
 * Extracts Name, DOB, Licence No. and Expiry from OCR output (TDD 9.5 "LicenseParser rules").
 * Structured provider fields win; otherwise the free text is parsed:
 *  - upper-case, collapse whitespace
 *  - licence: first match of [A-Z]{2}[ -]?[0-9]{2}[ -]?(19|20)[0-9]{2}[ -]?[0-9]{7}, spaces/dashes stripped;
 *    falls back to the value after a 'DL No' / 'Licence No' label (so R2 can flag a bad format for review)
 *  - dates dd-mm-yyyy / dd/mm/yyyy: near 'DOB'/'Date of Birth' = DOB, near 'Valid Till'/'Validity'/'NT' = expiry;
 *    without labels the earliest date is DOB and the latest is expiry
 *  - name: text after the label 'Name' up to the next label; 'S/D/W of' lines are ignored
 */
public with sharing class LicenseParser {
    public class ParsedLicense {
        public String name;
        public Date dob;
        public String licenseNo;
        public Date expiry;
        public Decimal confidence;
    }

    public static final String LICENSE_FORMAT = '^[A-Z]{2}[ -]?[0-9]{2}[ -]?(19|20)[0-9]{2}[ -]?[0-9]{7}$';
    private static final Pattern LICENSE = Pattern.compile('[A-Z]{2}[ -]?[0-9]{2}[ -]?(?:19|20)[0-9]{2}[ -]?[0-9]{7}');
    private static final Pattern LICENSE_LABEL = Pattern.compile(
        '(?:DL|LICEN[CS]E)\\s*(?:NO|NUMBER|NUM)\\.?\\s*[:.\\-]?\\s*([A-Z0-9][A-Z0-9 \\-]{5,22}[0-9])'
    );
    private static final Pattern DATE_TOKEN = Pattern.compile('(?<![0-9])([0-9]{1,2})[-/.]([0-9]{1,2})[-/.]([0-9]{4})(?![0-9])');
    private static final List<String> DOB_LABELS = new List<String>{ 'DOB', 'D.O.B', 'DATE OF BIRTH', 'BIRTH' };
    private static final List<String> EXPIRY_LABELS = new List<String>{
        'VALID TILL', 'VALIDITY', 'VALID UPTO', 'VALID UP TO', 'EXPIRY', 'EXPIRES', '(NT)', ' NT ', 'NT:', 'NT.'
    };
    private static final List<String> OTHER_DATE_LABELS = new List<String>{ 'DATE OF ISSUE', 'ISSUE', 'DOI', 'ISSUED' };
    private static final List<String> NAME_STOP_LABELS = new List<String>{
        ' DOB', 'D.O.B', 'DATE OF', 'S/D/W', 'S/O', 'D/O', 'W/O', 'SON OF', 'DAUGHTER', 'WIFE OF', 'ADDRESS', 'BLOOD',
        'VALID', 'DL NO', 'LICENCE', 'LICENSE'
    };
    private static final List<String> RELATION_MARKERS = new List<String>{
        'S/D/W', 'S/O', 'D/O', 'W/O', 'SON OF', 'DAUGHTER OF', 'WIFE OF', 'FATHER', 'HUSBAND', 'GUARDIAN'
    };

    public static ParsedLicense parse(OcrResult r) {
        ParsedLicense p = new ParsedLicense();
        if (r == null) {
            return p;
        }
        p.confidence = r.minConfidence();
        String upper = (r.text ?? '').toUpperCase();
        String flat = upper.replaceAll('\\s+', ' ').trim();

        p.name = cleanName(firstField(r.fields, new List<String>{ 'name', 'fullName', 'holderName' }));
        p.dob = normaliseDate(firstField(r.fields, new List<String>{ 'dob', 'dateOfBirth', 'birthDate' }));
        String lic = firstField(r.fields, new List<String>{ 'licenseNumber', 'licenceNumber', 'dlNumber' });
        p.licenseNo = String.isBlank(lic) ? null : lic.toUpperCase().replaceAll('[\\s-]', '');
        p.expiry = normaliseDate(firstField(r.fields, new List<String>{ 'expiry', 'expiryDate', 'validTill' }));

        if (p.licenseNo == null) {
            p.licenseNo = findLicense(flat);
        }
        if (p.dob == null || p.expiry == null) {
            fillDates(flat, p);
        }
        if (p.name == null) {
            p.name = findName(upper);
        }
        return p;
    }

    public static Boolean isValidFormat(String licenseNo) {
        return String.isNotBlank(licenseNo) && Pattern.matches(LICENSE_FORMAT, licenseNo.toUpperCase());
    }

    @TestVisible
    private static String findLicense(String flat) {
        Matcher m = LICENSE.matcher(flat);
        if (m.find()) {
            return m.group().replaceAll('[ -]', '');
        }
        Matcher l = LICENSE_LABEL.matcher(flat);
        if (l.find()) {
            return l.group(1).replaceAll('[ -]', '');
        }
        return null;
    }

    private static void fillDates(String flat, ParsedLicense p) {
        List<Date> unlabelled = new List<Date>();
        List<Date> all = new List<Date>();
        Matcher m = DATE_TOKEN.matcher(flat);
        while (m.find()) {
            Date d = buildDate(m.group(1), m.group(2), m.group(3));
            if (d == null) {
                continue;
            }
            all.add(d);
            String context = flat.substring(Math.max(0, m.start() - 30), m.start());
            Integer dobPos = lastIndex(context, DOB_LABELS);
            Integer expPos = lastIndex(context, EXPIRY_LABELS);
            Integer otherPos = lastIndex(context, OTHER_DATE_LABELS);
            if (dobPos > expPos && dobPos > otherPos) {
                p.dob = p.dob ?? d;
            } else if (expPos > dobPos && expPos > otherPos) {
                p.expiry = p.expiry ?? d;
            } else if (otherPos < 0) {
                unlabelled.add(d);
            }
        }
        if (all.isEmpty()) {
            return;
        }
        List<Date> pool = unlabelled.isEmpty() ? all : unlabelled;
        pool.sort();
        if (p.dob == null && (p.expiry == null || pool[0] != p.expiry)) {
            p.dob = pool[0];
        }
        if (p.expiry == null && pool.size() > 1 && pool[pool.size() - 1] != p.dob) {
            p.expiry = pool[pool.size() - 1];
        }
    }

    private static Integer lastIndex(String context, List<String> labels) {
        Integer best = -1;
        for (String label : labels) {
            best = Math.max(best, context.lastIndexOf(label));
        }
        return best;
    }

    @TestVisible
    private static String findName(String upper) {
        List<String> lines = upper.split('\n');
        for (Integer i = 0; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (!line.contains('NAME') || containsAny(line, RELATION_MARKERS)) {
                continue;
            }
            String after = line.substringAfter('NAME').replaceFirst('^\\s*[:.\\-]?\\s*', '');
            after = cutAtLabel(after);
            if (String.isBlank(after) && i + 1 < lines.size() && !containsAny(lines[i + 1], RELATION_MARKERS)) {
                after = cutAtLabel(lines[i + 1].trim());
            }
            String cleaned = cleanName(after);
            if (cleaned != null) {
                return cleaned;
            }
        }
        return null;
    }

    private static String cutAtLabel(String value) {
        String padded = ' ' + value;
        Integer cut = padded.length();
        for (String label : NAME_STOP_LABELS) {
            Integer idx = padded.indexOf(label);
            if (idx >= 0 && idx < cut) {
                cut = idx;
            }
        }
        return padded.substring(0, cut).trim();
    }

    private static Boolean containsAny(String value, List<String> markers) {
        for (String marker : markers) {
            if (value.contains(marker)) {
                return true;
            }
        }
        return false;
    }

    private static String cleanName(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String cleaned = value.replaceAll('[^A-Za-z .]', ' ').replaceAll('\\s+', ' ').trim();
        return cleaned.length() < 2 ? null : cleaned;
    }

    private static String firstField(Map<String, String> fields, List<String> keys) {
        for (String k : keys) {
            if (fields != null && String.isNotBlank(fields.get(k))) {
                return fields.get(k).trim();
            }
        }
        return null;
    }

    /** dd-mm-yyyy, dd/mm/yyyy, dd.mm.yyyy or yyyy-mm-dd -> Date; null when invalid. */
    public static Date normaliseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String v = value.trim();
        Matcher iso = Pattern.compile('^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}).*$').matcher(v);
        if (iso.matches()) {
            return buildDate(iso.group(3), iso.group(2), iso.group(1));
        }
        Matcher m = DATE_TOKEN.matcher(v);
        return m.find() ? buildDate(m.group(1), m.group(2), m.group(3)) : null;
    }

    private static Date buildDate(String dd, String mm, String yyyy) {
        Integer d = Integer.valueOf(dd), mo = Integer.valueOf(mm), y = Integer.valueOf(yyyy);
        if (mo < 1 || mo > 12 || d < 1 || y < 1900 || y > 2100 || d > Date.daysInMonth(y, mo)) {
            return null;
        }
        return Date.newInstance(y, mo, d);
    }
}