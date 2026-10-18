/**
 * On-demand action to (re)generate the Prompt Builder damage report for a Return inspection, e.g. from a staff
 * quick action or flow after correcting inspection data. The automatic generation after a return is done by
 * DamageReportQueueable (enqueued from flow Inspection_Return_Report). Each record is isolated.
 */
public with sharing class DamageReportAction {
    public class Request {
        @InvocableVariable(required=true label='Return inspection Id')
        public Id inspectionId;
    }

    @InvocableMethod(label='Generate Damage Report' description='Regenerates the pickup-vs-return damage report with generative AI and routes large charges for approval.' category='Smart Car Rental')
    public static void run(List<Request> requests) {
        for (Request r : requests) {
            try {
                InspectionService.generateDamageReport(r.inspectionId);
            } catch (Exception e) {
                RentalErrors.log(e);
            }
        }
    }
}