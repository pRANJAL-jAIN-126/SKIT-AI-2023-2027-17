/**
 * Agentforce action "Get Booking Details" (TDD 8.3). Ownership is enforced in the query: a booking that belongs
 * to someone else is reported exactly like a booking that does not exist (TC-24).
 */
public with sharing class AgentGetBooking {
    public class Req {
        @InvocableVariable(required=true label='Customer Contact Id' description='From the authenticated session context. Never ask the customer for it.')
        public String customerContactId;
        @InvocableVariable(required=true label='Booking number' description='e.g. BK-1042')
        public String bookingNumber;
    }

    public class Res {
        @InvocableVariable public Boolean found = false;
        @InvocableVariable public String status;
        @InvocableVariable public String vehicle;
        @InvocableVariable public String dates;
        @InvocableVariable public Decimal amount;
        @InvocableVariable public String paymentStatus;
        @InvocableVariable(description='Plain-text result to relay to the customer') public String message;
    }

    @InvocableMethod(label='Get Booking Details' description='Reads a booking of the logged-in customer by booking number.' category='Smart Car Rental')
    public static List<Res> run(List<Req> reqs) {
        List<Res> out = new List<Res>();
        for (Req r : reqs) {
            out.add(lookup(r.customerContactId, r.bookingNumber));
        }
        return out;
    }

    public static Res lookup(String customerContactId, String bookingNumber) {
        Res res = new Res();
        try {
            Id contactId = CustomerContext.resolveForAgent(customerContactId);
            Booking__c b = BookingRepository.getOwnedByNumber(contactId, bookingNumber);
            if (b == null) {
                res.message = 'I could not find booking ' + (bookingNumber ?? '') + ' on your account.';
                return res;
            }
            res.found = true;
            res.status = b.Status__c;
            res.vehicle = b.Vehicle__r.Make__c + ' ' + b.Vehicle__r.Model__c;
            res.dates = AgentSupport.range(b.Start_DateTime__c, b.End_DateTime__c);
            res.amount = (b.Total_Amount__c ?? 0) + (b.Deposit_Amount__c ?? 0);
            res.paymentStatus = b.Payment_Status__c;
            res.message = AgentSupport.bookingLine(b) +
                (b.Status__c == BookingService.ST_PENDING && b.Hold_Expires_At__c != null
                    ? '. Hold expires at ' + AgentSupport.time(b.Hold_Expires_At__c) + '.'
                    : '.');
        } catch (Exception e) {
            res.message = RentalErrors.friendlyMessage(e);
        }
        return res;
    }
}