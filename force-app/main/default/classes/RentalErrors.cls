/**
 * Converts exceptions into user-friendly AuraHandledExceptions (TDD 9.2, 10.4).
 * Business exceptions keep their message; anything unexpected becomes a generic message and is logged
 * (masked) to the debug log. Stack traces never reach the browser.
 */
public with sharing class RentalErrors {
    public static final String GENERIC = 'Something went wrong. Please try again in a moment.';

    public static AuraHandledException toAura(Exception e) {
        String msg = friendlyMessage(e);
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    public static String friendlyMessage(Exception e) {
        if (e instanceof AuraHandledException) {
            return e.getMessage();
        }
        if (e instanceof BookingException || e instanceof KycException || e instanceof StripeException ||
            e instanceof InspectionException) {
            return e.getMessage();
        }
        if (e instanceof DmlException) {
            DmlException d = (DmlException) e;
            StatusCode code = d.getDmlType(0);
            if (code == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION || code == StatusCode.DUPLICATE_VALUE) {
                return d.getDmlMessage(0);
            }
            if (code == StatusCode.UNABLE_TO_LOCK_ROW) {
                return 'This vehicle is being booked by someone else right now. Please try again.';
            }
        }
        if (e instanceof QueryException && e.getMessage() != null && e.getMessage().contains('Record Currently Unavailable')) {
            return 'This vehicle is being booked by someone else right now. Please try again.';
        }
        log(e);
        return GENERIC;
    }

    public static void log(Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'SmartCarRental error ' + e.getTypeName() + ': ' + DataMasking.maskLicenseNumbersIn(e.getMessage())
        );
    }
}