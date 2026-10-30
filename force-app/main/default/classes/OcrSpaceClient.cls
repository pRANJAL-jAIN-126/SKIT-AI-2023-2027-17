/**
 * OCR.space provider (plan D-04) – https://ocr.space/OCRAPI. Named Credential OCR_API must point to
 * https://api.ocr.space and External Credential OCR_EC must send the 'apikey' header.
 * OCR.space returns plain text only (no per-field confidence), so rule R6 is skipped for this provider.
 */
public with sharing class OcrSpaceClient implements OcrProvider {
    public OcrResult extract(Blob image, String mimeType) {
        String dataUri = 'data:' + mimeType + ';base64,' + EncodingUtil.base64Encode(image);
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OCR_API/parse/image');
        req.setMethod('POST');
        req.setTimeout(60000);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'language=eng&OCREngine=2&scale=true&isOverlayRequired=false&base64Image=' +
            EncodingUtil.urlEncode(dataUri, 'UTF-8')
        );
        dataUri = null; // release heap before the callout
        HttpResponse res = OcrHttp.send(req);

        OcrResult r = new OcrResult();
        r.rawResponse = res.getBody();
        Map<String, Object> j;
        try {
            j = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw new KycException('Could not read the image.');
        }
        if (j.get('IsErroredOnProcessing') == true) {
            throw new KycException('Could not read the image.');
        }
        List<String> texts = new List<String>();
        if (j.get('ParsedResults') instanceof List<Object>) {
            for (Object o : (List<Object>) j.get('ParsedResults')) {
                Map<String, Object> pr = (Map<String, Object>) o;
                if (pr.get('ParsedText') != null) {
                    texts.add(String.valueOf(pr.get('ParsedText')));
                }
            }
        }
        r.text = String.join(texts, '\n');
        return r;
    }
}