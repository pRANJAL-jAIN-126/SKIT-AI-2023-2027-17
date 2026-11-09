/**
 * Logic for InspectionTrigger: defaults and ordering / odometer validation (TDD 6.8). Booking state changes
 * are handled by flows Inspection_Pickup and Inspection_Return_Report.
 */
public with sharing class InspectionTriggerHandler {
    public static void beforeInsert(List<Inspection__c> news) {
        InspectionService.validateBeforeInsert(news);
    }

    public static void beforeUpdate(List<Inspection__c> news, Map<Id, Inspection__c> oldMap) {
        InspectionService.validateBeforeUpdate(news, oldMap);
    }
}