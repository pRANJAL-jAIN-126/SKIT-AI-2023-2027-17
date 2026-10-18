/**
 * Generates the Generative AI damage report for Return inspections (TDD 7.6, plan D-09). Enqueued by
 * InspectionReturnAction from flow Inspection_Return_Report: the Prompt Builder call is a callout, which cannot
 * run in the record-save transaction. Each inspection is isolated so one failure does not block the others; the
 * service itself falls back to a labelled rule-based report when generative AI is unavailable.
 */
public with sharing class DamageReportQueueable implements Queueable, Database.AllowsCallouts {
    private final List<Id> returnInspectionIds;

    public DamageReportQueueable(List<Id> returnInspectionIds) {
        this.returnInspectionIds = returnInspectionIds;
    }

    public void execute(QueueableContext ctx) {
        for (Id inspectionId : returnInspectionIds) {
            try {
                InspectionService.generateDamageReport(inspectionId);
            } catch (Exception e) {
                RentalErrors.log(e);
            }
        }
    }
}