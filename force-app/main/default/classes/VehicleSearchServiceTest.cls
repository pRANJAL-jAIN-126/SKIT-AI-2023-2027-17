/**
 * Availability search – TDD 13.2 TC-01 to TC-04, TC-06, TC-08 (search side), TC-22 (overdue car hidden).
 */
@IsTest
private class VehicleSearchServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c jaipur = TestDataFactory.createBranch('Jaipur');
        Branch__c delhi = TestDataFactory.createBranch('Delhi Central', 'Delhi');
        TestDataFactory.createVehicle(jaipur.Id, 'RJ14CD5678', 3500);
        Vehicle__c cheap = TestDataFactory.buildVehicle(jaipur.Id, 'RJ14NP7531', 1500);
        cheap.Make__c = 'Maruti';
        cheap.Model__c = 'Swift';
        cheap.Category__c = 'Hatchback';
        cheap.Seats__c = 5;
        cheap.Transmission__c = 'Manual';
        insert cheap;
        TestDataFactory.createVehicle(delhi.Id, 'DL01QR4455', 3400);
        TestDataFactory.createVerifiedContact();
    }

    private static Vehicle__c vehicle(String reg) {
        return [SELECT Id FROM Vehicle__c WHERE Registration_Number__c = :reg];
    }

    private static VehicleSearchService.SearchRequest req(Datetime s, Datetime e, String city) {
        VehicleSearchService.SearchRequest r = new VehicleSearchService.SearchRequest();
        r.startDt = s;
        r.endDt = e;
        r.city = city;
        return r;
    }

    @IsTest
    static void overlappingBookingHidesVehicle() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Vehicle__c v = vehicle('RJ14CD5678');
            Contact c = [SELECT Id FROM Contact LIMIT 1];
            Datetime s = TestDataFactory.future(2, 4), e = s.addDays(3);
            TestDataFactory.createBooking(c.Id, v.Id, s, e, 'Confirmed');

            Test.startTest();
            List<Vehicle__c> result = VehicleSearchService.searchAvailable(req(s.addDays(1), s.addDays(2), 'Jaipur'));
            Test.stopTest();

            for (Vehicle__c r : result) {
                Assert.areNotEqual(v.Id, r.Id, 'Booked vehicle must not be returned (TC-01)');
            }
            Assert.areEqual(1, result.size(), 'Only the free Jaipur car is returned; Delhi is filtered by city');
        }
    }

    @IsTest
    static void maintenanceVehicleExcluded() {
        Vehicle__c v = vehicle('RJ14CD5678');
        v.Status__c = 'Maintenance';
        update v; // fleet admin change (vehicles are Public Read Only)
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            List<Vehicle__c> result = VehicleSearchService.searchAvailable(req(TestDataFactory.future(2, 4), TestDataFactory.future(4, 4), 'Jaipur'));
            Assert.areEqual(1, result.size(), 'TC-02: vehicle in maintenance is not listed');
            Assert.areNotEqual(v.Id, result[0].Id);
        }
    }

    @IsTest
    static void backToBackBookingIsAllowed() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = vehicle('RJ14CD5678');
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        Datetime s = TestDataFactory.future(2, 4), e = s.addDays(2);
        TestDataFactory.createBooking(c.Id, v.Id, s, e, 'Confirmed');
        Set<Id> busy = VehicleSearchService.busyVehicleIds(e, e.addDays(1));
        Assert.isFalse(busy.contains(v.Id), 'TC-03: overlap is strict, a search starting at the previous end is free');
    }

    @IsTest
    static void invalidDatesGiveFriendlyError() {
        TestDataFactory.useTestConfig();
        Datetime s = TestDataFactory.future(3, 4);
        try {
            VehicleSearchService.searchAvailable(req(s, s.addHours(-2), 'Jaipur'));
            Assert.fail('TC-04: end before start must fail');
        } catch (BookingException e) {
            Assert.areEqual('Return time must be after the pickup time.', e.getMessage());
        }
        try {
            VehicleSearchService.searchAvailable(null);
            Assert.fail('null request must fail');
        } catch (BookingException e) {
            Assert.isTrue(e.getMessage().contains('valid pickup'));
        }
    }

    @IsTest
    static void activeHoldBlocksOthersButExpiredHoldDoesNot() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = vehicle('RJ14CD5678');
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        Datetime s = TestDataFactory.future(5, 4), e = s.addDays(2);
        Booking__c hold = TestDataFactory.createBooking(c.Id, v.Id, s, e, 'Pending Payment');
        Assert.isTrue(VehicleSearchService.busyVehicleIds(s, e).contains(v.Id), 'TC-06: live hold blocks the car');

        hold.Hold_Expires_At__c = System.now().addMinutes(-1);
        TestDataFactory.updateBypassingGuards(new List<SObject>{ hold });
        Assert.isFalse(VehicleSearchService.busyVehicleIds(s, e).contains(v.Id), 'TC-08: an expired hold no longer blocks');
    }

    @IsTest
    static void overdueActiveBookingBlocksAnyRange() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = vehicle('RJ14CD5678');
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        Booking__c b = TestDataFactory.createBooking(c.Id, v.Id, System.now().addDays(-3), System.now().addHours(-2), 'Active');
        b.Is_Overdue__c = true;
        TestDataFactory.updateBypassingGuards(new List<SObject>{ b });
        Datetime s = TestDataFactory.future(10, 4);
        Assert.isTrue(VehicleSearchService.busyVehicleIds(s, s.addDays(1)).contains(v.Id), 'TC-22: overdue car is not offered');
    }

    @IsTest
    static void filtersAndQuotesApplied() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            VehicleSearchService.SearchRequest r = req(TestDataFactory.future(2, 4), TestDataFactory.future(5, 4), 'Jaipur');
            r.category = 'MUV';
            r.minSeats = 7;
            r.transmission = 'Automatic';
            r.fuelType = 'Petrol';
            r.maxDailyRate = 4500;
            List<RentalDtos.VehicleDTO> result = VehicleSearchService.searchWithQuotes(r);
            Assert.areEqual(1, result.size());
            Assert.areEqual(3, result[0].days);
            Assert.areEqual(10500, result[0].subtotal);
            Assert.areEqual(1890, result[0].tax, '18% GST');
            Assert.areEqual(12390 + 5000, result[0].grandTotal);

            r.maxDailyRate = 1000;
            Assert.areEqual(0, VehicleSearchService.searchWithQuotes(r).size());
        }
    }

    @IsTest
    static void scopedBusyCheck() {
        TestDataFactory.useTestConfig();
        Vehicle__c v = vehicle('RJ14CD5678');
        Vehicle__c other = vehicle('RJ14NP7531');
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        Datetime s = TestDataFactory.future(2, 4), e = s.addDays(1);
        TestDataFactory.createBooking(c.Id, v.Id, s, e, 'Confirmed');
        TestDataFactory.createBooking(c.Id, other.Id, s, e, 'Confirmed');
        Set<Id> busy = VehicleSearchService.busyVehicleIds(s, e, new Set<Id>{ v.Id });
        Assert.areEqual(new Set<Id>{ v.Id }, busy);
    }
}