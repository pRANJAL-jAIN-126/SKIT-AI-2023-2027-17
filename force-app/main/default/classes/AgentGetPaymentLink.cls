/**
 * Agentforce action "Get Payment Link" (TDD 8.3). Returns the portal page that starts Stripe Checkout
 * (/my-bookings?pay=...). If KYC is not verified, the verification link is returned first (TDD 8.2).
 */
public with sharing class AgentGetPaymentLink {
    public class Req {
        @InvocableVariable(required=true label='Customer Contact Id' description='From the authenticated session context. Never ask the customer for it.')
        public String customerContactId;
        @InvocableVariable(required=true label='Booking number' description='e.g. BK-1042')
        public String bookingNumber;
    }

    public class Res {
        @InvocableVariable public String url;
        @InvocableVariable(description='Plain-text result to relay to the customer') public String message;
    }

    @InvocableMethod(label='Get Payment Link' description='Gives the customer the link to pay for a held booking.' category='Smart Car Rental')
    public static List<Res> run(List<Req> reqs) {
        List<Res> out = new List<Res>();
        for (Req r : reqs) {
            out.add(link(r.customerContactId, r.bookingNumber));
        }
        return out;
    }

    public static Res link(String customerContactId, String bookingNumber) {
        Res res = new Res();
        try {
            Id contactId = CustomerContext.resolveForAgent(customerContactId);
            Booking__c b = BookingRepository.getOwnedByNumber(contactId, bookingNumber);
            if (b == null) {
                res.message = 'I could not find booking ' + (bookingNumber ?? '') + ' on your account.';
                return res;
            }
            if (b.Payment_Status__c == BookingService.PAY_PAID || b.Status__c == BookingService.ST_CONFIRMED) {
                res.message = 'Booking ' + b.Name + ' is already paid.';
                return res;
            }
            if (!BookingService.isPayable(b)) {
                res.message = 'Booking ' + b.Name + ' can no longer be paid (status ' + b.Status__c +
                    '). Please search again to create a new hold.';
                return res;
            }
            if (b.Customer__r.KYC_Status__c != 'Verified') {
                res.url = RentalConfig.verifyUrl(b.Id);
                res.message = 'Your licence must be verified before payment. Verify here: ' + res.url +
                    ' . After that, pay here: ' + RentalConfig.paymentUrl(b.Id) + ' . The hold expires at ' +
                    AgentSupport.time(b.Hold_Expires_At__c) + '.';
                return res;
            }
            res.url = RentalConfig.paymentUrl(b.Id);
            res.message = 'Pay for ' + b.Name + ' here: ' + res.url + ' . The hold expires at ' +
                AgentSupport.time(b.Hold_Expires_At__c) + '. The booking is confirmed only after payment.';
        } catch (Exception e) {
            res.message = RentalErrors.friendlyMessage(e);
        }
        return res;
    }
}