/**
 * Provider-neutral OCR output: free text plus optional named fields and per-field confidence (0..1).
 * fromJson() reads the generic gateway contract used by GenericOcrClient:
 * { "text": "...", "lines": ["..."], "fields": {"name","dob","licenseNumber","expiry"}, "confidence": {"name": 0.93, ...} }
 */
public with sharing class OcrResult {
    public String text = '';
    public Map<String, String> fields = new Map<String, String>();
    public Map<String, Decimal> confidence = new Map<String, Decimal>();
    /** Raw provider body – callers must mask it before storing (DataMasking). */
    public String rawResponse;

    /** Lowest field confidence, or null when the provider does not return confidence (TDD R6). */
    public Decimal minConfidence() {
        Decimal result;
        for (Decimal c : confidence.values()) {
            if (c != null) {
                Decimal normalised = c > 1 ? c / 100 : c;
                result = result == null ? normalised : Math.min(result, normalised);
            }
        }
        return result;
    }

    public static OcrResult fromJson(String body) {
        OcrResult r = new OcrResult();
        r.rawResponse = body;
        Map<String, Object> j;
        try {
            j = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            throw new KycException('Could not read the image.');
        }
        List<String> parts = new List<String>();
        if (j.get('text') instanceof String) {
            parts.add((String) j.get('text'));
        }
        if (j.get('lines') instanceof List<Object>) {
            for (Object line : (List<Object>) j.get('lines')) {
                parts.add(String.valueOf(line));
            }
        }
        r.text = String.join(parts, '\n');
        if (j.get('fields') instanceof Map<String, Object>) {
            Map<String, Object> f = (Map<String, Object>) j.get('fields');
            for (String key : f.keySet()) {
                if (f.get(key) != null) {
                    r.fields.put(key, String.valueOf(f.get(key)));
                }
            }
        }
        if (j.get('confidence') instanceof Map<String, Object>) {
            Map<String, Object> c = (Map<String, Object>) j.get('confidence');
            for (String key : c.keySet()) {
                if (c.get(key) != null) {
                    r.confidence.put(key, Decimal.valueOf(String.valueOf(c.get(key))));
                }
            }
        } else if (j.get('confidence') != null) {
            r.confidence.put('overall', Decimal.valueOf(String.valueOf(j.get('confidence'))));
        }
        return r;
    }
}