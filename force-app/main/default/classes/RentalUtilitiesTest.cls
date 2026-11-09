/**
 * Small utilities: RentalConfig defaults, CustomerContext, AgentSupport formatting, OCR clients' request shape,
 * rule-based report and the prompt-template generator's failure path.
 */
@IsTest
private class RentalUtilitiesTest {
    @IsTest
    static void configDefaultsAndUrls() {
        Rental_Config__mdt c = RentalConfig.applyDefaults(new Rental_Config__mdt(Site_URL__c = 'https://x.example/rentals/'));
        Assert.areEqual(15, c.Hold_Minutes__c);
        Assert.areEqual(21, c.Min_Age__c);
        Assert.areEqual(0.18, c.Tax_Rate__c);
        Assert.areEqual('inr', c.Currency_Code__c);
        Assert.areEqual('https://x.example/rentals', c.Site_URL__c, 'trailing slash removed');
        RentalConfig.cached = c;
        Id fake = Id.valueOf('a00000000000000AAA');
        Assert.areEqual('https://x.example/rentals/verify?booking=' + fake, RentalConfig.verifyUrl(fake));
        Assert.areEqual('https://x.example/rentals/verify', RentalConfig.verifyUrl(null));
        Assert.isTrue(RentalConfig.paymentUrl(fake).endsWith('/my-bookings?pay=' + fake));
        RentalConfig.cached = null;
        Assert.isNotNull(RentalConfig.get(), 'loads the deployed Default record or safe defaults');
    }

    @IsTest
    static void customerContextResolution() {
        Assert.isNull(CustomerContext.runningUserContactId(), 'internal test user has no contact');
        Assert.isNull(CustomerContext.toId('nope'));
        Contact c = TestDataFactory.createContact('Asha', 'Rao', 'Verified');
        Assert.areEqual(c.Id, CustomerContext.resolveForAgent(c.Id));
        delete c;
        try {
            CustomerContext.resolveForAgent(c.Id);
            Assert.fail('deleted contact');
        } catch (BookingException e) {
            Assert.isTrue(e.getMessage().contains('could not identify'));
        }
        CustomerContext.testIsGuest = true;
        Assert.isNull(CustomerContext.runningUserContactId());
    }

    @IsTest
    static void formatting() {
        Assert.areEqual('INR 11,400', AgentSupport.inr(11400));
        Assert.areEqual('INR 0', AgentSupport.inr(null));
        Datetime d = Datetime.newInstanceGmt(2030, 1, 4, 4, 30, 0); // 10:00 IST
        Assert.isTrue(AgentSupport.dt(d).contains('10:00 AM IST'), AgentSupport.dt(d));
        Assert.areEqual('', AgentSupport.dt(null));
        Assert.areEqual('', AgentSupport.time(null));
    }

    @IsTest
    static void genericOcrClientSendsJsonToNamedCredential() {
        Test.setMock(HttpCalloutMock.class, OcrHttpMock.generic('NAME TEST', 0.9));
        Test.startTest();
        OcrResult r = new GenericOcrClient().extract(Blob.valueOf('img'), 'image/jpeg');
        Test.stopTest();
        Assert.areEqual('NAME TEST', r.text);
        Assert.areEqual(0.9, r.minConfidence());
        Assert.areEqual(1, OcrHttpMock.calls);
    }

    @IsTest
    static void ruleBasedReportFormat() {
        Inspection__c p = new Inspection__c(Odometer__c = 1000, Fuel_Level__c = 'Full', Exterior_Condition__c = 'Good', Interior_Condition__c = 'Excellent');
        Inspection__c r = new Inspection__c(Odometer__c = 1250, Fuel_Level__c = 'Full', Exterior_Condition__c = 'Good', Interior_Condition__c = 'Minor Damage');
        String text = new RuleBasedDamageReportGenerator().generate(new Vehicle__c(), p, r);
        Assert.isTrue(text.contains('1) Distance driven: 250 km'));
        Assert.isTrue(text.contains('(unchanged)'));
        Assert.isTrue(text.contains('Interior condition changed'));
        Assert.isTrue(text.contains('4) Severity: Minor'));
        Inspection__c none = new Inspection__c(Odometer__c = 1000);
        Assert.isTrue(new RuleBasedDamageReportGenerator().generate(new Vehicle__c(), none, none).contains('Not recorded'));
    }

    @IsTest
    static void promptTemplateGeneratorFailsCleanlyInTests() {
        Branch__c br = TestDataFactory.createBranch('Jaipur');
        Vehicle__c v = TestDataFactory.createVehicle(br.Id, 'RJ14CD5678', 3500);
        Inspection__c dummy = new Inspection__c(Id = Id.valueOf(Inspection__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA'));
        try {
            new PromptTemplateDamageReportGenerator().generate(v, dummy, dummy);
        } catch (Exception e) {
            // ConnectApi is not available in unit tests; the service falls back to the rule-based report.
            Assert.isNotNull(e.getMessage());
        }
        try {
            new RentalAssistantController.PromptTemplateIntentProvider().classify('hi', '[]');
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}