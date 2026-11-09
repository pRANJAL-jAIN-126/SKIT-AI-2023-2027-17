/**
 * Pickup / Return inspections and the Generative AI damage report (TDD 7.6, FR-11, FR-12, FR-13).
 *
 *  saveInspection        – staff entry point (inspectionForm); CRUD/FLS enforced with USER_MODE
 *  validateBeforeInsert  – InspectionTrigger: ordering + odometer rules (TDD 6.8)
 *  processReturn         – flow Inspection_Return_Report (immediate path): Completed, Actual_Return, late fee, odometer
 *  generateDamageReport  – flow Inspection_Return_Report (async path): Prompt Builder report, severity, approval
 * Pickup -> Active is done declaratively by flow Inspection_Pickup.
 */
public with sharing class InspectionService {
    public static final String TYPE_PICKUP = 'Pickup';
    public static final String TYPE_RETURN = 'Return';

    @TestVisible
    private static DamageReportGenerator generatorOverride;

    private static final String INSPECTION_FIELDS =
        'Id, Name, Booking__c, Vehicle__c, Type__c, Odometer__c, Fuel_Level__c, Exterior_Condition__c, ' +
        'Interior_Condition__c, Damage_Notes__c, Damage_Detected__c, Estimated_Charge__c, Inspection_Date__c, ' +
        'Branch_Manager__c, CreatedById, AI_Summary__c, Damage_Severity__c, Charge_Status__c';

    // ------------------------------------------------------------------ staff UI

    public static RentalDtos.InspectionContextDTO getContext(Id bookingId) {
        List<Booking__c> rows = [
            SELECT Id, Name, Status__c, Vehicle__c, Vehicle__r.Make__c, Vehicle__r.Model__c,
                Vehicle__r.Registration_Number__c, Vehicle__r.Odometer__c
            FROM Booking__c
            WHERE Id = :bookingId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new InspectionException('Booking not found.');
        }
        Booking__c b = rows[0];
        List<Inspection__c> pickups = [
            SELECT Odometer__c, Fuel_Level__c
            FROM Inspection__c
            WHERE Booking__c = :bookingId AND Type__c = :TYPE_PICKUP
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        RentalDtos.InspectionContextDTO dto = new RentalDtos.InspectionContextDTO();
        dto.bookingId = b.Id;
        dto.bookingNumber = b.Name;
        dto.bookingStatus = b.Status__c;
        dto.vehicleId = b.Vehicle__c;
        dto.vehicleName = b.Vehicle__r.Make__c + ' ' + b.Vehicle__r.Model__c + ' (' + b.Vehicle__r.Registration_Number__c + ')';
        dto.currentOdometer = b.Vehicle__r.Odometer__c;
        if (!pickups.isEmpty()) {
            dto.pickupOdometer = pickups[0].Odometer__c;
            dto.pickupFuel = pickups[0].Fuel_Level__c;
        }
        if (b.Status__c == BookingService.ST_CONFIRMED) {
            dto.nextType = TYPE_PICKUP;
            dto.message = 'Record the pickup inspection when handing over the car.';
        } else if (b.Status__c == BookingService.ST_ACTIVE) {
            dto.nextType = TYPE_RETURN;
            dto.message = 'Record the return inspection when the car comes back.';
        } else {
            dto.message = 'Inspections can only be recorded for Confirmed (pickup) or Active (return) bookings. Current status: ' + b.Status__c + '.';
        }
        return dto;
    }

    /** Saves an inspection and links uploaded photos (Salesforce Files) to it (TDD 6.6). */
    public static Id saveInspection(Inspection__c inspection, List<Id> contentDocumentIds) {
        if (inspection == null || inspection.Booking__c == null) {
            throw new InspectionException('Please choose the booking to inspect.');
        }
        RentalDtos.InspectionContextDTO ctx = getContext(inspection.Booking__c);
        if (ctx.nextType == null) {
            throw new InspectionException(ctx.message);
        }
        if (String.isBlank(inspection.Type__c)) {
            inspection.Type__c = ctx.nextType;
        } else if (inspection.Type__c != ctx.nextType) {
            throw new InspectionException('This booking needs a ' + ctx.nextType + ' inspection next.');
        }
        if (inspection.Odometer__c == null) {
            throw new InspectionException('Please enter the odometer reading.');
        }
        inspection.Vehicle__c = ctx.vehicleId;
        inspection.Inspector__c = UserInfo.getUserId();
        if (inspection.Inspection_Date__c == null) {
            inspection.Inspection_Date__c = System.now();
        }
        Database.insert(inspection, AccessLevel.USER_MODE);

        if (contentDocumentIds != null && !contentDocumentIds.isEmpty()) {
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id docId : new Set<Id>(contentDocumentIds)) {
                links.add(new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = inspection.Id, ShareType = 'V'));
            }
            Database.insert(links, false); // a photo that is already linked must not fail the inspection
        }
        return inspection.Id;
    }

    // ------------------------------------------------------------------ trigger validation

    /** Pickup needs a Confirmed booking; Return needs an Active booking with a pickup and odometer >= pickup. */
    public static void validateBeforeInsert(List<Inspection__c> news) {
        Set<Id> bookingIds = new Set<Id>();
        for (Inspection__c i : news) {
            if (i.Booking__c != null) {
                bookingIds.add(i.Booking__c);
            }
        }
        if (bookingIds.isEmpty()) {
            return;
        }
        Selector sel = new Selector();
        Map<Id, Booking__c> bookings = sel.bookings(bookingIds);
        Map<Id, Map<String, Inspection__c>> existing = sel.existingInspections(bookingIds);
        Map<String, Inspection__c> inBatch = new Map<String, Inspection__c>();

        for (Inspection__c i : news) {
            Booking__c b = bookings.get(i.Booking__c);
            if (b == null) {
                i.Booking__c.addError('Booking not found.');
                continue;
            }
            i.Vehicle__c = i.Vehicle__c ?? b.Vehicle__c;
            i.Inspector__c = i.Inspector__c ?? UserInfo.getUserId();
            i.Branch_Manager__c = i.Branch_Manager__c ?? b.Pickup_Branch__r?.Manager__c;
            if (i.Inspection_Date__c == null) {
                i.Inspection_Date__c = System.now();
            }
            String key = i.Booking__c + ':' + i.Type__c;
            Map<String, Inspection__c> forBooking = existing.get(i.Booking__c) ?? new Map<String, Inspection__c>();
            if (forBooking.containsKey(i.Type__c) || inBatch.containsKey(key)) {
                i.Type__c.addError('A ' + i.Type__c + ' inspection already exists for this booking.');
                continue;
            }
            if (i.Type__c == TYPE_PICKUP && b.Status__c != BookingService.ST_CONFIRMED) {
                i.Type__c.addError('A pickup inspection needs a Confirmed (paid) booking.');
                continue;
            }
            if (i.Type__c == TYPE_RETURN) {
                Inspection__c pickup = forBooking.get(TYPE_PICKUP);
                if (b.Status__c != BookingService.ST_ACTIVE || pickup == null) {
                    i.Type__c.addError('A return inspection needs an Active booking with a pickup inspection.');
                    continue;
                }
                if (i.Odometer__c != null && pickup.Odometer__c != null && i.Odometer__c < pickup.Odometer__c) {
                    i.Odometer__c.addError('Return odometer cannot be lower than the pickup odometer (' + pickup.Odometer__c + ' km).');
                    continue;
                }
            }
            inBatch.put(key, i);
        }
    }

    public static void validateBeforeUpdate(List<Inspection__c> news, Map<Id, Inspection__c> oldMap) {
        for (Inspection__c i : news) {
            Inspection__c old = oldMap.get(i.Id);
            if (i.Type__c != old.Type__c || i.Booking__c != old.Booking__c) {
                i.addError('The booking and type of an inspection cannot be changed.');
            }
        }
    }

    // ------------------------------------------------------------------ return processing (flow)

    /** Return inspection saved: Booking Completed + Actual_Return__c + late fee; vehicle odometer updated. */
    public static void processReturn(List<Id> returnInspectionIds) {
        List<Inspection__c> returns = [
            SELECT Id, Booking__c, Vehicle__c, Odometer__c, Inspection_Date__c, Type__c
            FROM Inspection__c
            WHERE Id IN :returnInspectionIds AND Type__c = :TYPE_RETURN
            WITH SYSTEM_MODE
        ];
        Set<Id> bookingIds = new Set<Id>();
        for (Inspection__c i : returns) {
            bookingIds.add(i.Booking__c);
        }
        Map<Id, Booking__c> bookings = BookingRepository.getByIds(bookingIds);
        List<Booking__c> bookingUpdates = new List<Booking__c>();
        Map<Id, Vehicle__c> vehicleUpdates = new Map<Id, Vehicle__c>();
        for (Inspection__c i : returns) {
            Booking__c b = bookings.get(i.Booking__c);
            if (b == null || b.Status__c != BookingService.ST_ACTIVE) {
                continue;
            }
            Datetime actual = i.Inspection_Date__c ?? System.now();
            bookingUpdates.add(
                new Booking__c(
                    Id = b.Id,
                    Status__c = BookingService.ST_COMPLETED,
                    Actual_Return__c = actual,
                    Late_Fee__c = PricingService.lateFee(b, actual),
                    Is_Overdue__c = false
                )
            );
            if (i.Odometer__c != null && (b.Vehicle__r.Odometer__c == null || i.Odometer__c > b.Vehicle__r.Odometer__c)) {
                vehicleUpdates.put(b.Vehicle__c, new Vehicle__c(Id = b.Vehicle__c, Odometer__c = i.Odometer__c));
            }
        }
        if (!bookingUpdates.isEmpty()) {
            BookingRepository.updateBookings(bookingUpdates);
        }
        if (!vehicleUpdates.isEmpty()) {
            BookingRepository.updateVehicles(vehicleUpdates.values());
        }
    }

    // ------------------------------------------------------------------ damage report (flow async path)

    /**
     * Compares the pickup and return inspections with Prompt Builder (Damage_Report_Summary), stores the text in
     * AI_Summary__c, sets severity / Damage_Detected__c, and submits Damage_Charge_Approval when the severity is
     * Major or the estimated charge exceeds Damage_Approval_Threshold__c. Falls back to a labelled rule-based
     * report if the generative AI call fails, so the return is never blocked (plan D-09).
     */
    public static Inspection__c generateDamageReport(Id returnInspectionId) {
        Inspection__c ret = loadInspection(returnInspectionId);
        if (ret == null || ret.Type__c != TYPE_RETURN) {
            throw new InspectionException('Return inspection not found.');
        }
        List<Inspection__c> pickups = Database.queryWithBinds(
            'SELECT ' + INSPECTION_FIELDS + ' FROM Inspection__c WHERE Booking__c = :bid AND Type__c = :t LIMIT 1',
            new Map<String, Object>{ 'bid' => ret.Booking__c, 't' => TYPE_PICKUP },
            AccessLevel.SYSTEM_MODE
        );
        Vehicle__c vehicle = [
            SELECT Id, Make__c, Model__c, Registration_Number__c
            FROM Vehicle__c
            WHERE Id = :ret.Vehicle__c
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Inspection__c upd = new Inspection__c(Id = ret.Id);
        if (pickups.isEmpty()) {
            upd.AI_Summary__c = 'Damage report not generated: the pickup inspection is missing, so there is nothing to compare against. Please review the vehicle manually.';
            update as system upd;
            return upd;
        }
        Inspection__c pickup = pickups[0];
        String report;
        try {
            report = generator().generate(vehicle, pickup, ret);
        } catch (Exception e) {
            RentalErrors.log(e);
            report = new RuleBasedDamageReportGenerator().generate(vehicle, pickup, ret);
        }
        String severity = parseSeverity(report) ?? severityFromConditions(ret);
        Decimal threshold = RentalConfig.get().Damage_Approval_Threshold__c;
        Boolean damage = ret.Damage_Detected__c == true || severity == 'Minor' || severity == 'Major';
        Decimal charge = ret.Estimated_Charge__c ?? 0;
        Boolean needsApproval = damage && (severity == 'Major' || charge > threshold);

        upd.AI_Summary__c = report.left(10000);
        upd.Damage_Severity__c = severity;
        upd.Damage_Detected__c = damage;
        upd.Charge_Status__c = needsApproval ? 'Pending Approval' : (damage && charge > 0 ? 'Approved' : 'Not Applicable');
        update as system upd; // server-computed fields (report, severity, charge status)

        if (needsApproval) {
            submitForApproval(ret, upd);
        }
        return upd;
    }

    private static void submitForApproval(Inspection__c ret, Inspection__c upd) {
        if (ret.Branch_Manager__c == null) {
            Booking__c b = BookingRepository.getById(ret.Booking__c);
            BookingRepository.createStaffTask(
                b,
                'Damage charge needs approval for ' + b.Name,
                'No branch manager is set on the pickup branch, so the approval process could not be started. ' +
                'Severity: ' + upd.Damage_Severity__c + '. Please review inspection ' + ret.Name + '.'
            );
            return;
        }
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(ret.Id);
        req.setSubmitterId(ret.CreatedById);
        req.setProcessDefinitionNameOrId('Damage_Charge_Approval');
        req.setComments('Severity ' + upd.Damage_Severity__c + ', estimated charge ' + (ret.Estimated_Charge__c ?? 0) + '. See AI Summary.');
        req.setSkipEntryCriteria(false);
        Approval.process(req);
    }

    /** Reads '4) Severity: Major' (or 'Severity - Minor') from the report. */
    @TestVisible
    private static String parseSeverity(String report) {
        if (String.isBlank(report)) {
            return null;
        }
        Matcher m = Pattern.compile('(?i)severity[^A-Za-z]{0,6}(none|minor|major)').matcher(report);
        if (!m.find()) {
            return null;
        }
        String s = m.group(1).toLowerCase();
        return s.substring(0, 1).toUpperCase() + s.substring(1);
    }

    private static String severityFromConditions(Inspection__c ret) {
        if (ret.Exterior_Condition__c == 'Major Damage' || ret.Interior_Condition__c == 'Major Damage') {
            return 'Major';
        }
        if (ret.Exterior_Condition__c == 'Minor Damage' || ret.Interior_Condition__c == 'Minor Damage' || ret.Damage_Detected__c == true) {
            return 'Minor';
        }
        return 'None';
    }

    private static Inspection__c loadInspection(Id inspectionId) {
        List<Inspection__c> rows = Database.queryWithBinds(
            'SELECT ' + INSPECTION_FIELDS + ' FROM Inspection__c WHERE Id = :iid LIMIT 1',
            new Map<String, Object>{ 'iid' => inspectionId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    private static DamageReportGenerator generator() {
        return generatorOverride ?? new PromptTemplateDamageReportGenerator();
    }

    /**
     * WITHOUT sharing on purpose: validation must see the booking and earlier inspections regardless of who
     * created them (e.g. a different branch agent did the pickup). Used for validation only.
     */
    private without sharing class Selector {
        Map<Id, Booking__c> bookings(Set<Id> ids) {
            return new Map<Id, Booking__c>(
                [SELECT Id, Status__c, Vehicle__c, Pickup_Branch__r.Manager__c FROM Booking__c WHERE Id IN :ids WITH SYSTEM_MODE]
            );
        }

        Map<Id, Map<String, Inspection__c>> existingInspections(Set<Id> bookingIds) {
            Map<Id, Map<String, Inspection__c>> result = new Map<Id, Map<String, Inspection__c>>();
            for (Inspection__c i : [SELECT Id, Booking__c, Type__c, Odometer__c FROM Inspection__c WHERE Booking__c IN :bookingIds WITH SYSTEM_MODE]) {
                if (!result.containsKey(i.Booking__c)) {
                    result.put(i.Booking__c, new Map<String, Inspection__c>());
                }
                result.get(i.Booking__c).put(i.Type__c, i);
            }
            return result;
        }
    }
}