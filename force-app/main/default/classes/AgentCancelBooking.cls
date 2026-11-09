/**
 * Agentforce action "Cancel Booking" (TDD 8.3, 8.4). Refuses unless confirmed = true; ownership re-checked in
 * BookingService.cancel; refund rule applied by the same service as the portal.
 */
public with sharing class AgentCancelBooking {
    public class Req {
        @InvocableVariable(required=true label='Customer Contact Id' description='From the authenticated session context. Never ask the customer for it.')
        public String customerContactId;
        @InvocableVariable(required=true label='Booking number' description='e.g. BK-1042')
        public String bookingNumber;
        @InvocableVariable(required=true label='Confirmed' description='True only after the booking details were read back and the customer explicitly said yes to cancelling')
        public Boolean confirmed;
    }

    public class Res {
        @InvocableVariable public Boolean cancelled = false;
        @InvocableVariable public Decimal refundAmount;
        @InvocableVariable(description='Plain-text result to relay to the customer') public String message;
    }

    @InvocableMethod(label='Cancel Booking' description='Cancels a booking of the logged-in customer after explicit confirmation and applies the refund policy.' category='Smart Car Rental')
    public static List<Res> run(List<Req> reqs) {
        List<Res> out = new List<Res>();
        for (Req r : reqs) {
            out.add(cancel(r.customerContactId, r.bookingNumber, r.confirmed));
        }
        return out;
    }

    public static Res cancel(String customerContactId, String bookingNumber, Boolean confirmed) {
        Res res = new Res();
        try {
            Id contactId = CustomerContext.resolveForAgent(customerContactId);
            Booking__c b = BookingRepository.getOwnedByNumber(contactId, bookingNumber);
            if (b == null) {
                res.message = 'I could not find booking ' + (bookingNumber ?? '') + ' on your account.';
                return res;
            }
            if (confirmed != true) {
                BookingService.CancelOutcome preview = BookingService.previewCancel(b.Id, contactId);
                res.refundAmount = preview.quote.refundAmount;
                res.message = 'Not cancelled yet. ' + AgentSupport.bookingLine(b) + '. ' + preview.message +
                    ' Ask the customer to confirm explicitly before cancelling.';
                return res;
            }
            BookingService.CancelOutcome o = BookingService.cancel(b.Id, contactId);
            res.cancelled = true;
            res.refundAmount = o.quote.refundAmount;
            res.message = o.message;
        } catch (Exception e) {
            res.message = 'Not cancelled: ' + RentalErrors.friendlyMessage(e);
        }
        return res;
    }
}