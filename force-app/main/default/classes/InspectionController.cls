/**
 * Staff entry point for the inspectionForm LWC (Booking record page). Thin wrapper over InspectionService.
 */
public with sharing class InspectionController {
    @AuraEnabled
    public static RentalDtos.InspectionContextDTO getInspectionContext(Id bookingId) {
        try {
            return InspectionService.getContext(bookingId);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static Id saveInspection(Inspection__c inspection, List<Id> contentDocumentIds) {
        try {
            return InspectionService.saveInspection(inspection, contentDocumentIds);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }
}