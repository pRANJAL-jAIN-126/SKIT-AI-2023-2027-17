/**
 * PortalController / InspectionController – portal happy path, guest lock-down and error translation
 * (TDD 4.2, 11.2, TC-25).
 */
@IsTest
private class PortalControllerTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        TestDataFactory.createVerifiedContact();
        TestDataFactory.createContact('Priya', 'Verma', 'Not Submitted');
    }

    private static Contact rahul() {
        return [SELECT Id FROM Contact WHERE FirstName = 'Rahul'];
    }

    private static Vehicle__c car() {
        return [SELECT Id FROM Vehicle__c LIMIT 1];
    }

    private static void loginAs(Id contactId) {
        CustomerContext.testIsGuest = false;
        CustomerContext.testContactId = contactId;
    }

    private static void asGuest() {
        CustomerContext.testIsGuest = true;
        CustomerContext.testContactId = null;
    }

    @IsTest
    static void guestCanBrowseButNotBook() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            asGuest();
            VehicleSearchService.SearchRequest r = new VehicleSearchService.SearchRequest();
            r.startDt = TestDataFactory.future(2, 4);
            r.endDt = TestDataFactory.future(4, 4);
            r.city = 'Jaipur';
            Assert.areEqual(1, PortalController.searchVehicles(r).size());
            Assert.areEqual(2, PortalController.getVehicleDetail(car().Id, r.startDt, r.endDt).days);
            Assert.isTrue(PortalController.getCustomerProfile().isGuest);
            try {
                PortalController.createHold(car().Id, r.startDt, r.endDt);
                Assert.fail('TDD 11.2: guest cannot book');
            } catch (AuraHandledException e) {
                Assert.areEqual('Please log in to continue.', e.getMessage());
            }
            for (Integer i = 0; i < 4; i++) {
                try {
                    if (i == 0) {
                        PortalController.getMyBookings();
                    } else if (i == 1) {
                        PortalController.verifyLicense(null, true, null);
                    } else if (i == 2) {
                        PortalController.confirmPayment('cs_test_x1234');
                    } else {
                        PortalController.cancelBooking(null);
                    }
                    Assert.fail('guest call ' + i + ' must fail');
                } catch (AuraHandledException e) {
                    Assert.areEqual('Please log in to continue.', e.getMessage());
                }
            }
        }
    }

    @IsTest
    static void customerHoldsAndSeesOwnBookings() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            loginAs(rahul().Id);
            RentalDtos.CustomerProfileDTO profile = PortalController.getCustomerProfile();
            Assert.areEqual('Verified', profile.kycStatus);
            Assert.areEqual('XXXX2345', profile.maskedLicenseNumber, 'NFR-03: only the masked licence reaches the UI');

            RentalDtos.BookingDTO b = PortalController.createHold(car().Id, TestDataFactory.future(3, 4), TestDataFactory.future(5, 4));
            Assert.areEqual('Pending Payment', b.status);
            Assert.isTrue(b.canPay);
            Assert.isTrue(b.canCancel);
            Assert.areEqual(1, PortalController.getMyBookings().size());

            RentalDtos.CancelResultDTO quote = PortalController.getCancellationQuote(b.id);
            Assert.areEqual(0, quote.refundAmount);
            RentalDtos.CancelResultDTO done = PortalController.cancelBooking(b.id);
            Assert.areEqual('Cancelled', done.booking.status);
        }
    }

    @IsTest
    static void customerCannotTouchAnotherCustomersBooking() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c rahulsBooking = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(3, 4), TestDataFactory.future(5, 4), 'Pending Payment');
            loginAs([SELECT Id FROM Contact WHERE FirstName = 'Priya'].Id);
            Assert.areEqual(0, PortalController.getMyBookings().size(), 'TC-25');
            for (Integer i = 0; i < 3; i++) {
                try {
                    if (i == 0) {
                        PortalController.cancelBooking(rahulsBooking.Id);
                    } else if (i == 1) {
                        PortalController.getCancellationQuote(rahulsBooking.Id);
                    } else {
                        PortalController.startCheckout(rahulsBooking.Id);
                    }
                    Assert.fail();
                } catch (AuraHandledException e) {
                    Assert.areEqual('Booking not found.', e.getMessage());
                }
            }
        }
    }

    @IsTest
    static void checkoutAndConfirmThroughController() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(3, 4), TestDataFactory.future(5, 4), 'Pending Payment');
        loginAs(rahul().Id);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));
        Test.startTest();
        StripeService.CheckoutResult r = PortalController.startCheckout(b.Id); // Apex call 2 of the booking flow
        Test.stopTest();
        Assert.isTrue(r.url.startsWith('https://checkout.stripe.com/'));
        Assert.areEqual('Initiated', [SELECT Status__c FROM Payment__c].Status__c);
    }

    @IsTest
    static void paymentResultPageConfirmsThroughController() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, TestDataFactory.future(3, 4), TestDataFactory.future(5, 4), 'Pending Payment');
        TestDataFactory.createPayment(b.Id, 'cs_test_mock123', 'Initiated', 1000, null);
        loginAs(rahul().Id);
        Test.setMock(HttpCalloutMock.class, StripeHttpMock.paid(b.Id));
        Test.startTest();
        RentalDtos.PaymentResultDTO paid = PortalController.confirmPayment('cs_test_mock123'); // separate request (redirect)
        Test.stopTest();
        Assert.areEqual('Succeeded', paid.status);
        Assert.areEqual('Confirmed', paid.booking.status);
    }

    @IsTest
    static void kycThroughController() {
        TestDataFactory.useTestConfig();
        Contact priya = [SELECT Id FROM Contact WHERE FirstName = 'Priya'];
        loginAs(priya.Id);
        Id cvId = PortalController.uploadLicenseImage('licence.jpg', EncodingUtil.base64Encode(Blob.valueOf('img')));
        try {
            PortalController.verifyLicense(cvId, false, null);
            Assert.fail('consent required');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('agree'));
        }
        Test.setMock(HttpCalloutMock.class, OcrHttpMock.generic(
            TestDataFactory.licenceText('Priya Verma', 'RJ1420150012345', '15-05-1990', '14-05-2040'), 0.95));
        Test.startTest();
        RentalDtos.KycResultDTO r = PortalController.verifyLicense(cvId, true, null);
        Test.stopTest();
        Assert.areEqual('Verified', r.status, r.reason);
        try {
            PortalController.uploadLicenseImage('x.exe', 'aGk=');
            Assert.fail();
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('JPG'));
        }
    }

    @IsTest
    static void friendlyErrorsAndUnexpectedExceptions() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            loginAs(rahul().Id);
            try {
                PortalController.getVehicleDetail(rahul().Id, null, null);
                Assert.fail();
            } catch (AuraHandledException e) {
                Assert.areEqual('This vehicle is not available.', e.getMessage());
            }
            Assert.isNull(PortalController.getVehicleDetail(car().Id, null, null).days, 'no quote without dates');
            try {
                PortalController.searchVehicles(null);
                Assert.fail();
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('valid pickup'));
            }
            Assert.areEqual(RentalErrors.GENERIC, RentalErrors.friendlyMessage(new NullPointerException()), 'no stack traces');
            DmlException dml;
            try {
                insert new Vehicle__c();
            } catch (DmlException e) {
                dml = e;
            }
            Assert.isNotNull(RentalErrors.friendlyMessage(dml));
            CustomerContext.testContactId = null;
            CustomerContext.testIsGuest = false;
            Assert.isNull(PortalController.getCustomerProfile().contactId, 'internal user without contact');
            try {
                PortalController.getMyBookings();
                Assert.fail();
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('customer account'));
            }
        }
    }

    @IsTest
    static void inspectionControllerWrapsService() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = TestDataFactory.createBooking(rahul().Id, car().Id, System.now().addHours(1), System.now().addDays(2), 'Confirmed');
            RentalDtos.InspectionContextDTO ctx = InspectionController.getInspectionContext(b.Id);
            Assert.areEqual('Pickup', ctx.nextType);
            Id insId = InspectionController.saveInspection(
                new Inspection__c(Booking__c = b.Id, Odometer__c = 10001, Fuel_Level__c = 'Full'), new List<Id>());
            Assert.isNotNull(insId);
            try {
                InspectionController.getInspectionContext(null);
                Assert.fail();
            } catch (AuraHandledException e) {
                Assert.areEqual('Booking not found.', e.getMessage());
            }
            try {
                InspectionController.saveInspection(null, null);
                Assert.fail();
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }
}