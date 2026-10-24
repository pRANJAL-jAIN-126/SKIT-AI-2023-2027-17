/**
 * Test data for all rental tests (TDD 9.1: createBranch, createVehicle, createContact, createBooking).
 * All data is fictitious.
 */
@IsTest
public class TestDataFactory {
    public static final String SITE = 'https://test.example.com/rentals';

    /** Deterministic configuration independent of the org's Rental_Config__mdt record. */
    public static Rental_Config__mdt useTestConfig() {
        return useTestConfig(new Map<String, Object>());
    }

    /** Custom metadata is read-only in memory, so overrides are applied while the test config is built. */
    public static Rental_Config__mdt useTestConfig(Map<String, Object> overrides) {
        Rental_Config__mdt c = new Rental_Config__mdt(Site_URL__c = SITE, OCR_Provider_Class__c = 'GenericOcrClient');
        RentalConfig.cached = RentalConfig.applyDefaults(c, overrides);
        return RentalConfig.cached;
    }

    public static final String STAFF_ALIAS = 'rstaff';

    /**
     * Apex at API 67.0 runs database operations in user mode by default, so code paths that intentionally use
     * USER_MODE (search, My Bookings, inspections) must run as a user with real permissions. Creates a staff user
     * with Rental_Manager (no Rental_Data_Admin bypass, so the booking state machine stays enforced) and
     * Rental_Integration. Call first in every @TestSetup; use System.runAs(staffUser()) around user-mode code.
     */
    public static void grantStaffAccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            String unique = String.valueOf(Crypto.getRandomInteger()).remove('-');
            User u = new User(
                Alias = STAFF_ALIAS,
                Email = 'rental.staff@example.com',
                EmailEncodingKey = 'UTF-8',
                FirstName = 'Rental',
                LastName = 'Staff',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_IN',
                ProfileId = p.Id,
                TimeZoneSidKey = 'Asia/Kolkata',
                Username = 'rental.staff.' + unique + '@test.example.com'
            );
            insert u;
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('Rental_Manager', 'Rental_Integration')]) {
                psas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert psas;
        }
    }

    public static User staffUser() {
        return [SELECT Id FROM User WHERE Alias = :STAFF_ALIAS AND Email = 'rental.staff@example.com' ORDER BY CreatedDate DESC LIMIT 1];
    }

    public static Branch__c createBranch(String city) {
        return createBranch(city + ' Airport', city);
    }

    public static Branch__c createBranch(String name, String city) {
        Branch__c b = new Branch__c(Name = name, City__c = city, Address__c = '1 Test Road, ' + city, Phone__c = '+911400000000', Manager__c = UserInfo.getUserId());
        insert b;
        return b;
    }

    public static Vehicle__c createVehicle(Id branchId, String registration, Decimal dailyRate) {
        Vehicle__c v = buildVehicle(branchId, registration, dailyRate);
        insert v;
        return v;
    }

    public static Vehicle__c buildVehicle(Id branchId, String registration, Decimal dailyRate) {
        return new Vehicle__c(
            Branch__c = branchId,
            Registration_Number__c = registration,
            Make__c = 'Kia',
            Model__c = 'Carens',
            Year__c = 2024,
            Category__c = 'MUV',
            Transmission__c = 'Automatic',
            Fuel_Type__c = 'Petrol',
            Seats__c = 7,
            Daily_Rate__c = dailyRate,
            Security_Deposit__c = 5000,
            Status__c = 'Available',
            Odometer__c = 10000
        );
    }

    public static Contact createContact(String firstName, String lastName, String kycStatus) {
        Contact c = new Contact(
            FirstName = firstName,
            LastName = lastName,
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + '@example.com',
            KYC_Status__c = kycStatus
        );
        if (kycStatus == 'Verified') {
            c.License_Expiry__c = Date.today().addYears(10);
            c.Birthdate = Date.newInstance(1990, 5, 15);
            c.Driving_License_Number__c = 'RJ1420150012345';
            c.KYC_Verified_At__c = System.now();
        }
        insert c;
        return c;
    }

    public static Contact createVerifiedContact() {
        return createContact('Rahul', 'Sharma', 'Verified');
    }

    /** Inserts a booking in any status, bypassing the state-machine guard (setup only). */
    public static Booking__c createBooking(Id contactId, Id vehicleId, Datetime s, Datetime e, String status) {
        Booking__c b = buildBooking(contactId, vehicleId, s, e, status);
        insertBypassingGuards(new List<Booking__c>{ b });
        return b;
    }

    public static Booking__c buildBooking(Id contactId, Id vehicleId, Datetime s, Datetime e, String status) {
        Integer days = PricingService.rentalDays(s, e);
        return new Booking__c(
            Customer__c = contactId,
            Vehicle__c = vehicleId,
            Start_DateTime__c = s,
            End_DateTime__c = e,
            Rental_Days__c = days,
            Total_Amount__c = 3500 * days * 1.18,
            Deposit_Amount__c = 5000,
            Status__c = status,
            Payment_Status__c = (status == 'Pending Payment' || status == 'Expired') ? 'Unpaid' : 'Paid',
            Source__c = 'Staff',
            Hold_Expires_At__c = status == 'Pending Payment' ? System.now().addMinutes(15) : null
        );
    }

    public static void insertBypassingGuards(List<Booking__c> rows) {
        BookingTriggerHandler.bypassGuards = true;
        try {
            insert rows;
        } finally {
            BookingTriggerHandler.bypassGuards = false;
        }
    }

    public static void updateBypassingGuards(List<SObject> rows) {
        BookingTriggerHandler.bypassGuards = true;
        try {
            update rows;
        } finally {
            BookingTriggerHandler.bypassGuards = false;
        }
    }

    public static Payment__c createPayment(Id bookingId, String sessionId, String status, Decimal amount, String intentId) {
        Payment__c p = new Payment__c(
            Booking__c = bookingId,
            Stripe_Session_Id__c = sessionId,
            Status__c = status,
            Amount__c = amount,
            Currency_Code__c = 'INR',
            Stripe_Payment_Intent_Id__c = intentId,
            Paid_At__c = status == 'Succeeded' ? System.now() : null
        );
        insert p;
        return p;
    }

    /** A future date-time at the given hour (UTC) n days from today. */
    public static Datetime future(Integer days, Integer hour) {
        Date d = Date.today().addDays(days);
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), hour, 0, 0);
    }

    public static ContentVersion createLicenseFile(Id contactId) {
        ContentVersion cv = new ContentVersion(
            Title = 'Driving licence',
            PathOnClient = 'licence.jpg',
            VersionData = Blob.valueOf('fake-image-bytes'),
            FirstPublishLocationId = contactId
        );
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }

    /** Sample OCR text of a fictitious Indian licence. */
    public static String licenceText(String name, String licenceNo, String dob, String validTill) {
        return 'INDIAN UNION DRIVING LICENCE\nRAJASTHAN\nDL No: ' + licenceNo + '\nName: ' + name + '\nS/D/W of: SURESH KUMAR\n' +
            'DOB: ' + dob + '  Date of Issue: 10-01-2015\nValidity (NT): ' + validTill + '\nAddress: 12 Test Nagar, Jaipur';
    }
}