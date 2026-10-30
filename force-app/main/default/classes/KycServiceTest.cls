/**
 * KYC pipeline – TDD 13.2 TC-09 to TC-13 plus name mismatch, bad format, provider swap and upload rules.
 */
@IsTest
private class KycServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Contact c = TestDataFactory.createContact('Rahul', 'Sharma', 'Not Submitted');
        TestDataFactory.createLicenseFile(c.Id);
    }

    private static Contact contact() {
        return [SELECT Id FROM Contact LIMIT 1];
    }

    private static Id fileId() {
        return [SELECT Id FROM ContentVersion LIMIT 1].Id;
    }

    private static String validText() {
        return TestDataFactory.licenceText('Rahul Sharma', 'RJ14 2015 0012345', '15-05-1990', '14-05-2040');
    }

    private static RentalDtos.KycResultDTO run(HttpCalloutMock mock) {
        TestDataFactory.useTestConfig();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        RentalDtos.KycResultDTO r = KycService.verifyLicense(contact().Id, fileId(), null);
        Test.stopTest();
        return r;
    }

    @IsTest
    static void validLicenceIsVerified() {
        RentalDtos.KycResultDTO r = run(OcrHttpMock.generic(validText(), 0.95));
        Assert.areEqual('Verified', r.status, 'TC-09: ' + r.reason);
        Assert.areEqual('XXXX2345', r.maskedLicenseNumber, 'only masked number returned');
        Contact c = [SELECT KYC_Status__c, Driving_License_Number__c, License_Expiry__c, Birthdate, KYC_Verified_At__c, KYC_Confidence__c, License_File_Id__c FROM Contact];
        Assert.areEqual('Verified', c.KYC_Status__c);
        Assert.areEqual('RJ1420150012345', c.Driving_License_Number__c);
        Assert.areEqual(Date.newInstance(2040, 5, 14), c.License_Expiry__c);
        Assert.areEqual(Date.newInstance(1990, 5, 15), c.Birthdate);
        Assert.isNotNull(c.KYC_Verified_At__c);
        Assert.areEqual(95, c.KYC_Confidence__c);
        Assert.isNotNull(c.License_File_Id__c);
        KYC_Log__c log = [SELECT Status__c, Raw_Response__c FROM KYC_Log__c];
        Assert.areEqual('Verified', log.Status__c);
        Assert.isFalse(log.Raw_Response__c.contains('0012345'), 'licence number masked in the log (TDD 11.3)');
    }

    @IsTest
    static void expiredLicenceRejected() {
        RentalDtos.KycResultDTO r = run(OcrHttpMock.generic(TestDataFactory.licenceText('Rahul Sharma', 'RJ1420150012345', '15-05-1990', '01-01-2020'), 0.95));
        Assert.areEqual('Rejected', r.status, 'TC-10');
        Assert.isTrue(r.reason.contains('expire'));
    }

    @IsTest
    static void licenceExpiringBeforeTripEndRejected() {
        TestDataFactory.useTestConfig();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        Vehicle__c v = TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        Date expiry = Date.today().addDays(10);
        Booking__c b = TestDataFactory.createBooking(contact().Id, v.Id, TestDataFactory.future(8, 4), TestDataFactory.future(12, 4), 'Pending Payment');
        String t = TestDataFactory.licenceText('Rahul Sharma', 'RJ1420150012345', '15-05-1990',
            String.valueOf(expiry.day()).leftPad(2, '0') + '-' + String.valueOf(expiry.month()).leftPad(2, '0') + '-' + expiry.year());
        Test.setMock(HttpCalloutMock.class, OcrHttpMock.generic(t, 0.95));
        Test.startTest();
        RentalDtos.KycResultDTO r = KycService.verifyLicense(contact().Id, fileId(), b.Id);
        Test.stopTest();
        Assert.areEqual('Rejected', r.status, 'R3 uses the trip end date');
    }

    @IsTest
    static void blurryImageRejectedAsUnreadable() {
        RentalDtos.KycResultDTO r = run(OcrHttpMock.generic('### ~~ blurry', 0.2));
        Assert.areEqual('Rejected', r.status, 'TC-11: R1 missing fields');
        Assert.isTrue(r.reason.contains('clearer photo'));
        Assert.areNotEqual('Verified', [SELECT KYC_Status__c FROM Contact].KYC_Status__c);
    }

    @IsTest
    static void lowConfidenceGoesToReview() {
        RentalDtos.KycResultDTO r = run(OcrHttpMock.generic(validText(), 0.55));
        Assert.areEqual('Pending Review', r.status, 'R6');
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Review licence for%'], 'flow KYC_Pending_Task creates the review task');
    }

    @IsTest
    static void underAgeRejected() {
        Date dob = Date.today().addYears(-19);
        String d = String.valueOf(dob.day()).leftPad(2, '0') + '-' + String.valueOf(dob.month()).leftPad(2, '0') + '-' + dob.year();
        RentalDtos.KycResultDTO r = run(OcrHttpMock.generic(TestDataFactory.licenceText('Rahul Sharma', 'RJ1420150012345', d, '14-05-2040'), 0.95));
        Assert.areEqual('Rejected', r.status, 'TC-12');
        Assert.isTrue(r.reason.contains('21'));
    }

    @IsTest
    static void nameMismatchGoesToReview() {
        RentalDtos.KycResultDTO r = run(OcrHttpMock.generic(TestDataFactory.licenceText('Priya Verma', 'RJ1420150012345', '15-05-1990', '14-05-2040'), 0.95));
        Assert.areEqual('Pending Review', r.status, 'R5');
    }

    @IsTest
    static void ocrOutageKeepsStatusAndLogsError() {
        RentalDtos.KycResultDTO r = run(new OcrHttpMock(503, 'Service Unavailable'));
        Assert.areEqual('Error', r.status, 'TC-13');
        Assert.areEqual(OcrHttp.MSG_BUSY, r.reason);
        Assert.areEqual('Not Submitted', [SELECT KYC_Status__c FROM Contact].KYC_Status__c, 'status unchanged');
        Assert.areEqual('Error', [SELECT Status__c FROM KYC_Log__c].Status__c);
    }

    @IsTest
    static void ocrTimeoutAndClientError() {
        RentalDtos.KycResultDTO timeout = run(OcrHttpMock.timeoutMock());
        Assert.areEqual(OcrHttp.MSG_BUSY, timeout.reason);
        Assert.areEqual(1, [SELECT COUNT() FROM KYC_Log__c WHERE Status__c = 'Error'], 'one error log');
    }

    @IsTest
    static void ocrBadRequestMeansUnreadable() {
        RentalDtos.KycResultDTO r = run(new OcrHttpMock(400, '{"error":"bad image"}'));
        Assert.areEqual(OcrHttp.MSG_UNREADABLE, r.reason);
    }

    @IsTest
    static void ocrSpaceProvider() {
        TestDataFactory.useTestConfig(new Map<String, Object>{ 'OCR_Provider_Class__c' => 'OcrSpaceClient' });
        Test.setMock(HttpCalloutMock.class, OcrHttpMock.ocrSpace(validText()));
        Test.startTest();
        RentalDtos.KycResultDTO r = KycService.verifyLicense(contact().Id, fileId(), null);
        Test.stopTest();
        Assert.areEqual('Verified', r.status, 'provider swapped by configuration only (D6): ' + r.reason);
        Assert.isNull(r.confidence, 'OCR.space has no confidence -> R6 skipped');
    }

    @IsTest
    static void ocrSpaceProcessingError() {
        TestDataFactory.useTestConfig(new Map<String, Object>{ 'OCR_Provider_Class__c' => 'OcrSpaceClient' });
        Test.setMock(HttpCalloutMock.class, new OcrHttpMock(200, '{"IsErroredOnProcessing":true,"ErrorMessage":["bad"]}'));
        Test.startTest();
        RentalDtos.KycResultDTO r = KycService.verifyLicense(contact().Id, fileId(), null);
        Test.stopTest();
        Assert.areEqual('Error', r.status);
    }

    @IsTest
    static void misconfiguredProviderIsReportedSafely() {
        TestDataFactory.useTestConfig(new Map<String, Object>{ 'OCR_Provider_Class__c' => 'NoSuchClass' });
        RentalDtos.KycResultDTO r = KycService.verifyLicense(contact().Id, fileId(), null);
        Assert.areEqual('Error', r.status);
        Assert.isTrue(r.reason.contains('not configured'));
    }

    @IsTest
    static void foreignOrMissingFileRefused() {
        TestDataFactory.useTestConfig();
        Contact other = TestDataFactory.createContact('Priya', 'Verma', 'Not Submitted');
        Id fakeVersion = Id.valueOf(String.valueOf(ContentVersion.SObjectType.getDescribe().getKeyPrefix()) + '000000000000AAA');
        try {
            KycService.verifyLicense(other.Id, fakeVersion, null);
            Assert.fail('a missing file is refused');
        } catch (KycException e) {
            Assert.isTrue(e.getMessage().contains('could not find'));
        }
        try {
            KycService.verifyLicense(null, fileId(), null);
            Assert.fail('no contact');
        } catch (KycException e) {
            Assert.isTrue(e.getMessage().contains('customer account'));
        }
    }

    @IsTest
    static void uploadValidation() {
        TestDataFactory.useTestConfig();
        Id contactId = contact().Id;
        Id cvId = KycService.saveLicenseImage(contactId, 'photo.PNG', EncodingUtil.base64Encode(Blob.valueOf('img')));
        Assert.areEqual(contactId, [SELECT FirstPublishLocationId FROM ContentVersion WHERE Id = :cvId].FirstPublishLocationId);
        for (String name : new List<String>{ 'licence.pdf', 'noextension' }) {
            try {
                KycService.saveLicenseImage(contactId, name, 'aGVsbG8=');
                Assert.fail(name);
            } catch (KycException e) {
                Assert.isTrue(e.getMessage().contains('JPG or PNG'));
            }
        }
        try {
            KycService.saveLicenseImage(contactId, 'a.jpg', '');
            Assert.fail();
        } catch (KycException e) {
            Assert.isTrue(e.getMessage().contains('empty'));
        }
        TestDataFactory.useTestConfig(new Map<String, Object>{ 'Max_Image_MB__c' => 0.000001 });
        try {
            KycService.saveLicenseImage(contactId, 'a.jpg', 'aGVsbG8gd29ybGQ=');
            Assert.fail();
        } catch (KycException e) {
            Assert.isTrue(e.getMessage().contains('smaller than'));
        }
    }

    @IsTest
    static void ageCalculationAndProfile() {
        Assert.areEqual(20, KycService.ageOn(Date.newInstance(2000, 6, 1), Date.newInstance(2020, 6, 1)));
        Assert.areEqual(19, KycService.ageOn(Date.newInstance(2000, 6, 2), Date.newInstance(2020, 6, 1)));
        RentalDtos.CustomerProfileDTO p = KycService.profile(contact().Id);
        Assert.areEqual('Not Submitted', p.kycStatus);
        Assert.isNull(KycService.profile(null).contactId);
    }
