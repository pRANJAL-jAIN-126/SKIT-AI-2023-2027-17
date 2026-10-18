/**
 * Schedules every recurring rental job (TDD 14 step 4). Safe to re-run: jobs that already exist are skipped.
 * Usage: sf apex run --file scripts/apex/schedule-jobs.apex
 */
public with sharing class RentalJobScheduler {
    public static List<String> scheduleAll() {
        Set<String> existing = new Set<String>();
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Rental %' AND State != 'DELETED'
            WITH SYSTEM_MODE
        ]) {
            existing.add(ct.CronJobDetail.Name);
        }
        List<String> scheduled = new List<String>();
        Boolean holdJobsExist = false;
        for (String name : existing) {
            holdJobsExist = holdJobsExist || name.startsWith(BookingHoldExpiryBatch.JOB_PREFIX);
        }
        if (!holdJobsExist) {
            BookingHoldExpiryBatch.scheduleEvery5Minutes();
            scheduled.add(BookingHoldExpiryBatch.JOB_PREFIX + '(x12, every 5 minutes)');
        }
        if (!existing.contains(BookingOverdueBatch.JOB_NAME)) {
            BookingOverdueBatch.scheduleHourly();
            scheduled.add(BookingOverdueBatch.JOB_NAME);
        }
        if (!existing.contains(LicenseRetentionBatch.JOB_NAME)) {
            LicenseRetentionBatch.scheduleDaily();
            scheduled.add(LicenseRetentionBatch.JOB_NAME);
        }
        return scheduled;
    }
}