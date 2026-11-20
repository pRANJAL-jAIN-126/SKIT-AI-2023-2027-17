/**
 * Staff side of KYC: the "KYC Review" tab (LWC kycReviewQueue). Lists every customer whose licence is Pending Review
 * (OCR unavailable, name mismatch, unclear photo, unusual licence number) with the uploaded licence photo, and lets
 * staff Approve (entering the expiry date read from the photo) or Reject with a reason.
 *
 * Every decision is written to KYC_Log__c and closes the open "Review licence" Task created by flow KYC_Pending_Task.
 * Only users who can edit Contact.KYC_Status__c (staff) may decide – portal customers cannot.
 */
public with sharing class KycReviewController {
    public class PendingCustomer {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public Datetime submittedAt;
        @AuraEnabled public String reason;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public String extractedName;
        @AuraEnabled public String licenseNumber;
        @AuraEnabled public Date licenseExpiry;
        @AuraEnabled public Date dateOfBirth;
        @AuraEnabled public Date mustBeValidUntil;
        @AuraEnabled public Integer openBookings;
    }

    @AuraEnabled
    public static List<PendingCustomer> getPendingReviews() {
        try {
            requireReviewer();
            List<Contact> contacts = [
                SELECT Id, Name, Email, Phone, License_File_Id__c, License_Name_OCR__c, Driving_License_Number__c,
                    License_Expiry__c, Birthdate, LastModifiedDate
                FROM Contact
                WHERE KYC_Status__c = :KycService.PENDING_REVIEW
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate ASC
                LIMIT 200
            ];
            Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
            Set<Id> docIds = new Set<Id>();
            for (Contact c : contacts) {
                if (c.License_File_Id__c != null) {
                    docIds.add(c.License_File_Id__c);
                }
            }
            Map<Id, Id> versionByDoc = new Map<Id, Id>();
            for (ContentDocument d : [SELECT Id, LatestPublishedVersionId FROM ContentDocument WHERE Id IN :docIds WITH SYSTEM_MODE]) {
                versionByDoc.put(d.Id, d.LatestPublishedVersionId);
            }
            Map<Id, KYC_Log__c> lastLog = new Map<Id, KYC_Log__c>();
            for (KYC_Log__c l : [
                SELECT Contact__c, Status__c, Reason__c, CreatedDate
                FROM KYC_Log__c
                WHERE Contact__c IN :contactIds
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ]) {
                if (!lastLog.containsKey(l.Contact__c)) {
                    lastLog.put(l.Contact__c, l);
                }
            }
            Map<Id, Datetime> latestEnd = new Map<Id, Datetime>();
            Map<Id, Integer> openCount = new Map<Id, Integer>();
            for (Booking__c b : [
                SELECT Customer__c, End_DateTime__c
                FROM Booking__c
                WHERE Customer__c IN :contactIds AND Status__c IN ('Pending Payment', 'Confirmed', 'Active')
                WITH SYSTEM_MODE
            ]) {
                openCount.put(b.Customer__c, (openCount.get(b.Customer__c) ?? 0) + 1);
                Datetime e = latestEnd.get(b.Customer__c);
                if (e == null || b.End_DateTime__c > e) {
                    latestEnd.put(b.Customer__c, b.End_DateTime__c);
                }
            }

            List<PendingCustomer> out = new List<PendingCustomer>();
            for (Contact c : contacts) {
                PendingCustomer p = new PendingCustomer();
                p.contactId = c.Id;
                p.name = c.Name;
                p.email = c.Email;
                p.phone = c.Phone;
                KYC_Log__c log = lastLog.get(c.Id);
                p.submittedAt = log?.CreatedDate ?? c.LastModifiedDate;
                p.reason = describeReason(log);
                Id versionId = versionByDoc.get(c.License_File_Id__c);
                if (versionId != null) {
                    p.photoUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + versionId;
                    p.downloadUrl = '/sfc/servlet.shepherd/version/download/' + versionId;
                }
                p.extractedName = c.License_Name_OCR__c;
                p.licenseNumber = c.Driving_License_Number__c;
                p.licenseExpiry = c.License_Expiry__c;
                p.dateOfBirth = c.Birthdate;
                p.mustBeValidUntil = latestEnd.get(c.Id)?.date();
                p.openBookings = openCount.get(c.Id) ?? 0;
                out.add(p);
            }
            return out;
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    /**
     * Approves the licence. The expiry date (read by staff from the photo) is required: payment checks that the
     * licence stays valid through the return date of the booking.
     */
    @AuraEnabled
    public static void approve(Id contactId, Date licenseExpiry, Date dateOfBirth, String licenseNumber) {
        try {
            requireReviewer();
            Contact c = pendingContact(contactId);
            Date today = Date.today();
            if (licenseExpiry == null || licenseExpiry <= today) {
                throw new KycException('Enter the licence expiry date shown on the photo (it must be in the future).');
            }
            Rental_Config__mdt cfg = RentalConfig.get();
            if (dateOfBirth != null && KycService.ageOn(dateOfBirth, today) < cfg.Min_Age__c.intValue()) {
                throw new KycException('The customer must be at least ' + cfg.Min_Age__c.intValue() + ' years old. Reject this licence instead.');
            }
            Contact upd = new Contact(
                Id = c.Id,
                KYC_Status__c = KycService.VERIFIED,
                KYC_Verified_At__c = System.now(),
                License_Expiry__c = licenseExpiry
            );
            if (dateOfBirth != null) {
                upd.Birthdate = dateOfBirth;
            }
            if (String.isNotBlank(licenseNumber)) {
                upd.Driving_License_Number__c = licenseNumber.toUpperCase().replaceAll('[\\s-]', '').left(25);
            }
            new Writer().decide(upd, new KYC_Log__c(
                Contact__c = c.Id,
                Status__c = KycService.VERIFIED,
                Reason__c = ('Approved manually by ' + UserInfo.getName() + '. Licence valid until ' + licenseExpiry.format() + '.').left(255)
            ));
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static void reject(Id contactId, String reason) {
        try {
            requireReviewer();
            Contact c = pendingContact(contactId);
            if (String.isBlank(reason)) {
                throw new KycException('Enter the reason so the customer knows what to fix.');
            }
            new Writer().decide(
                new Contact(Id = c.Id, KYC_Status__c = KycService.REJECTED, KYC_Verified_At__c = null),
                new KYC_Log__c(
                    Contact__c = c.Id,
                    Status__c = KycService.REJECTED,
                    Reason__c = ('Rejected by ' + UserInfo.getName() + ': ' + reason.trim()).left(255)
                )
            );
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static void requireReviewer() {
        if (!Schema.SObjectType.Contact.fields.KYC_Status__c.isUpdateable()) {
            throw new KycException('Only rental staff can review driving licences.');
        }
    }

    private static Contact pendingContact(Id contactId) {
        List<Contact> rows = [SELECT Id, KYC_Status__c FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1];
        if (rows.isEmpty()) {
            throw new KycException('Customer not found.');
        }
        if (rows[0].KYC_Status__c != KycService.PENDING_REVIEW) {
            throw new KycException('This licence was already reviewed (status ' + rows[0].KYC_Status__c + '). Refresh the list.');
        }
        return rows[0];
    }

    @TestVisible
    private static String describeReason(KYC_Log__c log) {
        if (log == null) {
            return 'Sent for manual review.';
        }
        if (log.Status__c == KycService.ERROR) {
            return 'Automatic check was not available (' + log.Reason__c + '). Please read the licence photo.';
        }
        return log.Reason__c;
    }

    /** KYC fields and logs are written in system mode (customers have no access); staff access checked above. */
    private without sharing class Writer {
        void decide(Contact upd, KYC_Log__c log) {
            update as system upd;
            insert as system log;
            List<Task> open = [
                SELECT Id
                FROM Task
                WHERE WhoId = :upd.Id AND IsClosed = FALSE AND Subject LIKE 'Review licence%'
                WITH SYSTEM_MODE
            ];
            for (Task t : open) {
                t.Status = 'Completed';
            }
            if (!open.isEmpty()) {
                update as system open;
            }
        }
    }
}
