/**
 * Data layer for bookings and payments.
 *
 * Runs WITHOUT sharing on purpose (documented exception, plan D-03): customers only receive read access to
 * bookings (sharing set) so they can never change status through the API, and the Agentforce service user owns
 * none of them. Every read method that serves a customer therefore takes the customer's Contact Id and filters
 * on Customer__c – ownership is part of the query. Write methods are only called by services after such a check.
 */
public without sharing class BookingRepository {
    public static final String BOOKING_FIELDS =
        'Id, Name, OwnerId, Customer__c, Customer__r.FirstName, Customer__r.LastName, Customer__r.KYC_Status__c, ' +
        'Customer__r.License_Expiry__c, Vehicle__c, Vehicle__r.Make__c, Vehicle__r.Model__c, ' +
        'Vehicle__r.Registration_Number__c, Vehicle__r.Daily_Rate__c, Vehicle__r.Odometer__c, Vehicle__r.Status__c, ' +
        'Pickup_Branch__c, Pickup_Branch__r.Name, Pickup_Branch__r.Manager__c, Start_DateTime__c, End_DateTime__c, ' +
        'Actual_Return__c, Rental_Days__c, Total_Amount__c, Deposit_Amount__c, Late_Fee__c, Refund_Amount__c, ' +
        'Status__c, Payment_Status__c, Source__c, Hold_Expires_At__c, Is_Overdue__c, Agent_Session_Id__c, ' +
        'Vehicle_Display__c';

    public static Booking__c getOwned(Id contactId, Id bookingId) {
        if (contactId == null || bookingId == null) {
            return null;
        }
        List<Booking__c> rows = Database.queryWithBinds(
            'SELECT ' + BOOKING_FIELDS + ' FROM Booking__c WHERE Id = :bookingId AND Customer__c = :contactId LIMIT 1',
            new Map<String, Object>{ 'bookingId' => bookingId, 'contactId' => contactId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public static Booking__c getOwnedByNumber(Id contactId, String bookingNumber) {
        String num = normaliseBookingNumber(bookingNumber);
        if (contactId == null || num == null) {
            return null;
        }
        List<Booking__c> rows = Database.queryWithBinds(
            'SELECT ' + BOOKING_FIELDS + ' FROM Booking__c WHERE Name = :num AND Customer__c = :contactId LIMIT 1',
            new Map<String, Object>{ 'num' => num, 'contactId' => contactId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public static Booking__c getById(Id bookingId) {
        List<Booking__c> rows = Database.queryWithBinds(
            'SELECT ' + BOOKING_FIELDS + ' FROM Booking__c WHERE Id = :bookingId LIMIT 1',
            new Map<String, Object>{ 'bookingId' => bookingId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public static Map<Id, Booking__c> getByIds(Set<Id> bookingIds) {
        return new Map<Id, Booking__c>(
            (List<Booking__c>) Database.queryWithBinds(
                'SELECT ' + BOOKING_FIELDS + ' FROM Booking__c WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => bookingIds },
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    /** Row-locks the booking so concurrent confirmations / cancellations are serialised. */
    public static Booking__c lockForUpdate(Id bookingId) {
        List<Booking__c> rows = [
            SELECT Id, Status__c, Payment_Status__c, Vehicle__c, Start_DateTime__c, End_DateTime__c, Customer__c
            FROM Booking__c
            WHERE Id = :bookingId
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** 'bk 1042', 'BK1042', '1042' -> 'BK-1042'. */
    public static String normaliseBookingNumber(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String digits = value.toUpperCase().replaceAll('[^0-9]', '');
        return String.isBlank(digits) ? null : 'BK-' + digits.leftPad(4, '0');
    }

    public static Boolean hasOverlap(Id vehicleId, Datetime startDt, Datetime endDt, Id excludeBookingId) {
        Datetime nowDt = System.now();
        return [
                SELECT COUNT()
                FROM Booking__c
                WHERE
                    Vehicle__c = :vehicleId
                    AND Id != :excludeBookingId
                    AND Start_DateTime__c < :endDt
                    AND End_DateTime__c > :startDt
                    AND (Status__c IN ('Confirmed', 'Active')
                    OR (Status__c = 'Pending Payment'
                    AND Hold_Expires_At__c > :nowDt))
                WITH SYSTEM_MODE
            ] > 0;
    }

    public static Contact getCustomer(Id contactId) {
        List<Contact> rows = [
            SELECT Id, FirstName, LastName, Name, KYC_Status__c, License_Expiry__c, License_Number_Masked__c,
                KYC_Verified_At__c, Birthdate
            FROM Contact
            WHERE Id = :contactId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static void insertBookings(List<Booking__c> rows) {
        insert as system rows;
    }

    public static void updateBookings(List<Booking__c> rows) {
        update as system rows;
    }

    public static void updateVehicles(List<Vehicle__c> rows) {
        update as system rows;
    }

    // ---------------------------------------------------------------- payments

    public static final String PAYMENT_FIELDS =
        'Id, Name, Booking__c, Booking__r.Customer__c, Booking__r.Status__c, Amount__c, Currency_Code__c, ' +
        'Stripe_Session_Id__c, Stripe_Payment_Intent_Id__c, Status__c, Paid_At__c, Failure_Reason__c, ' +
        'Refund_Amount__c, Stripe_Refund_Id__c';

    public static Payment__c paymentBySession(String sessionId) {
        List<Payment__c> rows = Database.queryWithBinds(
            'SELECT ' + PAYMENT_FIELDS + ' FROM Payment__c WHERE Stripe_Session_Id__c = :sid LIMIT 1',
            new Map<String, Object>{ 'sid' => sessionId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public static Payment__c paymentById(Id paymentId) {
        List<Payment__c> rows = Database.queryWithBinds(
            'SELECT ' + PAYMENT_FIELDS + ' FROM Payment__c WHERE Id = :pid LIMIT 1',
            new Map<String, Object>{ 'pid' => paymentId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public static Payment__c lockPayment(Id paymentId) {
        List<Payment__c> rows = [SELECT Id, Status__c FROM Payment__c WHERE Id = :paymentId WITH SYSTEM_MODE LIMIT 1 FOR UPDATE];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Latest successful payment for a booking (refund source). */
    public static Payment__c succeededPayment(Id bookingId) {
        List<Payment__c> rows = Database.queryWithBinds(
            'SELECT ' + PAYMENT_FIELDS + ' FROM Payment__c WHERE Booking__c = :bid AND Status__c = \'Succeeded\' ' +
            'ORDER BY Paid_At__c DESC NULLS LAST LIMIT 1',
            new Map<String, Object>{ 'bid' => bookingId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public static List<Payment__c> initiatedPayments(Set<Id> bookingIds) {
        return [SELECT Id, Status__c, Failure_Reason__c FROM Payment__c WHERE Booking__c IN :bookingIds AND Status__c = 'Initiated' WITH SYSTEM_MODE];
    }

    /** Upsert on the unique external id Stripe_Session_Id__c keeps session creation idempotent. */
    public static void upsertPayment(Payment__c p) {
        upsert as system p Stripe_Session_Id__c;
    }

    public static void updatePayments(List<Payment__c> rows) {
        update as system rows;
    }

    /** Follow-up task for staff when something needs a human (paid-but-unconfirmable, refund failure). */
    public static void createStaffTask(Booking__c b, String subject, String description) {
        Id ownerId = b.Pickup_Branch__r?.Manager__c ?? staffQueueId();
        if (ownerId == null) {
            ownerId = UserInfo.getUserId();
        }
        insert as system new Task(
            Subject = subject.left(255),
            Description = DataMasking.maskLicenseNumbersIn(description),
            WhatId = b.Id,
            OwnerId = ownerId,
            Priority = 'High',
            Status = 'Not Started',
            ActivityDate = Date.today()
        );
    }

    /** Branch-agent task queue (also used by flow KYC_Pending_Task). */
    public static Id staffQueueId() {
        List<Group> queues = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'KYC_Review_Queue' WITH SYSTEM_MODE LIMIT 1];
        return queues.isEmpty() ? null : queues[0].Id;
    }
}