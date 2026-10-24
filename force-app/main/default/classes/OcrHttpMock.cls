/**
 * HttpCalloutMock for the OCR provider (TDD 9.1). Returns a fixed status/body; can simulate a timeout.
 */
@IsTest
public class OcrHttpMock implements HttpCalloutMock {
    public static Integer calls = 0;
    private final Integer status;
    private final String body;
    private final Boolean timeout;

    public OcrHttpMock(Integer status, String body) {
        this(status, body, false);
    }

    private OcrHttpMock(Integer status, String body, Boolean timeout) {
        this.status = status;
        this.body = body;
        this.timeout = timeout;
    }

    public static OcrHttpMock timeoutMock() {
        return new OcrHttpMock(0, null, true);
    }

    /** Generic gateway contract (GenericOcrClient). */
    public static OcrHttpMock generic(String text, Decimal confidence) {
        return new OcrHttpMock(200, JSON.serialize(new Map<String, Object>{
            'text' => text,
            'confidence' => new Map<String, Object>{ 'name' => confidence, 'licenseNumber' => confidence }
        }));
    }

    /** OCR.space response shape (OcrSpaceClient). */
    public static OcrHttpMock ocrSpace(String text) {
        return new OcrHttpMock(200, JSON.serialize(new Map<String, Object>{
            'ParsedResults' => new List<Object>{ new Map<String, Object>{ 'ParsedText' => text, 'FileParseExitCode' => 1 } },
            'OCRExitCode' => 1,
            'IsErroredOnProcessing' => false
        }));
    }

    public HttpResponse respond(HttpRequest req) {
        calls++;
        if (timeout) {
            throw new CalloutException('Read timed out');
        }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(status);
        res.setBody(body ?? '');
        return res;
    }
}