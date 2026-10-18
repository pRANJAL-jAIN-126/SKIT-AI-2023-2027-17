/**
 * Shared HTTP handling for OCR providers – maps transport errors to the TDD 10.4 messages:
 * timeout / 5xx -> 'Verification service is busy, try again'; 4xx -> 'Could not read the image'.
 */
public with sharing class OcrHttp {
    public static final String MSG_BUSY = 'Verification service is busy, try again.';
    public static final String MSG_UNREADABLE = 'Could not read the image.';

    public static HttpResponse send(HttpRequest req) {
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new KycException(MSG_BUSY);
        }
        Integer code = res.getStatusCode();
        if (code >= 500) {
            throw new KycException(MSG_BUSY);
        }
        if (code >= 400) {
            throw new KycException(MSG_UNREADABLE);
        }
        return res;
    }
}