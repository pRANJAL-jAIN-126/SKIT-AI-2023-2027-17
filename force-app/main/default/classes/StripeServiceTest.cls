/**
 * Stripe Checkout – TDD 13.2 TC-14 to TC-17, idempotency, failure paths (TDD 10.4).
 */
@IsTest
private class StripeServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        Vehicle__c v = TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        Contact verified = TestDataFactory.createVerifiedContact();
        TestDataFactory.createContact('Priya', 'Verma', 'Not Submitted');
        TestDataFactory.createBooking(verified.Id, v.Id, TestDataFactory.future(3, 4), TestDataFactory.future(5, 4), 'Pending Payment');
    }

    private static Booking__c booking() {
        return [SELECT Id, Customer__c, Grand_Total__c FROM Booking__c LIMIT 1];
    }

    @IsTest
    static void createsCheckoutSessionAndInitiatedPayment() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));
        Test.startTest();
        StripeService.CheckoutResult r = StripeService.createCheckoutSession(b.Id, b.Customer__c);
        Test.stopTest();

        Assert.areEqual('cs_test_mock123', r.sessionId);
        Assert.isTrue(r.url.startsWith('https://checkout.stripe.com/'));
        Payment__c p = [SELECT Status__c, Amount__c, Currency_Code__c FROM Payment__c];
        Assert.areEqual('Initiated', p.Status__c);
        // a retry replays the same Stripe session (Idempotency-Key) and upserts on the unique session id
        BookingRepository.upsertPayment(new Payment__c(Booking__c = b.Id, Stripe_Session_Id__c = r.sessionId, Status__c = 'Initiated'));
        Assert.areEqual(1, [SELECT COUNT() FROM Payment__c], 'no duplicate payment');
        Assert.areEqual(b.Grand_Total__c, p.Amount__c);
        Assert.areEqual('INR', p.Currency_Code__c);
        HttpRequest req = StripeHttpMock.requests[0];
        Assert.areEqual('booking-' + b.Id, req.getHeader('Idempotency-Key'));
        Assert.isTrue(req.getEndpoint().startsWith('callout:Stripe_API'), 'key only in the Named Credential');
        String body = EncodingUtil.urlDecode(req.getBody(), 'UTF-8');
        Assert.isTrue(body.contains('line_items[0][price_data][unit_amount]=' + PricingService.toMinorUnits(b.Grand_Total__c)), 'amount in paise');
        Assert.isTrue(body.contains('success_url=' + TestDataFactory.SITE + '/payment-result?session_id={CHECKOUT_SESSION_ID}'));
        Assert.isTrue(body.contains('metadata[booking_id]=' + b.Id));
    }

    @IsTest
    static void paidSessionConfirmsBookingOnceOnly() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', b.Grand_Total__c, null);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));
        Test.startTest();
        RentalDtos.PaymentResultDTO first = StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
        Integer callsAfterFirst = StripeHttpMock.requests.size();
        RentalDtos.PaymentResultDTO second = StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
        Test.stopTest();

        Assert.areEqual('Succeeded', first.status, 'TC-14');
        Assert.areEqual('Confirmed', first.booking.status);
        Assert.areEqual('Paid', first.booking.paymentStatus);
        Assert.areEqual('Succeeded', second.status, 'TC-16: reload is safe');
        Assert.areEqual(callsAfterFirst, StripeHttpMock.requests.size(), 'no second Stripe call');
        Assert.areEqual(1, [SELECT COUNT() FROM Payment__c], 'one payment record');
        Payment__c p = [SELECT Status__c, Stripe_Payment_Intent_Id__c, Paid_At__c, Amount__c FROM Payment__c];
        Assert.areEqual('Succeeded', p.Status__c);
        Assert.areEqual('pi_test_mock123', p.Stripe_Payment_Intent_Id__c);
        Assert.areEqual(20000, p.Amount__c, 'amount taken from Stripe (paise -> INR)');
        Assert.isNotNull(p.Paid_At__c);
    }

    @IsTest
    static void declinedCardLeavesBookingPending() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', b.Grand_Total__c, null);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.unpaid(b.Id));
        Test.startTest();
        RentalDtos.PaymentResultDTO r = StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
        Test.stopTest();
        Assert.areEqual('Pending', r.status, 'TC-15');
        Assert.areEqual('Pending Payment', [SELECT Status__c FROM Booking__c].Status__c);
    }

    @IsTest
    static void expiredSessionMarksPaymentFailed() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', b.Grand_Total__c, null);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.expired(b.Id));
        Test.startTest();
        RentalDtos.PaymentResultDTO r = StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
        Test.stopTest();
        Assert.areEqual('Failed', r.status);
        Assert.areEqual('Failed', [SELECT Status__c FROM Payment__c].Status__c);
    }

    @IsTest
    static void checkoutBlockedWithoutKyc() {
        TestDataFactory.useTestConfig();
        Contact priya = [SELECT Id FROM Contact WHERE FirstName = 'Priya'];
        Booking__c b = TestDataFactory.createBooking(priya.Id, [SELECT Id FROM Vehicle__c].Id, TestDataFactory.future(10, 4), TestDataFactory.future(11, 4), 'Pending Payment');
        try {
            StripeService.createCheckoutSession(b.Id, priya.Id);
            Assert.fail('TC-17');
        } catch (StripeException e) {
            Assert.areEqual('Please verify your driving licence before paying.', e.getMessage());
        }
        Assert.areEqual(0, StripeHttpMock.requests.size(), 'no Stripe call');
    }

    @IsTest
    static void checkoutGuards() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        Contact priya = [SELECT Id FROM Contact WHERE FirstName = 'Priya'];
        try {
            StripeService.createCheckoutSession(b.Id, priya.Id);
            Assert.fail('foreign booking');
        } catch (StripeException e) {
            Assert.areEqual('Booking not found.', e.getMessage());
        }
        b.Hold_Expires_At__c = System.now().addMinutes(-1);
        TestDataFactory.updateBypassingGuards(new List<SObject>{ b });
        try {
            StripeService.createCheckoutSession(b.Id, b.Customer__c);
            Assert.fail('expired hold');
        } catch (StripeException e) {
            Assert.isTrue(e.getMessage().contains('expired'));
        }
        b.Status__c = 'Cancelled';
        TestDataFactory.updateBypassingGuards(new List<SObject>{ b });
        try {
            StripeService.createCheckoutSession(b.Id, b.Customer__c);
            Assert.fail('cancelled');
        } catch (StripeException e) {
            Assert.areEqual('Booking is not awaiting payment.', e.getMessage());
        }
    }

    @IsTest
    static void stripeOutageKeepsBookingPending() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id).withCreateStatus(500));
        Test.startTest();
        try {
            StripeService.createCheckoutSession(b.Id, b.Customer__c);
            Assert.fail();
        } catch (StripeException e) {
            Assert.isTrue(e.getMessage().contains('try again'));
        }
        Test.stopTest();
        Assert.areEqual('Pending Payment', [SELECT Status__c FROM Booking__c].Status__c, 'NFR-04');
        Assert.areEqual(0, [SELECT COUNT() FROM Payment__c]);
    }

    @IsTest
    static void timeoutOnVerifyIsFriendly() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', b.Grand_Total__c, null);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id).withTimeout());
        Test.startTest();
        try {
            StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
            Assert.fail();
        } catch (StripeException e) {
            Assert.isTrue(e.getMessage().contains('refresh'));
        }
        Test.stopTest();
    }

    @IsTest
    static void verifyRejectsForeignOrForgedSessions() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        Contact priya = [SELECT Id FROM Contact WHERE FirstName = 'Priya'];
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', b.Grand_Total__c, null);
        for (String bad : new List<String>{ null, 'pi_123', 'cs_x"; DROP' }) {
            try {
                StripeService.verifyAndConfirm(bad, b.Customer__c);
                Assert.fail(bad);
            } catch (StripeException e) {
                Assert.areEqual('Invalid payment reference.', e.getMessage());
            }
        }
        try {
            StripeService.verifyAndConfirm('cs_test_mock123', priya.Id);
            Assert.fail('TC-25: another customer cannot confirm');
        } catch (StripeException e) {
            Assert.areEqual('Payment not found.', e.getMessage());
        }
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(priya.Id)); // metadata points elsewhere
        Test.startTest();
        try {
            StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
            Assert.fail('metadata mismatch');
        } catch (StripeException e) {
            Assert.isTrue(e.getMessage().contains('does not match'));
        }
        Test.stopTest();
    }

    @IsTest
    static void paidButKycRevokedHandsOverToStaff() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        update new Contact(Id = b.Customer__c, KYC_Status__c = 'Rejected');
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', b.Grand_Total__c, null);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));
        Test.startTest();
        RentalDtos.PaymentResultDTO r = StripeService.verifyAndConfirm('cs_test_mock123', b.Customer__c);
        Test.stopTest();
        Assert.areEqual('Pending', r.status);
        Booking__c after = [SELECT Status__c, Payment_Status__c FROM Booking__c];
        Assert.areEqual('Pending Payment', after.Status__c, 'never confirmed without KYC (FR-07)');
        Assert.areEqual('Paid', after.Payment_Status__c, 'money is not lost (NFR-04)');
        Assert.areEqual('Succeeded', [SELECT Status__c FROM Payment__c].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :b.Id]);
    }

    @IsTest
    static void refundGuards() {
        TestDataFactory.useTestConfig();
        Booking__c b = booking();
        Payment__c initiated = TestDataFactory.createPayment(b.Id, 'cs_test_r1', 'Initiated', 100, null);
        Payment__c noIntent = TestDataFactory.createPayment(b.Id, 'cs_test_r2', 'Succeeded', 100, null);
        Payment__c ok = TestDataFactory.createPayment(b.Id, 'cs_test_r3', 'Succeeded', 100, 'pi_1');
        Map<Id, Decimal> cases = new Map<Id, Decimal>{ initiated.Id => 50, noIntent.Id => 50 };
        for (Id pid : cases.keySet()) {
            try {
                StripeService.refund(pid, cases.get(pid));
                Assert.fail();
            } catch (StripeException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
        try {
            StripeService.refund(ok.Id, 500);
            Assert.fail('more than paid');
        } catch (StripeException e) {
            Assert.areEqual('Invalid refund amount.', e.getMessage());
        }
        StripeService.recordRefundFailure(null, 1, 'x');
    }
    @IsTest
static void successfulPaymentConfirmsBooking() {
    TestDataFactory.useTestConfig();

    Booking__c b = booking();

    TestDataFactory.createPayment(
        b.Id,
        'cs_test_success123',
        'Initiated',
        b.Grand_Total__c,
        null
    );

    Test.setMock(
        HttpCalloutMock.class,
        StripeHttpMock.paid(b.Id)
    );

    Test.startTest();

    RentalDtos.PaymentResultDTO result =
        StripeService.verifyAndConfirm(
            'cs_test_success123',
            b.Customer__c
        );

    Test.stopTest();

    System.assertEquals('Succeeded', result.status);

    Booking__c updatedBooking = [
        SELECT Status__c, Payment_Status__c
        FROM Booking__c
        WHERE Id = :b.Id
    ];

    System.assertEquals('Confirmed', updatedBooking.Status__c);
    System.assertEquals('Paid', updatedBooking.Payment_Status__c);

    Payment__c payment = [
        SELECT Status__c
        FROM Payment__c
        WHERE Booking__c = :b.Id
        LIMIT 1
    ];

    System.assertEquals('Succeeded', payment.Status__c);
}
}