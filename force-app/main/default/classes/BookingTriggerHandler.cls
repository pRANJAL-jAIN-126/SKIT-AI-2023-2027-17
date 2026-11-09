/**
 * Logic for BookingTrigger (TDD 12: one trigger per object, logic in the handler).
 *  - defaults (Pickup_Branch__c from vehicle, Status/Payment Status)
 *  - booking status state machine (TDD 6.4) – also protects against API / Data Loader writes
 *  - confirmation gate: only StripeService (via BookingService.confirmAfterPayment) can set Confirmed, and
 *    only when Payment_Status__c = Paid and the customer's KYC is Verified (FR-07, TDD 8.4)
 *  - bulk overlap re-check: defence in depth against double booking (NFR-02)
 *  - portal users can only create bookings for their own Contact
 * Vehicle status synchronisation is done declaratively by flow Booking_Status_VehicleSync.
 */
public with sharing class BookingTriggerHandler {
    /** Seed scripts / tests only: skip state-machine guards. Users with Rental_Data_Admin bypass as well. */
    public static Boolean bypassGuards = false;
    /** Opened by BookingService.confirmAfterPayment for the duration of the confirming update. */
    public static Boolean confirmationGateOpen = false;

    @TestVisible
    private static final Map<String, Set<String>> ALLOWED = new Map<String, Set<String>>{
        BookingService.ST_PENDING => new Set<String>{ BookingService.ST_CONFIRMED, BookingService.ST_EXPIRED, BookingService.ST_CANCELLED },
        BookingService.ST_EXPIRED => new Set<String>{ BookingService.ST_CONFIRMED },
        BookingService.ST_CONFIRMED => new Set<String>{ BookingService.ST_ACTIVE, BookingService.ST_CANCELLED },
        BookingService.ST_ACTIVE => new Set<String>{ BookingService.ST_COMPLETED },
        BookingService.ST_COMPLETED => new Set<String>(),
        BookingService.ST_CANCELLED => new Set<String>()
    };

    public static void beforeInsert(List<Booking__c> news) {
        Boolean bypass = canBypass();
        applyDefaults(news);
        Id portalContactId = bypass ? null : CustomerContext.runningUserContactId();
        for (Booking__c b : news) {
            if (!bypass && b.Status__c != BookingService.ST_PENDING) {
                b.Status__c.addError('New bookings must start as Pending Payment.');
            }
            if (portalContactId != null && b.Customer__c != portalContactId) {
                b.Customer__c.addError('You can only create bookings for yourself.');
            }
        }
        if (!bypass) {
            enforceConfirmationRules(news);
        }
        checkOverlaps(news);
    }

    public static void beforeUpdate(List<Booking__c> news, Map<Id, Booking__c> oldMap) {
        Boolean bypass = canBypass();
        List<Booking__c> toCheck = new List<Booking__c>();
        List<Booking__c> confirming = new List<Booking__c>();
        List<Booking__c> repriced = new List<Booking__c>();
        Set<Id> repricedVehicles = new Set<Id>();
        for (Booking__c b : news) {
            Booking__c old = oldMap.get(b.Id);
            if (!bypass && (b.Vehicle__c != old.Vehicle__c || b.Start_DateTime__c != old.Start_DateTime__c ||
                b.End_DateTime__c != old.End_DateTime__c || b.Total_Amount__c != old.Total_Amount__c ||
                b.Deposit_Amount__c != old.Deposit_Amount__c)) {
                repriced.add(b);
                repricedVehicles.add(b.Vehicle__c);
            }
        }
        if (!repriced.isEmpty()) {
            applyPricing(repriced, vehicles(repricedVehicles));
        }
        for (Booking__c b : news) {
            Booking__c old = oldMap.get(b.Id);
            Boolean statusChanged = b.Status__c != old.Status__c;
            if (statusChanged && !bypass) {
                Set<String> allowed = ALLOWED.get(old.Status__c);
                if (allowed == null || !allowed.contains(b.Status__c)) {
                    b.Status__c.addError('A booking cannot move from ' + old.Status__c + ' to ' + b.Status__c + '.');
                    continue;
                }
                if (b.Status__c == BookingService.ST_CONFIRMED) {
                    confirming.add(b);
                }
            }
            if (b.Status__c == BookingService.ST_COMPLETED) {
                b.Is_Overdue__c = false; // returned – no longer overdue (late fee already recorded)
            }
            Boolean rangeChanged = b.Vehicle__c != old.Vehicle__c || b.Start_DateTime__c != old.Start_DateTime__c ||
                b.End_DateTime__c != old.End_DateTime__c;
            Boolean becameBlocking = statusChanged && isBlocking(b) && !isBlocking(old);
            if ((rangeChanged || becameBlocking) && isBlocking(b)) {
                toCheck.add(b);
            }
        }
        if (!confirming.isEmpty()) {
            enforceConfirmationRules(confirming);
        }
        if (!toCheck.isEmpty()) {
            checkOverlaps(toCheck);
        }
    }

    private static Boolean canBypass() {
        return bypassGuards || FeatureManagement.checkPermission('Rental_Data_Admin');
    }

    private static void applyDefaults(List<Booking__c> news) {
        Set<Id> vehicleIds = new Set<Id>();
        for (Booking__c b : news) {
            if (b.Status__c == null) {
                b.Status__c = BookingService.ST_PENDING;
            }
            if (b.Payment_Status__c == null) {
                b.Payment_Status__c = BookingService.PAY_UNPAID;
            }
            if (b.Vehicle__c != null) {
                vehicleIds.add(b.Vehicle__c);
            }
        }
        Map<Id, Vehicle__c> vehicles = vehicles(vehicleIds);
        for (Booking__c b : news) {
            if (b.Pickup_Branch__c == null && vehicles.containsKey(b.Vehicle__c)) {
                b.Pickup_Branch__c = vehicles.get(b.Vehicle__c).Branch__c;
            }
        }
        if (!canBypass()) {
            for (Booking__c b : news) {
                // server-owned fields: never trust values sent through the API
                b.Payment_Status__c = BookingService.PAY_UNPAID;
                b.Late_Fee__c = null;
                b.Refund_Amount__c = null;
                b.Hold_Expires_At__c = System.now().addMinutes(RentalConfig.get().Hold_Minutes__c.intValue());
            }
            applyPricing(news, vehicles);
        }
    }

    /**
     * Price, rental days and deposit are always recomputed from the vehicle (Appendix C) for non-admin writes, so
     * a booking created or re-dated through the API can never be paid at a tampered amount.
     */
    private static void applyPricing(List<Booking__c> rows, Map<Id, Vehicle__c> vehicles) {
        for (Booking__c b : rows) {
            Vehicle__c v = vehicles.get(b.Vehicle__c);
            if (v == null || b.Start_DateTime__c == null || b.End_DateTime__c == null || b.End_DateTime__c <= b.Start_DateTime__c) {
                continue; // validation rules / required fields report the problem
            }
            PricingService.Quote q = PricingService.calculate(v, b.Start_DateTime__c, b.End_DateTime__c);
            b.Rental_Days__c = q.days;
            b.Total_Amount__c = q.total;
            b.Deposit_Amount__c = q.deposit;
        }
    }

    private static Map<Id, Vehicle__c> vehicles(Set<Id> vehicleIds) {
        if (vehicleIds.isEmpty()) {
            return new Map<Id, Vehicle__c>();
        }
        return new Map<Id, Vehicle__c>(
            [SELECT Id, Branch__c, Daily_Rate__c, Security_Deposit__c FROM Vehicle__c WHERE Id IN :vehicleIds WITH SYSTEM_MODE]
        );
    }

    /** Confirmed only through the Stripe gate, with Paid status and a Verified customer (FR-07). */
    private static void enforceConfirmationRules(List<Booking__c> rows) {
        List<Booking__c> confirming = new List<Booking__c>();
        Set<Id> contactIds = new Set<Id>();
        for (Booking__c b : rows) {
            if (b.Status__c == BookingService.ST_CONFIRMED) {
                if (!confirmationGateOpen) {
                    b.Status__c.addError('A booking can only be confirmed by a verified payment.');
                    continue;
                }
                if (b.Payment_Status__c != BookingService.PAY_PAID) {
                    b.Status__c.addError('A booking can only be confirmed after successful payment.');
                    continue;
                }
                confirming.add(b);
                contactIds.add(b.Customer__c);
            }
        }
        if (confirming.isEmpty()) {
            return;
        }
        Map<Id, String> kyc = new Selector().kycStatuses(contactIds);
        for (Booking__c b : confirming) {
            if (kyc.get(b.Customer__c) != 'Verified') {
                b.Status__c.addError('A booking can only be confirmed when the customer\'s licence is verified.');
            }
        }
    }

    private static Boolean isBlocking(Booking__c b) {
        return b.Status__c == BookingService.ST_CONFIRMED || b.Status__c == BookingService.ST_ACTIVE ||
            (b.Status__c == BookingService.ST_PENDING && b.Hold_Expires_At__c != null && b.Hold_Expires_At__c > System.now());
    }

    /** Rejects any booking that would overlap a blocking booking of the same vehicle (in the DB or in this batch). */
    private static void checkOverlaps(List<Booking__c> rows) {
        List<Booking__c> candidates = new List<Booking__c>();
        Set<Id> vehicleIds = new Set<Id>();
        Set<Id> selfIds = new Set<Id>();
        Datetime minStart, maxEnd;
        for (Booking__c b : rows) {
            if (!isBlocking(b) || b.Vehicle__c == null || b.Start_DateTime__c == null || b.End_DateTime__c == null) {
                continue;
            }
            candidates.add(b);
            vehicleIds.add(b.Vehicle__c);
            if (b.Id != null) {
                selfIds.add(b.Id);
            }
            minStart = (minStart == null || b.Start_DateTime__c < minStart) ? b.Start_DateTime__c : minStart;
            maxEnd = (maxEnd == null || b.End_DateTime__c > maxEnd) ? b.End_DateTime__c : maxEnd;
        }
        if (candidates.isEmpty()) {
            return;
        }
        Map<Id, List<Booking__c>> existingByVehicle = new Map<Id, List<Booking__c>>();
        for (Booking__c e : new Selector().blockingBookings(vehicleIds, minStart, maxEnd, selfIds)) {
            if (!existingByVehicle.containsKey(e.Vehicle__c)) {
                existingByVehicle.put(e.Vehicle__c, new List<Booking__c>());
            }
            existingByVehicle.get(e.Vehicle__c).add(e);
        }
        Map<Id, List<Booking__c>> batchByVehicle = new Map<Id, List<Booking__c>>();
        for (Booking__c b : candidates) {
            Boolean clash = false;
            for (Booking__c e : existingByVehicle.get(b.Vehicle__c) ?? new List<Booking__c>()) {
                if (overlaps(b, e)) {
                    clash = true;
                    break;
                }
            }
            for (Booking__c other : batchByVehicle.get(b.Vehicle__c) ?? new List<Booking__c>()) {
                if (overlaps(b, other)) {
                    clash = true;
                    break;
                }
            }
            if (clash) {
                b.addError('Sorry, this vehicle was just booked for those dates.');
            } else {
                if (!batchByVehicle.containsKey(b.Vehicle__c)) {
                    batchByVehicle.put(b.Vehicle__c, new List<Booking__c>());
                }
                batchByVehicle.get(b.Vehicle__c).add(b);
            }
        }
    }

    private static Boolean overlaps(Booking__c a, Booking__c b) {
        return a.Start_DateTime__c < b.End_DateTime__c && a.End_DateTime__c > b.Start_DateTime__c;
    }

    /**
     * WITHOUT sharing on purpose (plan D-02/D-03): overlap and KYC checks must see all bookings / contacts, not
     * only those shared with the user who triggered the save. Returns data used only for validation.
     */
    private without sharing class Selector {
        List<Booking__c> blockingBookings(Set<Id> vehicleIds, Datetime minStart, Datetime maxEnd, Set<Id> selfIds) {
            Datetime nowDt = System.now();
            return [
                SELECT Id, Vehicle__c, Start_DateTime__c, End_DateTime__c
                FROM Booking__c
                WHERE
                    Vehicle__c IN :vehicleIds
                    AND Id NOT IN :selfIds
                    AND Start_DateTime__c < :maxEnd
                    AND End_DateTime__c > :minStart
                    AND (Status__c IN ('Confirmed', 'Active')
                    OR (Status__c = 'Pending Payment'
                    AND Hold_Expires_At__c > :nowDt))
                WITH SYSTEM_MODE
            ];
        }

        Map<Id, String> kycStatuses(Set<Id> contactIds) {
            Map<Id, String> result = new Map<Id, String>();
            for (Contact c : [SELECT Id, KYC_Status__c FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE]) {
                result.put(c.Id, c.KYC_Status__c);
            }
            return result;
        }
    }
}