<<<<<<< HEAD
=======
    @IsTest
static void providerFailureReturnsErrorAndKeepsKycStatus() {
    TestDataFactory.useTestConfig();

    Contact c = contact();
    c.KYC_Status__c = 'Pending Review';
    update c;

    Id cvId = KycService.saveLicenseImage(
        c.Id,
        'licence.jpg',
        EncodingUtil.base64Encode(Blob.valueOf('test-image'))
    );

    KycService.providerOverride = new OcrProvider() {
        public OcrResult extract(Blob image, String mimeType) {
            throw new KycException('OCR service temporarily unavailable.');
        }
    };

    try {
        Test.startTest();

        RentalDtos.KycResultDTO result =
            KycService.verifyLicense(c.Id, cvId, null);

        Test.stopTest();

        System.assertEquals('Error', result.status);
        System.assert(
            result.reason.contains('OCR service temporarily unavailable.')
        );

        Contact updated = [
            SELECT KYC_Status__c
            FROM Contact
            WHERE Id = :c.Id
        ];

        System.assertEquals('Pending Review', updated.KYC_Status__c);

        KYC_Log__c log = [
            SELECT Status__c, Reason__c
            FROM KYC_Log__c
            WHERE Contact__c = :c.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals('Error', log.Status__c);
        System.assert(
            log.Reason__c.contains('OCR service temporarily unavailable.')
        );
    } finally {
        KycService.providerOverride = null;
    }
}
>>>>>>> origin/main
}