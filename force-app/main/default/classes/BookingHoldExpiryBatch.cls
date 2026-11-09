/**
 * Expires unpaid holds (TDD 6.4: Pending Payment -> Expired when Hold_Expires_At__c has passed; Initiated
 * payments -> Failed). Scheduled every 5 minutes – see scheduleEvery5Minutes() (plan D-08).
 */
public with sharing class BookingHoldExpiryBatch implements Database.Batchable<SObject>, Schedulable {
    public static final String JOB_PREFIX = 'Rental Hold Expiry ';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime nowDt = System.now();
        return Database.getQueryLocator(
            [
                SELECT Id, Status__c, Payment_Status__c, Hold_Expires_At__c
                FROM Booking__c
                WHERE Status__c = 'Pending Payment' AND Hold_Expires_At__c < :nowDt AND Payment_Status__c != 'Paid'
                WITH SYSTEM_MODE
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Booking__c> scope) {
        BookingService.expireHolds(scope);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'BookingHoldExpiryBatch finished');
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new BookingHoldExpiryBatch(), 200);
    }

    /** Apex cron cannot express "every 5 minutes" in one job, so 12 hourly jobs are created (minute 0,5,...,55). */
    public static List<Id> scheduleEvery5Minutes() {
        List<Id> ids = new List<Id>();
        for (Integer minute = 0; minute < 60; minute += 5) {
            ids.add(System.schedule(JOB_PREFIX + String.valueOf(minute).leftPad(2, '0'), '0 ' + minute + ' * * * ?', new BookingHoldExpiryBatch()));
        }
        return ids;
    }
}