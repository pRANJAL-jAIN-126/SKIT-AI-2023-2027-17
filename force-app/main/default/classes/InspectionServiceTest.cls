/**
 * Inspections + GenAI damage report – TDD 13.2 TC-19 to TC-21, missing inspection data, late return.
 */
@IsTest
private class InspectionServiceTest {
    /** Stub so tests never depend on the live LLM. */
    private class StubGenerator implements DamageReportGenerator {
        String text;
        StubGenerator(String text) {
            this.text = text;
        }
        public String generate(Vehicle__c v, Inspection__c p, Inspection__c r) {
            if (text == null) {
                throw new InspectionException('LLM unavailable');
            }
            return text;
        }
    }

    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        Vehicle__c v = TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 4000);
        Contact c = TestDataFactory.createVerifiedContact();
        TestDataFactory.createBooking(c.Id, v.Id, System.now().addHours(1), System.now().addDays(2), 'Confirmed');
    }

    private static Booking__c booking() {
        return [SELECT Id, Status__c, Vehicle__c FROM Booking__c LIMIT 1];
    }

    private static Inspection__c pickup(Booking__c b) {
        return new Inspection__c(Booking__c = b.Id, Type__c = 'Pickup', Odometer__c = 10000, Fuel_Level__c = 'Full',
            Exterior_Condition__c = 'Good', Interior_Condition__c = 'Good');
    }

    /** Puts the booking into Active with a pickup inspection (as flow Inspection_Pickup would). */
    private static Booking__c activate() {
        Booking__c b = booking();
        InspectionService.saveInspection(pickup(b), new List<Id>());
        b = booking();
        if (b.Status__c != 'Active') {
            b.Status__c = 'Active';
            update b;
        }
        return b;
    }

    @IsTest
    static void contextTellsWhichInspectionIsNext() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            RentalDtos.InspectionContextDTO ctx = InspectionService.getContext(booking().Id);
            Assert.areEqual('Pickup', ctx.nextType);
            Assert.areEqual(10000, ctx.currentOdometer);
            try {
                InspectionService.getContext(null);
                Assert.fail();
            } catch (InspectionException e) {
                Assert.areEqual('Booking not found.', e.getMessage());
            }
        }
    }

    @IsTest
    static void pickupActivatesBookingAndRentsVehicle() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = booking();
            ContentVersion photo = TestDataFactory.createLicenseFile(b.Id);
            Test.startTest();
            Id insId = InspectionService.saveInspection(pickup(b), new List<Id>{ photo.ContentDocumentId });
            Test.stopTest();
            Inspection__c ins = [SELECT Vehicle__c, Inspector__c, Branch_Manager__c FROM Inspection__c WHERE Id = :insId];
            Assert.areEqual(b.Vehicle__c, ins.Vehicle__c);
            Assert.areEqual(UserInfo.getUserId(), ins.Inspector__c);
            Assert.areEqual([SELECT Manager__c FROM Branch__c LIMIT 1].Manager__c, ins.Branch_Manager__c, 'copied from the branch for approval routing');
            Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :insId], 'photo linked');
            Assert.areEqual('Active', booking().Status__c, 'TC-19: flow Inspection_Pickup activates the booking');
            Assert.areEqual('Rented', [SELECT Status__c FROM Vehicle__c].Status__c, 'flow Booking_Status_VehicleSync');
            Assert.areEqual('Return', InspectionService.getContext(b.Id).nextType);
        }
    }

    @IsTest
    static void orderingAndOdometerRules() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = booking();
            Inspection__c early = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10500);
            Assert.isFalse(Database.insert(early, false).isSuccess(), 'return before pickup is refused');

            b = activate();
            Inspection__c lowerOdo = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 9000);
            Database.SaveResult sr = Database.insert(lowerOdo, false);
            Assert.isFalse(sr.isSuccess(), 'TDD 6.8: return odometer lower than pickup');
            Assert.isTrue(sr.getErrors()[0].getMessage().contains('pickup odometer'));

            Assert.isFalse(Database.insert(pickup(b), false).isSuccess(), 'duplicate pickup refused');

            try {
                InspectionService.saveInspection(new Inspection__c(Booking__c = b.Id, Type__c = 'Pickup', Odometer__c = 1), null);
                Assert.fail();
            } catch (InspectionException e) {
                Assert.isTrue(e.getMessage().contains('Return inspection next'));
            }
            try {
                InspectionService.saveInspection(new Inspection__c(Booking__c = b.Id), null);
                Assert.fail();
            } catch (InspectionException e) {
                Assert.isTrue(e.getMessage().contains('odometer'));
            }
            try {
                InspectionService.saveInspection(null, null);
                Assert.fail();
            } catch (InspectionException e) {
                Assert.isTrue(e.getMessage().contains('booking'));
            }
            Inspection__c saved = [SELECT Id, Type__c FROM Inspection__c LIMIT 1];
            saved.Type__c = 'Return';
            Assert.isFalse(Database.update(saved, false).isSuccess(), 'type cannot change');
        }
    }

    @IsTest
    static void returnCompletesBookingWithLateFee() {
        Booking__c late = booking();
        late.End_DateTime__c = System.now().addHours(-3).addMinutes(-10);
        late.Start_DateTime__c = System.now().addDays(-2);
        TestDataFactory.updateBypassingGuards(new List<SObject>{ late }); // trip already ran late
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10420, Fuel_Level__c = '3/4',
                Exterior_Condition__c = 'Good', Interior_Condition__c = 'Good');
            Test.startTest();
            insert ret;
            InspectionService.processReturn(new List<Id>{ ret.Id }); // idempotent if the flow already did it
            Test.stopTest();
            Booking__c done = [SELECT Status__c, Actual_Return__c, Late_Fee__c FROM Booking__c WHERE Id = :b.Id];
            Assert.areEqual('Completed', done.Status__c, 'TC-19');
            Assert.isNotNull(done.Actual_Return__c);
            Assert.areEqual(1600, done.Late_Fee__c, 'FR-13: 4 started hours x 10% x 4000');
            Assert.areEqual(10420, [SELECT Odometer__c FROM Vehicle__c].Odometer__c);
            Assert.areEqual('Available', [SELECT Status__c FROM Vehicle__c].Status__c, 'vehicle released');
        }
    }

    @IsTest
    static void aiReportMinorDamage() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10300, Fuel_Level__c = 'Full',
                Exterior_Condition__c = 'Minor Damage', Interior_Condition__c = 'Good', Damage_Notes__c = 'scratch on rear bumper', Estimated_Charge__c = 1500);
            insert ret;
            InspectionService.generatorOverride = new StubGenerator(
                '1) Distance driven: 300 km\n2) Fuel difference: none\n3) New damage found:\n- scratch on rear bumper\n4) Severity: Minor\n5) Recommended action: Apply the charge.'
            );
            Test.startTest();
            Inspection__c out = InspectionService.generateDamageReport(ret.Id);
            Test.stopTest();
            Assert.areEqual('Minor', out.Damage_Severity__c, 'TC-20');
            Assert.isTrue(out.Damage_Detected__c);
            Assert.areEqual('Approved', out.Charge_Status__c, 'below threshold -> no approval needed');
            Inspection__c saved = [SELECT AI_Summary__c FROM Inspection__c WHERE Id = :ret.Id];
            for (String section : new List<String>{ '1)', '2)', '3)', '4)', '5)' }) {
                Assert.isTrue(saved.AI_Summary__c.contains(section), 'five required sections');
            }
        }
    }

    @IsTest
    static void majorDamageGoesToApproval() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10300, Fuel_Level__c = 'Full',
                Exterior_Condition__c = 'Major Damage', Interior_Condition__c = 'Good', Damage_Notes__c = 'dent on driver door', Estimated_Charge__c = 12000);
            insert ret;
            InspectionService.generatorOverride = new StubGenerator(null); // LLM down -> rule-based fallback
            Test.startTest();
            Inspection__c out = InspectionService.generateDamageReport(ret.Id);
            Test.stopTest();
            Assert.areEqual('Major', out.Damage_Severity__c);
            Assert.isTrue([SELECT AI_Summary__c FROM Inspection__c WHERE Id = :ret.Id].AI_Summary__c.startsWith(RuleBasedDamageReportGenerator.LABEL));
            Assert.areEqual(1, [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :ret.Id AND Status = 'Pending'], 'TC-21: manager approval requested');
            Assert.areEqual('Pending Approval', [SELECT Charge_Status__c FROM Inspection__c WHERE Id = :ret.Id].Charge_Status__c);
        }
    }

    @IsTest
    static void noBranchManagerCreatesTaskInstead() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10300,
                Exterior_Condition__c = 'Major Damage', Estimated_Charge__c = 9000);
            insert ret;
            ret.Branch_Manager__c = null;
            update ret;
            InspectionService.generatorOverride = new StubGenerator('4) Severity: Major');
            InspectionService.generateDamageReport(ret.Id);
            Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :b.Id AND Subject LIKE 'Damage charge%']);
        }
    }

    @IsTest
    static void cleanReturnHasNoDamage() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10100, Fuel_Level__c = '1/2',
                Exterior_Condition__c = 'Good', Interior_Condition__c = 'Good');
            insert ret;
            InspectionService.generatorOverride = new StubGenerator(null);
            Inspection__c out = InspectionService.generateDamageReport(ret.Id);
            Assert.areEqual('None', out.Damage_Severity__c);
            Assert.isFalse(out.Damage_Detected__c);
            Assert.areEqual('Not Applicable', out.Charge_Status__c);
            Assert.isTrue([SELECT AI_Summary__c FROM Inspection__c WHERE Id = :ret.Id].AI_Summary__c.contains('refuel'));
        }
    }

    @IsTest
    static void missingPickupIsReportedNotInvented() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10200);
            insert ret;
            Inspection__c p = [SELECT Id FROM Inspection__c WHERE Booking__c = :b.Id AND Type__c = 'Pickup'];
            delete p; // pickup data lost
            Inspection__c out = InspectionService.generateDamageReport(ret.Id);
            Assert.isTrue(out.AI_Summary__c.contains('pickup inspection is missing'), 'no damage is invented');
            try {
                InspectionService.generateDamageReport(p.Id);
                Assert.fail();
            } catch (InspectionException e) {
                Assert.areEqual('Return inspection not found.', e.getMessage());
            }
        }
    }

    @IsTest
    static void severityParsingAndFlowActions() {
        System.runAs(TestDataFactory.staffUser()) {
            Assert.areEqual('Major', InspectionService.parseSeverity('4) Severity: MAJOR'));
            Assert.areEqual('None', InspectionService.parseSeverity('Severity - none'));
            Assert.isNull(InspectionService.parseSeverity('no info'));
            Assert.isNull(InspectionService.parseSeverity(null));

            TestDataFactory.useTestConfig();
            Booking__c b = activate();
            Inspection__c ret = new Inspection__c(Booking__c = b.Id, Type__c = 'Return', Odometer__c = 10100);
            insert ret;
            InspectionService.generatorOverride = new StubGenerator('4) Severity: None');
            InspectionReturnAction.Request r1 = new InspectionReturnAction.Request();
            r1.inspectionId = ret.Id;
            InspectionReturnAction.run(new List<InspectionReturnAction.Request>{ r1 });
            DamageReportAction.Request r2 = new DamageReportAction.Request();
            r2.inspectionId = ret.Id;
            DamageReportAction.Request bad = new DamageReportAction.Request();
            DamageReportAction.run(new List<DamageReportAction.Request>{ r2, bad });
            Assert.areEqual('None', [SELECT Damage_Severity__c FROM Inspection__c WHERE Id = :ret.Id].Damage_Severity__c);
        }
    }
}