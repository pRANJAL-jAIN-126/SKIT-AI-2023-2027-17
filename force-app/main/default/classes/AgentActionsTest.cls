/**
 * Agentforce actions – TDD 8.3 / 8.4 guardrails, TC-23 (happy path) and TC-24 (security).
 */
@IsTest
private class AgentActionsTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantStaffAccess();
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        Vehicle__c innova = TestDataFactory.buildVehicle(br.Id, 'RJ14GH2468', 4200);
        innova.Make__c = 'Toyota';
        innova.Model__c = 'Innova Crysta';
        innova.Fuel_Type__c = 'Diesel';
        insert innova;
        TestDataFactory.createVehicle(br.Id, 'RJ14JK1357', 3800); // Kia Carens
        TestDataFactory.createVerifiedContact();
        TestDataFactory.createContact('Priya', 'Verma', 'Not Submitted');
    }

    private static Contact rahul() {
        return [SELECT Id FROM Contact WHERE FirstName = 'Rahul'];
    }

    private static Contact priya() {
        return [SELECT Id FROM Contact WHERE FirstName = 'Priya'];
    }

    @IsTest
    static void happyPathSearchThenHold() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            AgentSearchVehicles.Req s = new AgentSearchVehicles.Req();
            s.pickupDateTime = TestDataFactory.future(4, 4);
            s.returnDateTime = TestDataFactory.future(7, 4);
            s.city = 'Jaipur';
            s.minSeats = 7;
            s.transmission = 'Automatic';
            s.maxDailyRate = 4500;
            AgentSearchVehicles.Res found = AgentSearchVehicles.run(new List<AgentSearchVehicles.Req>{ s })[0];
            Assert.areEqual(2, found.vehicleIds.size(), 'TC-23: real vehicles from Vehicle__c');
            Assert.isTrue(found.summary.contains('Kia Carens') && found.summary.contains('INR 3,800/day') && found.summary.contains('INR 11,400 for 3 days'));

            AgentCreateBooking.Req c = new AgentCreateBooking.Req();
            c.customerContactId = rahul().Id;
            c.vehicleId = found.vehicleIds[0];
            c.pickupDateTime = s.pickupDateTime;
            c.returnDateTime = s.returnDateTime;
            c.sessionId = '0Mw000000000001';
            AgentCreateBooking.Res held = AgentCreateBooking.run(new List<AgentCreateBooking.Req>{ c })[0];
            Assert.isTrue(held.success, held.message);
            Assert.isTrue(held.message.contains('Held as BK-'));
            Assert.isTrue(held.paymentUrl.startsWith(TestDataFactory.SITE + '/my-bookings?pay='));
            Booking__c b = [SELECT Status__c, Source__c, Agent_Session_Id__c FROM Booking__c];
            Assert.areEqual('Pending Payment', b.Status__c, 'agent never confirms');
            Assert.areEqual('Agentforce', b.Source__c);
            Assert.areEqual('0Mw000000000001', b.Agent_Session_Id__c, 'session logged for audit');

            AgentGetPaymentLink.Res link = AgentGetPaymentLink.run(new List<AgentGetPaymentLink.Req>{ paymentReq(rahul().Id, held.bookingNumber) })[0];
            Assert.isTrue(link.url.contains('/my-bookings?pay='));
        }
    }

    private static AgentGetPaymentLink.Req paymentReq(Id contactId, String num) {
        AgentGetPaymentLink.Req r = new AgentGetPaymentLink.Req();
        r.customerContactId = contactId;
        r.bookingNumber = num;
        return r;
    }

    @IsTest
    static void unverifiedCustomerGetsVerificationLinkFirst() {
        TestDataFactory.useTestConfig();
        AgentCreateBooking.Req c = new AgentCreateBooking.Req();
        c.customerContactId = priya().Id;
        c.vehicleId = [SELECT Id FROM Vehicle__c LIMIT 1].Id;
        c.pickupDateTime = TestDataFactory.future(4, 4);
        c.returnDateTime = TestDataFactory.future(5, 4);
        AgentCreateBooking.Res held = AgentCreateBooking.create(c);
        Assert.isTrue(held.message.contains('not verified yet'));
        Assert.isTrue(held.message.contains(held.verifyUrl));
        AgentGetPaymentLink.Res link = AgentGetPaymentLink.link(priya().Id, held.bookingNumber);
        Assert.isTrue(link.url.contains('/verify'), 'KYC link first');
    }

    @IsTest
    static void cannotReadOrCancelAnotherCustomersBooking() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, [SELECT Id FROM Vehicle__c LIMIT 1].Id, TestDataFactory.future(4, 4), TestDataFactory.future(5, 4), 'Confirmed');
        String num = [SELECT Name FROM Booking__c WHERE Id = :b.Id].Name;

        AgentGetBooking.Req g = new AgentGetBooking.Req();
        g.customerContactId = priya().Id;
        g.bookingNumber = num;
        AgentGetBooking.Res res = AgentGetBooking.run(new List<AgentGetBooking.Req>{ g })[0];
        Assert.isFalse(res.found, 'TC-24');
        Assert.isTrue(res.message.contains('could not find'));

        AgentCancelBooking.Res c = AgentCancelBooking.cancel(priya().Id, num, true);
        Assert.isFalse(c.cancelled);
        Assert.areEqual('Confirmed', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);

        // a portal user's own contact always wins over a supplied id
        CustomerContext.testContactId = priya().Id;
        AgentGetBooking.Res spoof = AgentGetBooking.lookup(rahul().Id, num);
        Assert.isFalse(spoof.found);
        Assert.isTrue(spoof.message.contains('only access your own'));
        CustomerContext.testContactId = null;

        AgentGetBooking.Res noIdentity = AgentGetBooking.lookup('not-an-id', num);
        Assert.isTrue(noIdentity.message.contains('could not identify'));
    }

    @IsTest
    static void cancelRequiresExplicitConfirmation() {
        TestDataFactory.useTestConfig();
        Booking__c b = TestDataFactory.createBooking(rahul().Id, [SELECT Id FROM Vehicle__c LIMIT 1].Id, TestDataFactory.future(4, 4), TestDataFactory.future(5, 4), 'Pending Payment');
        String num = [SELECT Name FROM Booking__c WHERE Id = :b.Id].Name;
        AgentCancelBooking.Req r = new AgentCancelBooking.Req();
        r.customerContactId = rahul().Id;
        r.bookingNumber = num;
        r.confirmed = false;
        AgentCancelBooking.Res notYet = AgentCancelBooking.run(new List<AgentCancelBooking.Req>{ r })[0];
        Assert.isFalse(notYet.cancelled, 'TDD 8.4: refuses unless confirmed = true');
        Assert.areEqual('Pending Payment', [SELECT Status__c FROM Booking__c].Status__c);

        r.confirmed = true;
        AgentCancelBooking.Res done = AgentCancelBooking.run(new List<AgentCancelBooking.Req>{ r })[0];
        Assert.isTrue(done.cancelled, done.message);
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Booking__c].Status__c);
    }

    @IsTest
    static void getBookingAndPaymentLinkStates() {
        TestDataFactory.useTestConfig();
        Id v = [SELECT Id FROM Vehicle__c LIMIT 1].Id;
        Booking__c paid = TestDataFactory.createBooking(rahul().Id, v, TestDataFactory.future(4, 4), TestDataFactory.future(5, 4), 'Confirmed');
        Booking__c expired = TestDataFactory.createBooking(rahul().Id, v, TestDataFactory.future(8, 4), TestDataFactory.future(9, 4), 'Expired');
        Map<Id, String> nums = new Map<Id, String>();
        for (Booking__c b : [SELECT Id, Name FROM Booking__c]) {
            nums.put(b.Id, b.Name);
        }
        AgentGetBooking.Res info = AgentGetBooking.lookup(rahul().Id, nums.get(paid.Id).toLowerCase().replace('-', ' '));
        Assert.isTrue(info.found, 'booking number normalised');
        Assert.areEqual('Confirmed', info.status);
        Assert.isTrue(AgentGetPaymentLink.link(rahul().Id, nums.get(paid.Id)).message.contains('already paid'));
        Assert.isTrue(AgentGetPaymentLink.link(rahul().Id, nums.get(expired.Id)).message.contains('can no longer be paid'));
        Assert.isTrue(AgentGetPaymentLink.link(rahul().Id, 'BK-9999').message.contains('could not find'));
        Assert.isTrue(AgentCancelBooking.cancel(rahul().Id, 'BK-9999', true).message.contains('could not find'));
    }

    @IsTest
    static void invalidInputsGivePlainTextErrors() {
        System.runAs(TestDataFactory.staffUser()) {
            TestDataFactory.useTestConfig();
            AgentSearchVehicles.Req s = new AgentSearchVehicles.Req();
            s.pickupDateTime = TestDataFactory.future(4, 4);
            s.returnDateTime = TestDataFactory.future(3, 4);
            s.city = 'Jaipur';
            Assert.isTrue(AgentSearchVehicles.search(s).summary.startsWith('Search not possible'));
            s.returnDateTime = TestDataFactory.future(5, 4);
            s.city = 'Mumbai';
            Assert.isTrue(AgentSearchVehicles.search(s).summary.startsWith('No vehicles are free'));

            AgentCreateBooking.Req c = new AgentCreateBooking.Req();
            c.customerContactId = rahul().Id;
            c.vehicleId = 'Kia Carens';
            c.pickupDateTime = TestDataFactory.future(4, 4);
            c.returnDateTime = TestDataFactory.future(5, 4);
            AgentCreateBooking.Res r = AgentCreateBooking.create(c);
            Assert.isFalse(r.success);
            Assert.isTrue(r.message.contains('search for vehicles first'), 'no vehicle invented from free text');
            c.vehicleId = [SELECT Id FROM Vehicle__c LIMIT 1].Id;
            c.pickupDateTime = System.now().addDays(-1);
            Assert.isTrue(AgentCreateBooking.create(c).message.contains('past'));
            c.pickupDateTime = TestDataFactory.future(4, 4);
            c.returnDateTime = TestDataFactory.future(40, 4);
            Assert.isTrue(AgentCreateBooking.create(c).message.contains('30 days'), 'max rental length');
            Assert.areEqual(0, [SELECT COUNT() FROM Booking__c]);
        }
    }
    @IsTest
