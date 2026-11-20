/**
 * Gives every new portal customer (self-registered on the Smart Car Rental site or created by staff) the
 * permission sets the portal needs: Rental_Customer (objects/fields, Apex classes) and Rental_Integration
 * (OCR / Stripe named-credential access). Without them a new customer can log in but cannot book or verify KYC.
 *
 * Runs from UserTrigger (after insert). Permission set assignment is setup DML and cannot share a transaction
 * with the User insert's non-setup DML (self-registration also inserts the Contact), so it runs @future.
 */
public without sharing class CustomerPermissionAssigner {
    public static final Set<String> CUSTOMER_PROFILES = new Set<String>{ 'Customer Community User', 'Customer Community Login User' };
    public static final Set<String> CUSTOMER_PERMISSION_SETS = new Set<String>{ 'Rental_Customer', 'Rental_Integration' };

    /** Trigger entry: picks the new portal users (ContactId set) and assigns asynchronously. */
    public static void afterInsert(List<User> news) {
        Set<Id> portalUserIds = new Set<Id>();
        for (User u : news) {
            if (u.ContactId != null && u.IsActive) {
                portalUserIds.add(u.Id);
            }
        }
        if (portalUserIds.isEmpty()) {
            return;
        }
        if (System.isFuture() || System.isBatch()) {
            assign(portalUserIds);
        } else {
            assignAsync(portalUserIds);
        }
    }

    @future
    public static void assignAsync(Set<Id> userIds) {
        assign(userIds);
    }

    /** Idempotent: skips users whose profile is not a customer profile and assignments that already exist. */
    public static Integer assign(Set<Id> userIds) {
        List<User> customers = [
            SELECT Id
            FROM User
            WHERE Id IN :userIds AND ContactId != NULL AND IsActive = TRUE AND Profile.Name IN :CUSTOMER_PROFILES
            WITH SYSTEM_MODE
        ];
        if (customers.isEmpty()) {
            return 0;
        }
        Map<Id, PermissionSet> permSets = new Map<Id, PermissionSet>(
            [SELECT Id FROM PermissionSet WHERE Name IN :CUSTOMER_PERMISSION_SETS WITH SYSTEM_MODE]
        );
        Set<String> existing = new Set<String>();
        for (PermissionSetAssignment a : [
            SELECT AssigneeId, PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :customers AND PermissionSetId IN :permSets.keySet()
            WITH SYSTEM_MODE
        ]) {
            existing.add(a.AssigneeId + ':' + a.PermissionSetId);
        }
        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        for (User u : customers) {
            for (Id psId : permSets.keySet()) {
                if (!existing.contains(u.Id + ':' + psId)) {
                    toInsert.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId));
                }
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        return toInsert.size();
    }
}
