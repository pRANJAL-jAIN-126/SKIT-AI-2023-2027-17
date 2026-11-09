/**
 * Generic JSON OCR gateway client (TDD 9.5 reference implementation). Use it with any provider fronted by a
 * small gateway that accepts {image, mimeType} and returns the OcrResult.fromJson contract.
 * Named Credential: OCR_API (key held by External Credential OCR_EC – never in code).
 */
public with sharing class GenericOcrClient implements OcrProvider {
    public OcrResult extract(Blob image, String mimeType) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OCR_API/ocr');
        req.setMethod('POST');
        req.setTimeout(60000);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'image' => EncodingUtil.base64Encode(image), 'mimeType' => mimeType }));
        HttpResponse res = OcrHttp.send(req);
        return OcrResult.fromJson(res.getBody());
    }
}