static void createBookingHoldSuccessFlow() {
    System.runAs(TestDataFactory.staffUser()) {
        TestDataFactory.useTestConfig();

        AgentCreateBooking.Req r = new AgentCreateBooking.Req();
        r.customerContactId = rahul().Id;
        r.vehicleId = [SELECT Id FROM Vehicle__c LIMIT 1].Id;
        r.pickupDateTime = TestDataFactory.future(10, 4);
        r.returnDateTime = TestDataFactory.future(11, 4);
        r.sessionId = 'agent-session-step-2';

        AgentCreateBooking.Res res = AgentCreateBooking.create(r);

        System.assertEquals(true, res.success);
        System.assertNotEquals(null, res.bookingNumber);
        System.assertNotEquals(null, res.totalAmount);
        System.assertNotEquals(null, res.holdExpiresAt);
        System.assertNotEquals(null, res.paymentUrl);
        System.assertNotEquals(null, res.verifyUrl);
        System.assert(res.message.contains('Held as'));

        Booking__c b = [
            SELECT Status__c, Payment_Status__c, Source__c, Agent_Session_Id__c
            FROM Booking__c
            WHERE Name = :res.bookingNumber
            LIMIT 1
        ];

        System.assertEquals('Pending Payment', b.Status__c);
        System.assertEquals('Unpaid', b.Payment_Status__c);
        System.assertEquals('Agentforce', b.Source__c);
        System.assertEquals('agent-session-step-2', b.Agent_Session_Id__c);
    }
}
}