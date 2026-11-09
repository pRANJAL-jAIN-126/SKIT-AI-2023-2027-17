/**
 * Booking engine – TDD 13.2 TC-05 to TC-08, TC-18, TC-25 and negative paths.
 */
@IsTest
private class BookingServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        TestDataFactory.createVerifiedContact();
        TestDataFactory.createContact('Priya', 'Verma', 'Not Submitted');
    }

    private static Vehicle__c car() {
        return [SELECT Id, Branch__c FROM Vehicle__c LIMIT 1];
    }

    private static Contact rahul() {
        return [SELECT Id FROM Contact WHERE FirstName = 'Rahul'];
    }

    private static Contact priya() {
        return [SELECT Id FROM Contact WHERE FirstName = 'Priya'];
    }

    @IsTest
    static void createHoldSetsPendingPaymentAndPrice() {
        TestDataFactory.useTestConfig();
        Datetime s = TestDataFactory.future(3, 4), e = s.addDays(2);
        Test.startTest();
        Booking__c b = BookingService.createHold(rahul().Id, car().Id, s, e, 'Portal', null);
        Test.stopTest();
        Assert.areEqual('Pending Payment', b.Status__c, 'TC-05');
        Assert.areEqual('Unpaid', b.Payment_Status__c);
        Assert.areEqual(2, b.Rental_Days__c);
        Assert.areEqual(8260, b.Total_Amount__c, '3500 x 2 + 18%');
        Assert.areEqual(5000, b.Deposit_Amount__c);
        Assert.areEqual(car().Branch__c, b.Pickup_Branch__c);
        Assert.isTrue(b.Hold_Expires_At__c > System.now().addMinutes(14) && b.Hold_Expires_At__c <= System.now().addMinutes(15));
        Assert.isTrue(b.Name.startsWith('BK-'));
    }

    @IsTest
    static void secondHoldForSameSlotIsRejected() {
        TestDataFactory.useTestConfig();
        Datetime s = TestDataFactory.future(3, 4), e = s.addDays(2);
        BookingService.createHold(rahul().Id, car().Id, s, e, 'Portal', null);
        try {
            BookingService.createHold(priya().Id, car().Id, s.addHours(5), e.addDays(1), 'Agentforce', 'sess-1');
            Assert.fail('TC-07: the second request for an overlapping slot must fail');
        } catch (BookingException ex) {
            Assert.areEqual('Sorry, this vehicle was just booked for those dates.', ex.getMessage());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Booking__c], 'exactly one hold exists');
    }

    @IsTest
    static void triggerBlocksOverlapEvenWithoutService() {
        TestDataFactory.useTestConfig();
        Datetime s = TestDataFactory.future(3, 4), e = s.addDays(2);
        TestDataFactory.createBooking(rahul().Id, car().Id, s, e, 'Confirmed');
        Booking__c dup = TestDataFactory.buildBooking(priya().Id, car().Id, s.addHours(1), e, 'Pending Payment');
        Database.SaveResult sr = Database.insert(dup, false);
        Assert.isFalse(sr.isSuccess(), 'NFR-02: direct API insert of an overlapping hold is blocked');
    }

    @IsTest
    static void maintenanceVehicleCannotBeHeld() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = car();
        v.Status__c = 'Maintenance';
        update v;
        try {
            BookingService.createHold(rahul().Id, v.Id, TestDataFactory.future(3, 4), TestDataFactory.future(4, 4), 'Portal', null);
            Assert.fail();
        } catch (BookingException ex) {
            Assert.areEqual('This vehicle is not available.', ex.getMessage());
        }
    }

    @IsTest
    static void dateGuardrails() {
        TestDataFactory.useTestConfig();
        Id c = rahul().Id, v = car().Id;
        List<List<Datetime>> bad = new List<List<Datetime>>{
            new List<Datetime>{ System.now().addDays(-1), System.now().addDays(1) },
            new List<Datetime>{ TestDataFactory.future(3, 4), TestDataFactory.future(2, 4) },
            new List<Datetime>{ TestDataFactory.future(3, 4), TestDataFactory.future(40, 4) },
            new List<Datetime>{ null, TestDataFactory.future(2, 4) }
        };
        for (List<Datetime> range : bad) {
            try {
                BookingService.createHold(c, v, range[0], range[1], 'Portal', null);
                Assert.fail('invalid range accepted: ' + range);
            } catch (BookingException ex) {
                Assert.isNotNull(ex.getMessage());
            }
        }
        try {
            BookingService.createHold(null, v, TestDataFactory.future(3, 4), TestDataFactory.future(4, 4), 'Portal', null);
            Assert.fail();
        } catch (BookingException ex) {
            Assert.isTrue(ex.getMessage().contains('customer account'));
        }
        try {
            BookingService.createHold(c, c, TestDataFactory.future(3, 4), TestDataFactory.future(4, 4), 'Portal', null);
            Assert.fail();
        } catch (BookingException ex) {
            Assert.areEqual('Please choose a vehicle.', ex.getMessage());
        }
    }

    @IsTest
    static void agentSessionAndSourceRecorded() {
        TestDataFactory.useTestConfig();
        Booking__c b = BookingService.createHold(rahul().Id, car().Id, TestDataFactory.future(3, 4), TestDataFactory.future(4, 4), 'Agentforce', 'agent-session-42');
        Assert.areEqual('Agentforce', b.Source__c);
        Assert.areEqual('agent-session-42', b.Agent_Session_Id__c);
    }

    @IsTest
    static void cancelPendingHoldNoRefund() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(3, 4), TestDataFactory.future(5, 4), 'Pending Payment');
        TestDataFactory.createPayment(b.Id, 'cs_test_open1', 'Initiated', 100, null);
        BookingService.CancelOutcome o = BookingService.cancel(b.Id, rahul().Id);
        Assert.areEqual('Cancelled', o.booking.Status__c);
        Assert.areEqual(0, o.quote.refundAmount);
        Assert.areEqual('Failed', [SELECT Status__c FROM Payment__c].Status__c, 'open checkout payment is closed');
    }

    @IsTest
    static void cancelConfirmedEarlyGivesFullRefund() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Confirmed');
        Payment__c p = TestDataFactory.createPayment(b.Id, 'cs_test_paid1', 'Succeeded', 13260, 'pi_test_1');
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));

        Test.startTest();
        BookingService.CancelOutcome preview = BookingService.previewCancel(b.Id, rahul().Id);
        BookingService.CancelOutcome o = BookingService.cancel(b.Id, rahul().Id);
        Test.stopTest(); // runs StripeRefundQueueable

        Assert.isTrue(preview.quote.fullRefund);
        Assert.areEqual(13260, o.quote.refundAmount, 'TC-18 full refund');
        Payment__c after = [SELECT Status__c, Refund_Amount__c, Stripe_Refund_Id__c FROM Payment__c WHERE Id = :p.Id];
        Assert.areEqual('Refunded', after.Status__c);
        Assert.areEqual(13260, after.Refund_Amount__c);
        Assert.areEqual('re_test_mock123', after.Stripe_Refund_Id__c);
        Booking__c bAfter = [SELECT Status__c, Payment_Status__c, Refund_Amount__c FROM Booking__c WHERE Id = :b.Id];
        Assert.areEqual('Cancelled', bAfter.Status__c);
        Assert.areEqual('Refunded', bAfter.Payment_Status__c);
    }

    @IsTest
    static void lateCancelRetainsOneDay() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, System.now().addHours(5), System.now().addHours(53), 'Confirmed');
        TestDataFactory.createPayment(b.Id, 'cs_test_paid2', 'Succeeded', 13260, 'pi_test_2');
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));
        Test.startTest();
        BookingService.CancelOutcome o = BookingService.cancel(b.Id, rahul().Id);
        Test.stopTest();
        Assert.isFalse(o.quote.fullRefund);
        Assert.areEqual(4130, o.quote.retainedAmount, 'one day = 8260 / 2');
        Assert.areEqual(9130, o.quote.refundAmount);
        Assert.isTrue(o.message.contains('retained'));
    }

    @IsTest
    static void refundFailureKeepsCancellationAndCreatesTask() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Confirmed');
        Payment__c p = TestDataFactory.createPayment(b.Id, 'cs_test_paid3', 'Succeeded', 13260, 'pi_test_3');
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id).withRefundStatus(500));
        Test.startTest();
        BookingService.cancel(b.Id, rahul().Id);
        Test.stopTest();
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
        Payment__c after = [SELECT Status__c, Failure_Reason__c FROM Payment__c WHERE Id = :p.Id];
        Assert.areEqual('Succeeded', after.Status__c, 'payment state preserved for a manual refund');
        Assert.isTrue(after.Failure_Reason__c.startsWith('Refund of'));
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :b.Id], 'staff task created');
    }

    @IsTest
    static void cannotCancelSomeoneElsesBooking() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Confirmed');
        try {
            BookingService.cancel(b.Id, priya().Id);
            Assert.fail('TC-25: foreign booking must not be cancellable');
        } catch (BookingException ex) {
            Assert.areEqual('Booking not found.', ex.getMessage(), 'same message as a missing booking – no data leak');
        }
        Assert.areEqual('Confirmed', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @IsTest
    static void completedBookingCannotBeCancelled() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, System.now().addDays(-5), System.now().addDays(-3), 'Completed');
        try {
            BookingService.cancel(b.Id, rahul().Id);
            Assert.fail();
        } catch (BookingException ex) {
            Assert.areEqual('This booking can no longer be cancelled.', ex.getMessage());
        }
    }

    @IsTest
    static void confirmRequiresVerifiedKyc() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(priya().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Pending Payment');
        try {
            BookingService.confirmAfterPayment(b.Id);
            Assert.fail('FR-07: unverified customer cannot be confirmed');
        } catch (BookingException ex) {
            Assert.isTrue(ex.getMessage().contains('not verified'));
        }
    }

    @IsTest
    static void confirmIsIdempotentAndHandlesLatePayment() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Expired');
        Booking__c confirmed = BookingService.confirmAfterPayment(b.Id);
        Assert.areEqual('Confirmed', confirmed.Status__c, 'late payment on an expired hold still confirms when the car is free');
        Assert.areEqual('Paid', confirmed.Payment_Status__c);
        Assert.areEqual('Confirmed', BookingService.confirmAfterPayment(b.Id).Status__c, 'idempotent');
    }

    @IsTest
    static void latePaymentLosesSlotWhenRebooked() {
        TestDataFactory.useTestConfig();
        Datetime s = TestDataFactory.future(5, 4), e = TestDataFactory.future(7, 4);
        Booking__c expired = TestDataFactory.createBooking(rahul().Id, car().Id, s, e, 'Expired');
        TestDataFactory.createBooking(priya().Id, car().Id, s, e, 'Confirmed');
        try {
            BookingService.confirmAfterPayment(expired.Id);
            Assert.fail();
        } catch (BookingException ex) {
            Assert.isTrue(ex.getMessage().contains('booked by someone else'));
        }
    }

    @IsTest
    static void expireHoldsMarksBookingsAndPayments() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Pending Payment');
        b.Hold_Expires_At__c = System.now().addMinutes(-1);
        TestDataFactory.updateBypassingGuards(new List<SObject>{ b });
        TestDataFactory.createPayment(b.Id, 'cs_test_open2', 'Initiated', 100, null);
        Integer n = BookingService.expireHolds([SELECT Id, Status__c, Payment_Status__c, Hold_Expires_At__c FROM Booking__c]);
        Assert.areEqual(1, n);
        Assert.areEqual('Expired', [SELECT Status__c FROM Booking__c].Status__c);
        Assert.areEqual('Failed', [SELECT Status__c FROM Payment__c].Status__c);
        Assert.areEqual(0, BookingService.expireHolds(new List<Booking__c>()));
    }

    @IsTest
    static void myBookingsAndFlags() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(5, 4), TestDataFactory.future(7, 4), 'Pending Payment');
            List<Booking__c> mine = BookingService.bookingsForCustomer(rahul().Id);
            Assert.areEqual(1, mine.size());
            Assert.isTrue(BookingService.isPayable(mine[0]));
            Assert.isTrue(BookingService.isCancellable(mine[0]));
            Assert.areEqual(0, BookingService.bookingsForCustomer(priya().Id).size());
            Assert.areEqual('BK-1042', BookingRepository.normaliseBookingNumber('bk 1042'));
            Assert.isNull(BookingRepository.normaliseBookingNumber('abc'));
            Assert.isNotNull(BookingRepository.getOwnedByNumber(rahul().Id, b.Id == null ? null : [SELECT Name FROM Booking__c].Name));
        }
    }
}