/**
 * Privacy / retention (TDD 11.3, A11): the licence image is used only for KYC and is deleted
 * License_Retention_Days__c days after the customer's last booking completes, provided the customer has no
 * open booking. The extracted KYC fields stay on the Contact; only the image file is removed.
 */
public with sharing class LicenseRetentionBatch implements Database.Batchable<SObject>, Schedulable {
    public static final String JOB_NAME = 'Rental Licence Retention (daily)';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id, License_File_Id__c FROM Contact WHERE License_File_Id__c != NULL WITH SYSTEM_MODE]);
    }

    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        Datetime cutoff = System.now().addDays(-RentalConfig.get().License_Retention_Days__c.intValue());
        Map<Id, Contact> byId = new Map<Id, Contact>(scope);
        Set<Id> blocked = new Set<Id>();
        Set<Id> eligible = new Set<Id>();
        for (Booking__c b : [
            SELECT Customer__c, Status__c, Actual_Return__c, End_DateTime__c
            FROM Booking__c
            WHERE Customer__c IN :byId.keySet()
            WITH SYSTEM_MODE
        ]) {
            if (b.Status__c == 'Pending Payment' || b.Status__c == 'Confirmed' || b.Status__c == 'Active') {
                blocked.add(b.Customer__c);
            } else if (b.Status__c == 'Completed') {
                Datetime returned = b.Actual_Return__c ?? b.End_DateTime__c;
                if (returned != null && returned < cutoff) {
                    eligible.add(b.Customer__c);
                } else {
                    blocked.add(b.Customer__c);
                }
            }
        }
        eligible.removeAll(blocked);
        if (eligible.isEmpty()) {
            return;
        }
        Set<Id> docIds = new Set<Id>();
        List<Contact> toClear = new List<Contact>();
        for (Id contactId : eligible) {
            Id docId = CustomerContext.toId(byId.get(contactId).License_File_Id__c);
            if (docId != null) {
                docIds.add(docId);
            }
            toClear.add(new Contact(Id = contactId, License_File_Id__c = null));
        }
        List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Id IN :docIds WITH SYSTEM_MODE];
        if (!docs.isEmpty()) {
            Database.delete(docs, false, AccessLevel.SYSTEM_MODE);
        }
        update as system toClear;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'LicenseRetentionBatch finished');
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LicenseRetentionBatch(), 100);
    }

    public static Id scheduleDaily() {
        return System.schedule(JOB_NAME, '0 0 3 * * ?', new LicenseRetentionBatch());
    }
}