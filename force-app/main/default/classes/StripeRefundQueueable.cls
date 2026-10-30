/**
 * Executes the Stripe refund after a cancellation has been committed (plan D-06: a callout may not follow DML
 * in the same transaction). Failures never undo the cancellation – they are recorded and handed to staff.
 */
public with sharing class StripeRefundQueueable implements Queueable, Database.AllowsCallouts {
    private final Id paymentId;
    private final Decimal amount;

    public StripeRefundQueueable(Id paymentId, Decimal amount) {
        this.paymentId = paymentId;
        this.amount = amount;
    }

    public void execute(QueueableContext ctx) {
        try {
            StripeService.refund(paymentId, amount);
        } catch (Exception e) {
            StripeService.recordRefundFailure(paymentId, amount, RentalErrors.friendlyMessage(e));
        }
    }
}