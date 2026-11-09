/**
 * Price, late-fee and refund calculation (TDD Appendix C, 7.5, A4, A5). Pure calculation – no SOQL/DML.
 */
public with sharing class PricingService {
    public class Quote {
        @AuraEnabled public Integer days;
        @AuraEnabled public Decimal dailyRate;
        @AuraEnabled public Decimal subtotal;
        @AuraEnabled public Decimal tax;
        @AuraEnabled public Decimal deposit;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Decimal grandTotal;
    }

    public class RefundQuote {
        public Decimal paidAmount = 0;
        public Decimal refundAmount = 0;
        public Decimal retainedAmount = 0;
        public Boolean fullRefund = true;
    }

    /** days = max(1, ceil(hours/24)); subtotal = rate x days; tax = subtotal x Tax_Rate; total = subtotal + tax. */
    public static Quote calculate(Vehicle__c v, Datetime startDt, Datetime endDt) {
        if (v == null || startDt == null || endDt == null || endDt <= startDt) {
            throw new BookingException('Please choose a valid pickup and return time.');
        }
        Rental_Config__mdt cfg = RentalConfig.get();
        Quote q = new Quote();
        q.days = rentalDays(startDt, endDt);
        q.dailyRate = v.Daily_Rate__c ?? 0;
        q.subtotal = money(q.dailyRate * q.days);
        q.tax = money(q.subtotal * cfg.Tax_Rate__c);
        q.total = q.subtotal + q.tax;
        q.deposit = money(v.Security_Deposit__c ?? 0);
        q.grandTotal = q.total + q.deposit;
        return q;
    }

    public static Integer rentalDays(Datetime startDt, Datetime endDt) {
        Decimal hours = Decimal.valueOf(endDt.getTime() - startDt.getTime()) / 3600000;
        return Math.max(1, (hours / 24).round(System.RoundingMode.CEILING).intValue());
    }

    /** late_fee = Daily_Rate x Late_Fee_Per_Hour x ceil(hours late). Needs Vehicle__r.Daily_Rate__c. */
    public static Decimal lateFee(Booking__c b, Datetime actualReturn) {
        if (b == null || actualReturn == null || b.End_DateTime__c == null || actualReturn <= b.End_DateTime__c) {
            return 0;
        }
        Decimal rate = b.Vehicle__r?.Daily_Rate__c ?? 0;
        Decimal hoursLate = Decimal.valueOf(actualReturn.getTime() - b.End_DateTime__c.getTime()) / 3600000;
        Integer billable = hoursLate.round(System.RoundingMode.CEILING).intValue();
        return money(rate * RentalConfig.get().Late_Fee_Per_Hour__c * billable);
    }

    /**
     * Cancellation rule (A4): more than Free_Cancel_Hours before start -> full refund; otherwise one day's
     * rent (Total / Rental_Days, tax included) is retained. Deposit is always refunded.
     */
    public static RefundQuote refundQuote(Booking__c b, Decimal paidAmount, Datetime nowDt) {
        RefundQuote rq = new RefundQuote();
        rq.paidAmount = paidAmount ?? 0;
        if (rq.paidAmount <= 0) {
            return rq;
        }
        Integer freeHours = RentalConfig.get().Free_Cancel_Hours__c.intValue();
        if (nowDt < b.Start_DateTime__c.addHours(-freeHours)) {
            rq.refundAmount = rq.paidAmount;
            return rq;
        }
        Decimal days = (b.Rental_Days__c == null || b.Rental_Days__c < 1) ? 1 : b.Rental_Days__c;
        Decimal oneDay = money((b.Total_Amount__c ?? 0) / days);
        rq.retainedAmount = Math.min(oneDay, rq.paidAmount);
        rq.refundAmount = rq.paidAmount - rq.retainedAmount;
        rq.fullRefund = false;
        return rq;
    }

    /** Stripe amounts are in the smallest currency unit (paise for INR). */
    public static Long toMinorUnits(Decimal amount) {
        return (amount * 100).setScale(0, System.RoundingMode.HALF_UP).longValue();
    }

    public static Decimal money(Decimal value) {
        return (value ?? 0).setScale(2, System.RoundingMode.HALF_UP);
    }
}