/**
 * Agentforce action "Create Booking Hold" (TDD 8.3). Creates a Pending Payment hold through BookingService – the
 * same code path as the portal. It never confirms a booking: only a verified Stripe payment does (TDD 8.4).
 * customerContactId must be bound to the session context in the agent, and is re-validated by CustomerContext.
 */
public with sharing class AgentCreateBooking {
    public class Req {
        @InvocableVariable(required=true label='Customer Contact Id' description='From the authenticated session context. Never ask the customer for it.')
        public String customerContactId;
        @InvocableVariable(required=true label='Vehicle Id' description='Id returned by Search Available Vehicles')
        public String vehicleId;
        @InvocableVariable(required=true label='Pickup date-time' description='ISO 8601 date-time')
        public Datetime pickupDateTime;
        @InvocableVariable(required=true label='Return date-time' description='ISO 8601 date-time')
        public Datetime returnDateTime;
        @InvocableVariable(label='Session Id' description='Agent / messaging session id, logged on the booking for audit')
        public String sessionId;
    }

    public class Res {
        @InvocableVariable public Boolean success = false;
        @InvocableVariable public String bookingNumber;
        @InvocableVariable public Decimal totalAmount;
        @InvocableVariable public String holdExpiresAt;
        @InvocableVariable public String kycStatus;
        @InvocableVariable public String verifyUrl;
        @InvocableVariable public String paymentUrl;
        @InvocableVariable(description='Plain-text result to relay to the customer') public String message;
    }

    @InvocableMethod(
        label='Create Booking Hold'
        description='Holds a vehicle for the customer as Pending Payment after they explicitly confirmed vehicle, dates and price. Does not confirm the booking.'
        category='Smart Car Rental'
    )
    public static List<Res> run(List<Req> reqs) {
        List<Res> out = new List<Res>();
        for (Req r : reqs) {
            out.add(create(r));
        }
        return out;
    }

    public static Res create(Req r) {
        Res res = new Res();
        try {
            Id contactId = CustomerContext.resolveForAgent(r.customerContactId, r.sessionId);
            Id vehicleId = CustomerContext.toId(r.vehicleId);
            if (vehicleId == null || vehicleId.getSobjectType() != Vehicle__c.SObjectType) {
                throw new BookingException('Please search for vehicles first and choose one of the results.');
            }
            Booking__c b = BookingService.createHold(contactId, vehicleId, r.pickupDateTime, r.returnDateTime, 'Agentforce', r.sessionId);
            res.success = true;
            res.bookingNumber = b.Name;
            res.totalAmount = (b.Total_Amount__c ?? 0) + (b.Deposit_Amount__c ?? 0);
            res.holdExpiresAt = AgentSupport.time(b.Hold_Expires_At__c);
            res.kycStatus = b.Customer__r.KYC_Status__c;
            res.verifyUrl = RentalConfig.verifyUrl(b.Id);
            res.paymentUrl = RentalConfig.paymentUrl(b.Id);
            String held = 'Held as ' + b.Name + ' until ' + res.holdExpiresAt + '. Total ' + AgentSupport.inr(b.Total_Amount__c) +
                ' incl. GST plus refundable deposit ' + AgentSupport.inr(b.Deposit_Amount__c) + '. ';
            res.message = res.kycStatus == 'Verified'
                ? held + 'Pay here to confirm: ' + res.paymentUrl + ' . The booking is confirmed only after payment.'
                : held + 'Your licence is not verified yet: please verify here ' + res.verifyUrl + ' , then pay here ' + res.paymentUrl +
                  ' to confirm. The booking is confirmed only after payment.';
        } catch (Exception e) {
            res.message = 'Hold not created: ' + RentalErrors.friendlyMessage(e);
        }
        return res;
    }
}
