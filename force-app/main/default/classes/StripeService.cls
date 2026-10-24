/**
 * Stripe Checkout integration in TEST mode (TDD 7.4, 9.6, D4, D5). The secret key lives only in External
 * Credential Stripe_EC (Named Credential Stripe_API). Card data never reaches Salesforce.
 *
 *  createCheckoutSession – callout first, then Payment__c upsert (DML after callout is allowed)
 *  verifyAndConfirm      – server-side verification of the session; idempotent (reloading the result page is safe)
 *  refund                – POST /v1/refunds, run from StripeRefundQueueable
 */
public with sharing class StripeService {
    public static final String PAY_INITIATED = 'Initiated';
    public static final String PAY_SUCCEEDED = 'Succeeded';
    public static final String PAY_FAILED = 'Failed';
    public static final String PAY_REFUNDED = 'Refunded';

    public class CheckoutResult {
        @AuraEnabled public String url;
        @AuraEnabled public String sessionId;
    }

    // ------------------------------------------------------------------ checkout session

    public static CheckoutResult createCheckoutSession(Id bookingId) {
        return createCheckoutSession(bookingId, CustomerContext.requireCustomer());
    }

    public static CheckoutResult createCheckoutSession(Id bookingId, Id contactId) {
        Booking__c b = BookingRepository.getOwned(contactId, bookingId);
        if (b == null) {
            throw new StripeException('Booking not found.');
        }
        if (b.Status__c != BookingService.ST_PENDING || b.Payment_Status__c == BookingService.PAY_PAID) {
            throw new StripeException('Booking is not awaiting payment.');
        }
        if (b.Hold_Expires_At__c == null || b.Hold_Expires_At__c <= System.now()) {
            throw new StripeException('This hold has expired. Please search again to book the car.');
        }
        if (b.Customer__r.KYC_Status__c != 'Verified') {
            // FR-07 / TC-17: no payment before KYC is verified
            throw new StripeException('Please verify your driving licence before paying.');
        }
        Rental_Config__mdt cfg = RentalConfig.get();
        Decimal amount = (b.Total_Amount__c ?? 0) + (b.Deposit_Amount__c ?? 0);
        Long minor = PricingService.toMinorUnits(amount);
        String site = RentalConfig.siteUrl();
        Map<String, String> form = new Map<String, String>{
            'mode' => 'payment',
            'success_url' => site + '/payment-result?session_id={CHECKOUT_SESSION_ID}',
            'cancel_url' => site + '/my-bookings',
            'client_reference_id' => b.Id,
            'metadata[booking_id]' => b.Id,
            'metadata[booking_number]' => b.Name,
            'line_items[0][quantity]' => '1',
            'line_items[0][price_data][currency]' => cfg.Currency_Code__c,
            'line_items[0][price_data][unit_amount]' => String.valueOf(minor),
            'line_items[0][price_data][product_data][name]' =>
                b.Name + ' - ' + b.Vehicle__r.Make__c + ' ' + b.Vehicle__r.Model__c + ' (incl. GST and refundable deposit)'
        };
        HttpRequest req = request('POST', '/v1/checkout/sessions');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        // Stripe replays the same session for retries of the same booking -> no duplicate sessions (TDD 10.4)
        req.setHeader('Idempotency-Key', 'booking-' + b.Id);
        req.setBody(formEncode(form));
        Map<String, Object> session = send(req, 'Payment service error. Please try again.');

        Payment__c p = new Payment__c(
            Booking__c = b.Id,
            Amount__c = amount,
            Currency_Code__c = cfg.Currency_Code__c.toUpperCase(),
            Stripe_Session_Id__c = (String) session.get('id'),
            Status__c = PAY_INITIATED
        );
        BookingRepository.upsertPayment(p); // upsert on the unique session id = idempotent

        CheckoutResult r = new CheckoutResult();
        r.url = (String) session.get('url');
        r.sessionId = (String) session.get('id');
        return r;
    }

    // ------------------------------------------------------------------ verification

    public static RentalDtos.PaymentResultDTO verifyAndConfirm(String sessionId) {
        return verifyAndConfirm(sessionId, CustomerContext.requireCustomer());
    }

    /**
     * Retrieves the Checkout Session from Stripe and, if paid, marks the Payment Succeeded and confirms the
     * booking. The browser redirect is never trusted (D5). Idempotent: an already Succeeded payment returns
     * immediately without a callout, so no second payment / email is produced (TC-16).
     */
    public static RentalDtos.PaymentResultDTO verifyAndConfirm(String sessionId, Id contactId) {
        if (String.isBlank(sessionId) || !Pattern.matches('cs_[A-Za-z0-9_]{5,200}', sessionId)) {
            throw new StripeException('Invalid payment reference.');
        }
        Payment__c p = BookingRepository.paymentBySession(sessionId);
        if (p == null || p.Booking__r.Customer__c != contactId) {
            throw new StripeException('Payment not found.');
        }
        if (p.Status__c == PAY_SUCCEEDED || p.Status__c == PAY_REFUNDED) {
            return result(PAY_SUCCEEDED, 'Payment received. Your booking is confirmed.', p.Booking__c);
        }

        Map<String, Object> session = send(
            request('GET', '/v1/checkout/sessions/' + EncodingUtil.urlEncode(sessionId, 'UTF-8')),
            'We could not check your payment right now. Please refresh this page in a moment.'
        );
        Map<String, Object> metadata = (Map<String, Object>) session.get('metadata');
        String metaBooking = metadata == null ? null : (String) metadata.get('booking_id');
        if (metaBooking == null || CustomerContext.toId(metaBooking) != p.Booking__c) {
            throw new StripeException('This payment does not match your booking.');
        }
        String paymentStatus = (String) session.get('payment_status');
        String sessionStatus = (String) session.get('status');

        if (paymentStatus == 'paid') {
            return markPaidAndConfirm(p, session);
        }
        if (sessionStatus == 'expired') {
            p.Status__c = PAY_FAILED;
            p.Failure_Reason__c = 'Checkout session expired';
            BookingRepository.updatePayments(new List<Payment__c>{ p });
            return result(PAY_FAILED, 'Your payment session expired. Please start the payment again from My Bookings.', p.Booking__c);
        }
        // open / unpaid (e.g. declined card – the customer can retry on Stripe): booking stays Pending Payment
        return result('Pending', 'We are still waiting for your payment to complete.', p.Booking__c);
    }

    private static RentalDtos.PaymentResultDTO markPaidAndConfirm(Payment__c p, Map<String, Object> session) {
        Payment__c locked = BookingRepository.lockPayment(p.Id); // serialise concurrent reloads
        if (locked.Status__c == PAY_SUCCEEDED) {
            return result(PAY_SUCCEEDED, 'Payment received. Your booking is confirmed.', p.Booking__c);
        }
        p.Status__c = PAY_SUCCEEDED;
        p.Paid_At__c = System.now();
        p.Failure_Reason__c = null;
        p.Stripe_Payment_Intent_Id__c = session.get('payment_intent') instanceof String ? (String) session.get('payment_intent') : null;
        if (session.get('amount_total') != null) {
            p.Amount__c = Decimal.valueOf(String.valueOf(session.get('amount_total'))) / 100;
        }
        BookingRepository.updatePayments(new List<Payment__c>{ p });

        try {
            BookingService.confirmAfterPayment(p.Booking__c);
            return result(PAY_SUCCEEDED, 'Payment received. Your booking is confirmed.', p.Booking__c);
        } catch (Exception e) {
            // Money was taken but the booking cannot be confirmed (KYC no longer verified, or the slot was lost
            // after the hold expired). Never lose it silently (NFR-04): record Paid and hand over to staff.
            Booking__c b = BookingRepository.getById(p.Booking__c);
            if (b.Status__c == BookingService.ST_PENDING || b.Status__c == BookingService.ST_EXPIRED) {
                BookingRepository.updateBookings(new List<Booking__c>{ new Booking__c(Id = b.Id, Payment_Status__c = BookingService.PAY_PAID) });
            }
            String reason = RentalErrors.friendlyMessage(e);
            BookingRepository.createStaffTask(
                b,
                'Payment received but booking ' + b.Name + ' not confirmed',
                'Stripe session ' + p.Stripe_Session_Id__c + ' is paid but the booking could not be confirmed: ' + reason +
                ' Confirm manually or refund the customer.'
            );
            return result(
                'Pending',
                'Your payment was received, but the booking needs a quick manual check (' + reason +
                ') Our team will contact you shortly.',
                p.Booking__c
            );
        }
    }

    // ------------------------------------------------------------------ refund

    /** POST /v1/refunds for the given amount; marks the Payment Refunded and the Booking Payment Status Refunded. */
    public static Payment__c refund(Id paymentId, Decimal amount) {
        Payment__c p = BookingRepository.paymentById(paymentId);
        if (p == null || p.Status__c != PAY_SUCCEEDED) {
            throw new StripeException('Only a successful payment can be refunded.');
        }
        if (String.isBlank(p.Stripe_Payment_Intent_Id__c)) {
            throw new StripeException('The payment has no Stripe payment intent to refund.');
        }
        if (amount == null || amount <= 0 || amount > p.Amount__c) {
            throw new StripeException('Invalid refund amount.');
        }
        HttpRequest req = request('POST', '/v1/refunds');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Idempotency-Key', 'refund-' + p.Id);
        req.setBody(
            formEncode(new Map<String, String>{
                'payment_intent' => p.Stripe_Payment_Intent_Id__c,
                'amount' => String.valueOf(PricingService.toMinorUnits(amount)),
                'metadata[booking_id]' => p.Booking__c
            })
        );
        Map<String, Object> refund = send(req, 'Refund could not be processed.');
        p.Status__c = PAY_REFUNDED;
        p.Refund_Amount__c = amount;
        p.Stripe_Refund_Id__c = (String) refund.get('id');
        BookingRepository.updatePayments(new List<Payment__c>{ p });
        BookingRepository.updateBookings(
            new List<Booking__c>{ new Booking__c(Id = p.Booking__c, Payment_Status__c = BookingService.PAY_REFUNDED) }
        );
        return p;
    }

    /** Called by StripeRefundQueueable when a refund callout fails: keep state, record why, alert staff. */
    public static void recordRefundFailure(Id paymentId, Decimal amount, String reason) {
        Payment__c p = BookingRepository.paymentById(paymentId);
        if (p == null) {
            return;
        }
        p.Failure_Reason__c = ('Refund of ' + amount + ' failed: ' + reason).left(255);
        BookingRepository.updatePayments(new List<Payment__c>{ p });
        BookingRepository.createStaffTask(
            BookingRepository.getById(p.Booking__c),
            'Refund failed for payment ' + p.Name,
            'Automatic refund of ' + amount + ' failed: ' + reason + ' Please refund manually in the Stripe dashboard.'
        );
    }

    // ------------------------------------------------------------------ helpers

    private static HttpRequest request(String method, String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Stripe_API' + path);
        req.setMethod(method);
        req.setTimeout(60000);
        return req;
    }

    private static Map<String, Object> send(HttpRequest req, String friendlyError) {
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            RentalErrors.log(e);
            throw new StripeException(friendlyError);
        }
        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'Stripe HTTP ' + res.getStatusCode() + ' for ' + req.getMethod() + ' ' + req.getEndpoint());
            throw new StripeException(friendlyError);
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw new StripeException(friendlyError);
        }
    }

    @TestVisible
    private static String formEncode(Map<String, String> fields) {
        List<String> parts = new List<String>();
        for (String key : fields.keySet()) {
            parts.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(fields.get(key) ?? '', 'UTF-8'));
        }
        return String.join(parts, '&');
    }

    private static RentalDtos.PaymentResultDTO result(String status, String message, Id bookingId) {
        Booking__c b = BookingRepository.getById(bookingId);
        return new RentalDtos.PaymentResultDTO(status, message, b == null ? null : new RentalDtos.BookingDTO(b));
    }
}