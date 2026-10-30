/**
 * Thin trigger – all logic lives in BookingTriggerHandler (TDD 9.2, 12).
 */
trigger BookingTrigger on Booking__c(before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        BookingTriggerHandler.beforeInsert(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        BookingTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}