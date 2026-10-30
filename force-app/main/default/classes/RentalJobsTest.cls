/**
 * Scheduled / batch jobs: hold expiry (TC-08), overdue (TC-22), licence retention (A11), scheduler.
 */
@IsTest
private class RentalJobsTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        TestDataFactory.createVerifiedContact();
    }

    @IsTest
    static void holdExpiryBatchExpires200Holds() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = [SELECT Id FROM Vehicle__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        List<Booking__c> rows = new List<Booking__c>();
        for (Integer i = 0; i < 200; i++) {
            Datetime s = TestDataFactory.future(2 + i, 4);
            Booking__c b = TestDataFactory.buildBooking(c.Id, v.Id, s, s.addHours(20), 'Pending Payment');
            b.Hold_Expires_At__c = System.now().addMinutes(-1);
            rows.add(b);
        }
        TestDataFactory.insertBypassingGuards(rows);
        Test.startTest();
        Database.executeBatch(new BookingHoldExpiryBatch(), 200);
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Booking__c WHERE Status__c = 'Expired']);
    }

    @IsTest
    static void overdueBatchFlagsActiveBookingsPastEnd() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = [SELECT Id FROM Vehicle__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        Booking__c late = TestDataFactory.createBooking(c.Id, v.Id, System.now().addDays(-3), System.now().addHours(-2), 'Active');
        Test.startTest();
        Database.executeBatch(new BookingOverdueBatch(), 200);
        Test.stopTest();
        Assert.isTrue([SELECT Is_Overdue__c FROM Booking__c WHERE Id = :late.Id].Is_Overdue__c, 'TC-22');
    }

    @IsTest
    static void retentionDeletesOldLicenceImage() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = [SELECT Id FROM Vehicle__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        ContentVersion cv = TestDataFactory.createLicenseFile(c.Id);
        c.License_File_Id__c = cv.ContentDocumentId;
        update c;
        Booking__c old = TestDataFactory.createBooking(c.Id, v.Id, System.now().addDays(-45), System.now().addDays(-40), 'Completed');
        old.Actual_Return__c = System.now().addDays(-40);
        TestDataFactory.updateBypassingGuards(new List<SObject>{ old });

        Test.startTest();
        Database.executeBatch(new LicenseRetentionBatch(), 100);
        Test.stopTest();
        Assert.isNull([SELECT License_File_Id__c FROM Contact WHERE Id = :c.Id].License_File_Id__c);
        Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :cv.ContentDocumentId]);
    }

    @IsTest
    static void retentionKeepsImageWhileBookingOpen() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = [SELECT Id FROM Vehicle__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        ContentVersion cv = TestDataFactory.createLicenseFile(c.Id);
        c.License_File_Id__c = cv.ContentDocumentId;
        update c;
        TestDataFactory.createBooking(c.Id, v.Id, TestDataFactory.future(3, 4), TestDataFactory.future(4, 4), 'Confirmed');
        Test.startTest();
        Database.executeBatch(new LicenseRetentionBatch(), 100);
        Test.stopTest();
        Assert.isNotNull([SELECT License_File_Id__c FROM Contact WHERE Id = :c.Id].License_File_Id__c);
    }

    @IsTest
    static void schedulerCreatesAllJobsOnce() {
        List<CronTrigger> before = [
            SELECT CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Rental %' AND State != 'DELETED'
            WITH SYSTEM_MODE
        ];
        Set<String> existingNames = new Set<String>();
        for (CronTrigger ct : before) {
            existingNames.add(ct.CronJobDetail.Name);
        }
        Boolean holdJobsExist = false;
        for (String name : existingNames) {
            holdJobsExist = holdJobsExist || name.startsWith(BookingHoldExpiryBatch.JOB_PREFIX);
        }
        Integer expectedNewGroups = (holdJobsExist ? 0 : 1) +
            (existingNames.contains(BookingOverdueBatch.JOB_NAME) ? 0 : 1) +
            (existingNames.contains(LicenseRetentionBatch.JOB_NAME) ? 0 : 1);

        Test.startTest();
        List<String> first = RentalJobScheduler.scheduleAll();
        List<String> second = RentalJobScheduler.scheduleAll();
        Test.stopTest();
        Assert.areEqual(expectedNewGroups, first.size(), 'only missing logical job groups should be scheduled');
        Assert.areEqual(0, second.size(), 'idempotent');
        Assert.areEqual(14, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Rental %']);
    }

    @IsTest
    static void schedulableEntryPointsRunBatches() {
        TestDataFactory.useTestConfig();
        Test.startTest();
        new BookingHoldExpiryBatch().execute((SchedulableContext) null);
        new BookingOverdueBatch().execute((SchedulableContext) null);
        new LicenseRetentionBatch().execute((SchedulableContext) null);
        Test.stopTest();
        Assert.areEqual(3, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex']);
    }
}