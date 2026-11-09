/**
 * Hourly overdue detection (TDD 7.5, FR-13): Active bookings whose planned End_DateTime__c has passed are
 * flagged Is_Overdue__c = true. Flow Booking_Overdue_Check notifies the branch manager when the flag flips.
 * Implemented in Apex because scheduled flows can only run daily/weekly (plan D-07).
 */
public with sharing class BookingOverdueBatch implements Database.Batchable<SObject>, Schedulable {
    public static final String JOB_NAME = 'Rental Overdue Check (hourly)';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime nowDt = System.now();
        return Database.getQueryLocator(
            [
                SELECT Id, Is_Overdue__c
                FROM Booking__c
                WHERE Status__c = 'Active' AND End_DateTime__c < :nowDt AND Is_Overdue__c = FALSE
                WITH SYSTEM_MODE
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Booking__c> scope) {
        for (Booking__c b : scope) {
            b.Is_Overdue__c = true;
        }
        BookingRepository.updateBookings(scope);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'BookingOverdueBatch finished');
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new BookingOverdueBatch(), 200);
    }

    public static Id scheduleHourly() {
        return System.schedule(JOB_NAME, '0 0 * * * ?', new BookingOverdueBatch());
    }
}