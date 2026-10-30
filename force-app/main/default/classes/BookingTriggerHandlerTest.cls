/**
 * BookingTrigger: defaults, state machine, confirmation gate, bulk (200 records) – TDD 6.4, 8.4, 13.1.
 */
@IsTest
private class BookingTriggerHandlerTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        TestDataFactory.createVerifiedContact();
    }

    private static Id vehicleId;
    private static Id contactId;

    private static Booking__c build(Integer dayOffset, String status) {
        if (vehicleId == null) {
            vehicleId = [SELECT Id FROM Vehicle__c LIMIT 1].Id;
            contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        }
        Datetime s = TestDataFactory.future(dayOffset, 4);
        return TestDataFactory.buildBooking(contactId, vehicleId, s, s.addHours(20), status);
    }

    @IsTest
    static void newBookingMustStartPendingAndGetsDefaults() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c ok = build(2, 'Pending Payment');
            ok.Status__c = null;
            ok.Payment_Status__c = null;
            insert ok;
            Booking__c saved = [SELECT Status__c, Payment_Status__c, Pickup_Branch__c FROM Booking__c WHERE Id = :ok.Id];
            Assert.areEqual('Pending Payment', saved.Status__c);
            Assert.areEqual('Unpaid', saved.Payment_Status__c);
            Assert.isNotNull(saved.Pickup_Branch__c, 'pickup branch defaults from the vehicle');

            Database.SaveResult sr = Database.insert(build(5, 'Confirmed'), false);
            Assert.isFalse(sr.isSuccess(), 'a booking cannot be created as Confirmed');
        }
    }

    @IsTest
    static void confirmedOnlyThroughPaymentGate() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = build(2, 'Pending Payment');
            insert b;
            b.Status__c = 'Confirmed';
            b.Payment_Status__c = 'Paid';
            Database.SaveResult sr = Database.update(b, false);
            Assert.isFalse(sr.isSuccess(), 'TDD 8.4: nothing but StripeService may confirm');
            Assert.isTrue(sr.getErrors()[0].getMessage().contains('verified payment'));

            BookingTriggerHandler.confirmationGateOpen = true;
            b.Payment_Status__c = 'Unpaid';
            sr = Database.update(b, false);
            Assert.isFalse(sr.isSuccess(), 'gate still requires Paid');
            b.Payment_Status__c = 'Paid';
            sr = Database.update(b, false);
            BookingTriggerHandler.confirmationGateOpen = false;
            Assert.isTrue(sr.isSuccess(), String.valueOf(sr.getErrors()));
        }
    }

    @IsTest
    static void invalidTransitionsRejected() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = build(2, 'Pending Payment');
            insert b;
            b.Status__c = 'Active';
            Assert.isFalse(Database.update(b, false).isSuccess(), 'Pending Payment -> Active is not allowed');
            b.Status__c = 'Cancelled';
            Assert.isTrue(Database.update(b, false).isSuccess());
            b.Status__c = 'Pending Payment';
            Assert.isFalse(Database.update(b, false).isSuccess(), 'Cancelled is terminal');
        }
    }

    @IsTest
    static void completingClearsOverdueFlag() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(
            [SELECT Id FROM Contact LIMIT 1].Id, [SELECT Id FROM Vehicle__c LIMIT 1].Id,
            System.now().addDays(-3), System.now().addHours(-3), 'Active');
        b.Is_Overdue__c = true;
        TestDataFactory.updateBypassingGuards(new List<SObject>{ b });
        b.Status__c = 'Completed';
        update b;
        Assert.isFalse([SELECT Is_Overdue__c FROM Booking__c WHERE Id = :b.Id].Is_Overdue__c);
    }

    @IsTest
    static void bulkInsertOf200NonOverlappingHolds() {
        TestDataFactory.useTestConfig();
        List<Booking__c> rows = new List<Booking__c>();
        for (Integer i = 0; i < 200; i++) {
            rows.add(build(2 + i, 'Pending Payment'));
        }
        Test.startTest();
        insert rows;
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Booking__c]);
    }

    @IsTest
    static void apiCannotTamperWithPriceOrHold() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = build(4, 'Pending Payment');
            b.Total_Amount__c = 1;
            b.Deposit_Amount__c = 0;
            b.Rental_Days__c = 1;
            b.Payment_Status__c = 'Paid';
            b.Hold_Expires_At__c = System.now().addYears(1);
            insert b;
            Booking__c saved = [SELECT Total_Amount__c, Deposit_Amount__c, Payment_Status__c, Hold_Expires_At__c FROM Booking__c WHERE Id = :b.Id];
            Assert.areEqual(4130, saved.Total_Amount__c, 'price recomputed from the vehicle: 3500 x 1 day + 18%');
            Assert.areEqual(5000, saved.Deposit_Amount__c);
            Assert.areEqual('Unpaid', saved.Payment_Status__c);
            Assert.isTrue(saved.Hold_Expires_At__c <= System.now().addMinutes(15), 'hold cannot be extended');

            saved.Total_Amount__c = 10;
            update saved;
            Assert.areEqual(4130, [SELECT Total_Amount__c FROM Booking__c WHERE Id = :b.Id].Total_Amount__c, 'updates are repriced too');
        }
    }

    @IsTest
    static void overlapInsideSameBatchRejected() {
        TestDataFactory.useTestConfig();
        List<Booking__c> rows = new List<Booking__c>{ build(3, 'Pending Payment'), build(3, 'Pending Payment') };
        List<Database.SaveResult> results = Database.insert(rows, false);
        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess(), 'second booking for the same car and time in one batch is rejected');
    }
}