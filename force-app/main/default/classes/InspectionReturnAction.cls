/**
 * Flow action used by Inspection_Return_Report: completes the booking, records the actual return time and late
 * fee, updates the vehicle odometer, then enqueues DamageReportQueueable for the Generative AI damage report.
 * Thin wrapper over InspectionService.
 */
public with sharing class InspectionReturnAction {
    public class Request {
        @InvocableVariable(required=true label='Return inspection Id')
        public Id inspectionId;
    }

    @InvocableMethod(label='Process Return Inspection' description='Completes the booking after a Return inspection: actual return, late fee, odometer.' category='Smart Car Rental')
    public static void run(List<Request> requests) {
        List<Id> ids = new List<Id>();
        for (Request r : requests) {
            ids.add(r.inspectionId);
        }
        InspectionService.processReturn(ids);
        if (!ids.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new DamageReportQueueable(ids));
        }
    }
}