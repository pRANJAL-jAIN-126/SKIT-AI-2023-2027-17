@IsTest
private class KycReviewControllerTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        Vehicle__c v = TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        Contact c = TestDataFactory.createContact('Ritvik', 'Jolia', 'Not Submitted');
        TestDataFactory.useTestConfig();
        TestDataFactory.createBooking(c.Id, v.Id, TestDataFactory.future(5, 4), TestDataFactory.future(8, 4), 'Pending Payment');
        // customer uploaded a licence while OCR was unavailable -> manual review (flow creates the review Task)
        Id cvId = KycService.saveLicenseImage(c.Id, 'licence.jpg', EncodingUtil.base64Encode(Blob.valueOf('img')));
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvId].ContentDocumentId;
        update new Contact(Id = c.Id, KYC_Status__c = 'Pending Review', License_File_Id__c = docId);
        insert new KYC_Log__c(Contact__c = c.Id, Status__c = 'Error', Reason__c = OcrHttp.MSG_BUSY);
    }

    private static Contact ritvik() {
        return [SELECT Id, KYC_Status__c, KYC_Verified_At__c, License_Expiry__c, Birthdate, Driving_License_Number__c FROM Contact WHERE LastName = 'Jolia'];
    }

    @IsTest
    static void pendingListShowsPhotoReasonAndRequiredValidity() {
        TestDataFactory.useTestConfig();
        List<KycReviewController.PendingCustomer> rows = KycReviewController.getPendingReviews();
        Assert.areEqual(1, rows.size());
        KycReviewController.PendingCustomer p = rows[0];
        Assert.areEqual(ritvik().Id, p.contactId);
        Assert.isTrue(p.photoUrl.contains('/sfc/servlet.shepherd/version/renditionDownload'), p.photoUrl);
        Assert.isTrue(p.downloadUrl.contains('/sfc/servlet.shepherd/version/download/'));
        Assert.isTrue(p.reason.contains('Automatic check was not available'), p.reason);
        Assert.areEqual(1, p.openBookings);
        Assert.areEqual(TestDataFactory.future(8, 4).date(), p.mustBeValidUntil, 'staff see the return date to check against');
    }

    @IsTest
    static void approveVerifiesLogsAndClosesTask() {
        TestDataFactory.useTestConfig();
        Id contactId = ritvik().Id;
        Integer openTasksBefore = [SELECT COUNT() FROM Task WHERE WhoId = :contactId AND IsClosed = FALSE];

        KycReviewController.approve(contactId, Date.newInstance(2045, 8, 10), Date.newInstance(2005, 8, 11), 'rj59 2023 0022340');

        Contact c = ritvik();
        Assert.areEqual('Verified', c.KYC_Status__c);
        Assert.isNotNull(c.KYC_Verified_At__c);
        Assert.areEqual(Date.newInstance(2045, 8, 10), c.License_Expiry__c);
        Assert.areEqual('RJ5920230022340', c.Driving_License_Number__c);
        KYC_Log__c log = [SELECT Status__c, Reason__c FROM KYC_Log__c WHERE Contact__c = :contactId ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
        Assert.areEqual('Verified', log.Status__c);
        Assert.isTrue(log.Reason__c.startsWith('Approved manually by'));
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhoId = :contactId AND IsClosed = FALSE AND Subject LIKE 'Review licence%'],
            'review task closed (was ' + openTasksBefore + ' open)');
        Booking__c b = [SELECT End_DateTime__c, Customer__r.KYC_Status__c, Customer__r.License_Expiry__c FROM Booking__c LIMIT 1];
        Assert.isTrue(BookingService.hasLicenseValidThrough(b.Customer__r, b), 'customer can now pay');
        Assert.areEqual(0, KycReviewController.getPendingReviews().size(), 'removed from the queue');
    }

    @IsTest
    static void approveRequiresFutureExpiryAndMinimumAge() {
        TestDataFactory.useTestConfig();
        Id contactId = ritvik().Id;
        for (Date bad : new List<Date>{ null, Date.today() }) {
            try {
                KycReviewController.approve(contactId, bad, null, null);
                Assert.fail('expiry required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('expiry date'), e.getMessage());
            }
        }
        try {
            KycReviewController.approve(contactId, Date.today().addYears(10), Date.today().addYears(-17), null);
            Assert.fail('under age');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('years old'), e.getMessage());
        }
        Assert.areEqual('Pending Review', ritvik().KYC_Status__c, 'nothing changed');
    }

    @IsTest
    static void rejectNeedsReasonThenRejectsAndLogs() {
        TestDataFactory.useTestConfig();
        Id contactId = ritvik().Id;
        try {
            KycReviewController.reject(contactId, '  ');
            Assert.fail('reason required');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('reason'));
        }
        KycReviewController.reject(contactId, 'Photo is blurred, please upload a clearer one');
        Assert.areEqual('Rejected', ritvik().KYC_Status__c);
        KYC_Log__c log = [SELECT Status__c, Reason__c FROM KYC_Log__c WHERE Contact__c = :contactId ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
        Assert.areEqual('Rejected', log.Status__c);
        Assert.isTrue(log.Reason__c.contains('blurred'));
        try {
            KycReviewController.approve(contactId, Date.today().addYears(5), null, null);
            Assert.fail('already reviewed');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('already reviewed'), e.getMessage());
        }
    }

    @IsTest
    static void usersWithoutKycEditAccessCannotReview() {
        Profile minimal = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User outsider = new User(
            Alias = 'noaccs',
            Email = 'no.access@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoAccess',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_IN',
            TimeZoneSidKey = 'Asia/Kolkata',
            ProfileId = minimal.Id,
            Username = 'no.access.' + System.currentTimeMillis() + '@example.test'
        );
        insert outsider;
        Id contactId = ritvik().Id;
        System.runAs(outsider) {
            try {
                KycReviewController.approve(contactId, Date.today().addYears(5), null, null);
                Assert.fail('outsider must not approve');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only rental staff'), e.getMessage());
            }
        }
        Assert.areEqual('Pending Review', ritvik().KYC_Status__c);
    }

    @IsTest
    static void describeReasonVariants() {
        Assert.areEqual('Sent for manual review.', KycReviewController.describeReason(null));
        Assert.areEqual(
            'Name on the licence does not match your profile name.',
            KycReviewController.describeReason(new KYC_Log__c(Status__c = 'Pending Review', Reason__c = 'Name on the licence does not match your profile name.'))
        );
    }
}
