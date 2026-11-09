/**
 * Thin trigger – validation/defaults in InspectionTriggerHandler. Booking state changes after an inspection
 * are done by flows Inspection_Pickup / Inspection_Return_Report (TDD 12).
 */
trigger InspectionTrigger on Inspection__c(before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        InspectionTriggerHandler.beforeInsert(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        InspectionTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}