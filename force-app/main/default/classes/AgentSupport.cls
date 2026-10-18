/**
 * Formatting helpers for agent / chat responses. Results are short plain text built only from real record
 * values so the LLM has nothing to fill in (TDD 8.4).
 */
public with sharing class AgentSupport {
    public static final String TIME_ZONE = 'Asia/Kolkata';

    public static String inr(Decimal amount) {
        Decimal v = (amount ?? 0).setScale(0, System.RoundingMode.HALF_UP);
        return 'INR ' + v.format();
    }

    public static String dt(Datetime value) {
        return value == null ? '' : value.format('EEE d MMM yyyy, h:mm a', TIME_ZONE) + ' IST';
    }

    public static String time(Datetime value) {
        return value == null ? '' : value.format('h:mm a', TIME_ZONE) + ' IST';
    }

    public static String range(Datetime startDt, Datetime endDt) {
        return dt(startDt) + ' to ' + dt(endDt);
    }

    public static String bookingLine(Booking__c b) {
        String vehicle = b.Vehicle__r == null ? b.Vehicle_Display__c : b.Vehicle__r.Make__c + ' ' + b.Vehicle__r.Model__c;
        return b.Name + ': ' + vehicle + ', ' + range(b.Start_DateTime__c, b.End_DateTime__c) + ', status ' + b.Status__c +
            ', payment ' + b.Payment_Status__c + ', total ' + inr((b.Total_Amount__c ?? 0) + (b.Deposit_Amount__c ?? 0)) +
            ' (incl. GST and refundable deposit)';
    }
}