/**
 * HttpCalloutMock for the Stripe API (TDD 9.1). Responses are chosen by method + path; every request is
 * recorded so tests can assert idempotency (no second callout) and request contents.
 */
@IsTest
public class StripeHttpMock implements HttpCalloutMock {
    public static List<HttpRequest> requests = new List<HttpRequest>();

    private Integer createStatus = 200;
    private Integer retrieveStatus = 200;
    private Integer refundStatus = 200;
    private String paymentStatus = 'paid';
    private String sessionStatus = 'complete';
    private String bookingId;
    private Boolean throwTimeout = false;

    public StripeHttpMock(Id bookingId) {
        this.bookingId = bookingId;
    }

    public static StripeHttpMock paid(Id bookingId) {
        return new StripeHttpMock(bookingId);
    }

    public static StripeHttpMock unpaid(Id bookingId) {
        StripeHttpMock m = new StripeHttpMock(bookingId);
        m.paymentStatus = 'unpaid';
        m.sessionStatus = 'open';
        return m;
    }

    public static StripeHttpMock expired(Id bookingId) {
        StripeHttpMock m = new StripeHttpMock(bookingId);
        m.paymentStatus = 'unpaid';
        m.sessionStatus = 'expired';
        return m;
    }

    public StripeHttpMock withCreateStatus(Integer status) {
        createStatus = status;
        return this;
    }

    public StripeHttpMock withRetrieveStatus(Integer status) {
        retrieveStatus = status;
        return this;
    }

    public StripeHttpMock withRefundStatus(Integer status) {
        refundStatus = status;
        return this;
    }

    public StripeHttpMock withTimeout() {
        throwTimeout = true;
        return this;
    }

    public HttpResponse respond(HttpRequest req) {
        requests.add(req);
        if (throwTimeout) {
            throw new CalloutException('Read timed out');
        }
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        String endpoint = req.getEndpoint();
        if (req.getMethod() == 'POST' && endpoint.endsWith('/v1/checkout/sessions')) {
            res.setStatusCode(createStatus);
            res.setBody(createStatus == 200
                ? '{"id":"cs_test_mock123","object":"checkout.session","url":"https://checkout.stripe.com/c/pay/cs_test_mock123"}'
                : '{"error":{"message":"Stripe unavailable"}}');
        } else if (req.getMethod() == 'GET' && endpoint.contains('/v1/checkout/sessions/')) {
            res.setStatusCode(retrieveStatus);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'id' => endpoint.substringAfterLast('/'),
                'object' => 'checkout.session',
                'payment_status' => paymentStatus,
                'status' => sessionStatus,
                'payment_intent' => paymentStatus == 'paid' ? 'pi_test_mock123' : null,
                'amount_total' => 2000000,
                'metadata' => new Map<String, Object>{ 'booking_id' => bookingId }
            }));
        } else if (req.getMethod() == 'POST' && endpoint.endsWith('/v1/refunds')) {
            res.setStatusCode(refundStatus);
            res.setBody(refundStatus == 200 ? '{"id":"re_test_mock123","status":"succeeded"}' : '{"error":{"message":"refund failed"}}');
        } else {
            res.setStatusCode(404);
            res.setBody('{"error":{"message":"not found"}}');
        }
        return res;
    }
}