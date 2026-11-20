/** New portal customers (self-registration) get the Smart Car Rental customer permission sets. */
trigger UserTrigger on User(after insert) {
    CustomerPermissionAssigner.afterInsert(Trigger.new);
}
