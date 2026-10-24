/**
 * Price / late fee / refund rules – TDD Appendix C, A4, A5.
 */
@IsTest
private class PricingServiceTest {
    private static Vehicle__c car() {
        return new Vehicle__c(Daily_Rate__c = 3800, Security_Deposit__c = 5000);
    }

    @IsTest
    static void calculatesDaysSubtotalTaxDeposit() {
        TestDataFactory.useTestConfig();
        Datetime s = Datetime.newInstanceGmt(2030, 1, 4, 4, 30, 0);
        PricingService.Quote q = PricingService.calculate(car(), s, s.addDays(3));
        Assert.areEqual(3, q.days);
        Assert.areEqual(11400, q.subtotal, 'TDD 8.5: Kia Carens 3 days = INR 11,400');
        Assert.areEqual(2052, q.tax);
        Assert.areEqual(13452, q.total);
        Assert.areEqual(5000, q.deposit);
        Assert.areEqual(18452, q.grandTotal);
        Assert.areEqual(1845200L, PricingService.toMinorUnits(q.grandTotal), 'Stripe amount in paise');
    }

    @IsTest
    static void partialDayRoundsUpAndMinimumIsOneDay() {
        TestDataFactory.useTestConfig();
        Datetime s = Datetime.newInstanceGmt(2030, 1, 4, 4, 0, 0);
        Assert.areEqual(1, PricingService.calculate(car(), s, s.addHours(2)).days, 'minimum 1 day');
        Assert.areEqual(2, PricingService.calculate(car(), s, s.addHours(25)).days, 'ceil(25/24) = 2');
    }

    @IsTest
    static void invalidRangeRejected() {
        Datetime s = Datetime.newInstanceGmt(2030, 1, 4, 4, 0, 0);
        try {
            PricingService.calculate(car(), s, s);
            Assert.fail('zero-length range must fail');
        } catch (BookingException e) {
            Assert.isTrue(e.getMessage().contains('valid pickup'));
        }
    }

    @IsTest
    static void lateFeePerStartedHour() {
        TestDataFactory.useTestConfig();
        Datetime endDt = Datetime.newInstanceGmt(2030, 1, 7, 4, 0, 0);
        Booking__c b = new Booking__c(End_DateTime__c = endDt, Vehicle__r = new Vehicle__c(Daily_Rate__c = 4000));
        Assert.areEqual(0, PricingService.lateFee(b, endDt.addMinutes(-5)), 'on time');
        Assert.areEqual(400, PricingService.lateFee(b, endDt.addMinutes(10)), '1 started hour x 10% x 4000');
        Assert.areEqual(1200, PricingService.lateFee(b, endDt.addMinutes(150)), '3 started hours');
        Assert.areEqual(0, PricingService.lateFee(null, endDt));
    }

    @IsTest
    static void refundRules() {
        TestDataFactory.useTestConfig();
        Datetime start = System.now().addDays(5);
        Booking__c b = new Booking__c(Start_DateTime__c = start, Rental_Days__c = 3, Total_Amount__c = 13452);
        PricingService.RefundQuote early = PricingService.refundQuote(b, 18452, System.now());
        Assert.isTrue(early.fullRefund, 'TC-18: more than 24 h before start -> full refund');
        Assert.areEqual(18452, early.refundAmount);

        PricingService.RefundQuote late = PricingService.refundQuote(b, 18452, start.addHours(-2));
        Assert.isFalse(late.fullRefund);
        Assert.areEqual(4484, late.retainedAmount, 'one day of the rent (incl. tax) is retained');
        Assert.areEqual(13968, late.refundAmount);

        PricingService.RefundQuote unpaid = PricingService.refundQuote(b, null, System.now());
        Assert.areEqual(0, unpaid.refundAmount);
    }
}