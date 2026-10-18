/**
 * Booking engine (TDD 6.4 state machine, 7.5, 9.4). Shared by the portal (PortalController), the Agentforce
 * actions (Agent*) and the fallback chat – business rules live only here.
 */
public with sharing class BookingService {
    public static final String ST_PENDING = 'Pending Payment';
    public static final String ST_CONFIRMED = 'Confirmed';
    public static final String ST_ACTIVE = 'Active';
    public static final String ST_COMPLETED = 'Completed';
    public static final String ST_CANCELLED = 'Cancelled';
    public static final String ST_EXPIRED = 'Expired';
    public static final String PAY_UNPAID = 'Unpaid';
    public static final String PAY_PAID = 'Paid';
    public static final String PAY_REFUNDED = 'Refunded';
    public static final String PAY_FAILED = 'Failed';
    public static final Set<String> SOURCES = new Set<String>{ 'Portal', 'Agentforce', 'Staff' };

    public class CancelOutcome {
        public Booking__c booking;
        public PricingService.RefundQuote quote;
        public String message;
    }

    // ------------------------------------------------------------------ validation

    /** End after start, start not in the past, length <= Max_Rental_Days (TDD 8.4). */
    public static void validateDates(Datetime startDt, Datetime endDt) {
        if (startDt == null || endDt == null) {
            throw new BookingException('Please choose a valid pickup and return time.');
        }
        if (endDt <= startDt) {
            throw new BookingException('Return time must be after the pickup time.');
        }
        if (startDt < System.now().addMinutes(-5)) {
            throw new BookingException('Pickup time cannot be in the past.');
        }
        Integer maxDays = RentalConfig.get().Max_Rental_Days__c.intValue();
        if (endDt.getTime() - startDt.getTime() > maxDays * 24L * 3600000L) {
            throw new BookingException('A rental can be at most ' + maxDays + ' days long.');
        }
    }

    // ------------------------------------------------------------------ hold

    /**
     * Creates a Pending Payment hold (TDD 9.4). Locks the vehicle row so concurrent requests for the same car
     * are serialised, then re-checks availability. DML only – never followed by a callout in this transaction (D4).
     */
    public static Booking__c createHold(Id contactId, Id vehicleId, Datetime startDt, Datetime endDt, String source, String sessionId) {
        if (contactId == null) {
            throw new BookingException('A customer account is required for this action.');
        }
        if (vehicleId == null || vehicleId.getSobjectType() != Vehicle__c.SObjectType) {
            throw new BookingException('Please choose a vehicle.');
        }
        validateDates(startDt, endDt);
        Contact customer = BookingRepository.getCustomer(contactId);
        if (customer == null) {
            throw new BookingException('A customer account is required for this action.');
        }

        Vehicle__c v = lockVehicle(vehicleId);
        if (v.Status__c == 'Maintenance' || v.Status__c == 'Retired') {
            throw new BookingException('This vehicle is not available.');
        }
        if (VehicleSearchService.busyVehicleIds(startDt, endDt, new Set<Id>{ vehicleId }).contains(vehicleId)) {
            throw new BookingException('Sorry, this vehicle was just booked for those dates.');
        }

        PricingService.Quote q = PricingService.calculate(v, startDt, endDt);
        Booking__c b = new Booking__c(
            Customer__c = contactId,
            Vehicle__c = vehicleId,
            Pickup_Branch__c = v.Branch__c,
            Start_DateTime__c = startDt,
            End_DateTime__c = endDt,
            Rental_Days__c = q.days,
            Total_Amount__c = q.total,
            Deposit_Amount__c = q.deposit,
            Status__c = ST_PENDING,
            Payment_Status__c = PAY_UNPAID,
            Source__c = SOURCES.contains(source) ? source : 'Portal',
            Agent_Session_Id__c = String.isBlank(sessionId) ? null : sessionId.left(80),
            Hold_Expires_At__c = System.now().addMinutes(RentalConfig.get().Hold_Minutes__c.intValue())
        );
        BookingRepository.insertBookings(new List<Booking__c>{ b }); // DML only. No callout in this transaction.
        return BookingRepository.getById(b.Id);
    }

    private static Vehicle__c lockVehicle(Id vehicleId) {
        List<Vehicle__c> rows;
        try {
            rows = [
                SELECT Id, Daily_Rate__c, Security_Deposit__c, Branch__c, Status__c
                FROM Vehicle__c
                WHERE Id = :vehicleId
                WITH SYSTEM_MODE
                LIMIT 1
                FOR UPDATE
            ];
        } catch (QueryException e) {
            // UNABLE_TO_LOCK_ROW: another customer is booking this car right now
            throw new BookingException('This vehicle is being booked by someone else right now. Please try again.');
        }
        if (rows.isEmpty()) {
            throw new BookingException('This vehicle is not available.');
        }
        return rows[0];
    }

    // ------------------------------------------------------------------ confirm (only via StripeService)

    /**
     * Pending Payment (or Expired after a late payment) -> Confirmed + Paid. Called only by StripeService after
     * the Stripe session has been verified server-side; the trigger refuses this transition otherwise (TDD 8.4).
     */
    public static Booking__c confirmAfterPayment(Id bookingId) {
        Booking__c locked = BookingRepository.lockForUpdate(bookingId);
        if (locked == null) {
            throw new BookingException('Booking not found.');
        }
        if (locked.Status__c == ST_CONFIRMED) {
            return BookingRepository.getById(bookingId); // idempotent
        }
        if (locked.Status__c != ST_PENDING && locked.Status__c != ST_EXPIRED) {
            throw new BookingException('This booking can no longer be confirmed (status ' + locked.Status__c + ').');
        }
        Contact customer = BookingRepository.getCustomer(locked.Customer__c);
        if (customer == null || customer.KYC_Status__c != 'Verified') {
            throw new BookingException('Your driving licence is not verified yet.');
        }
        if (BookingRepository.hasOverlap(locked.Vehicle__c, locked.Start_DateTime__c, locked.End_DateTime__c, locked.Id)) {
            throw new BookingException('The vehicle was booked by someone else after your hold expired.');
        }
        Booking__c upd = new Booking__c(Id = bookingId, Status__c = ST_CONFIRMED, Payment_Status__c = PAY_PAID);
        BookingTriggerHandler.confirmationGateOpen = true;
        try {
            BookingRepository.updateBookings(new List<Booking__c>{ upd });
        } finally {
            BookingTriggerHandler.confirmationGateOpen = false;
        }
        return BookingRepository.getById(bookingId);
    }

    // ------------------------------------------------------------------ cancel

    public static Boolean isCancellable(Booking__c b) {
        return b.Status__c == ST_PENDING || b.Status__c == ST_CONFIRMED;
    }

    public static Boolean isPayable(Booking__c b) {
        return b.Status__c == ST_PENDING && b.Payment_Status__c != PAY_PAID && b.Hold_Expires_At__c != null &&
            b.Hold_Expires_At__c > System.now();
    }

    /** Refund preview for the confirmation dialog / agent read-back. */
    public static CancelOutcome previewCancel(Id bookingId, Id contactId) {
        Booking__c b = requireOwned(contactId, bookingId);
        if (!isCancellable(b)) {
            throw new BookingException('This booking can no longer be cancelled.');
        }
        CancelOutcome o = new CancelOutcome();
        o.booking = b;
        o.quote = quoteFor(b);
        o.message = describeRefund(b, o.quote);
        return o;
    }

    /**
     * Customer / staff cancellation (TDD 7.5, A4). Booking is cancelled in this transaction; the Stripe refund
     * (a callout) runs in StripeRefundQueueable afterwards because a callout may not follow DML (D4, plan D-06).
     */
    public static CancelOutcome cancel(Id bookingId, Id contactId) {
        Booking__c b = requireOwned(contactId, bookingId);
        BookingRepository.lockForUpdate(b.Id);
        if (!isCancellable(b)) {
            throw new BookingException('This booking can no longer be cancelled.');
        }
        Payment__c paid = BookingRepository.succeededPayment(b.Id);
        PricingService.RefundQuote q = PricingService.refundQuote(b, paid?.Amount__c, System.now());

        Booking__c upd = new Booking__c(Id = b.Id, Status__c = ST_CANCELLED, Refund_Amount__c = q.refundAmount);
        BookingRepository.updateBookings(new List<Booking__c>{ upd });

        List<Payment__c> open = BookingRepository.initiatedPayments(new Set<Id>{ b.Id });
        for (Payment__c p : open) {
            p.Status__c = 'Failed';
            p.Failure_Reason__c = 'Booking cancelled before payment';
        }
        if (!open.isEmpty()) {
            BookingRepository.updatePayments(open);
        }
        if (paid != null && q.refundAmount > 0) {
            System.enqueueJob(new StripeRefundQueueable(paid.Id, q.refundAmount));
        }

        CancelOutcome o = new CancelOutcome();
        o.booking = BookingRepository.getById(b.Id);
        o.quote = q;
        o.message = 'Booking ' + b.Name + ' has been cancelled. ' + describeRefund(b, q);
        return o;
    }

    private static PricingService.RefundQuote quoteFor(Booking__c b) {
        Payment__c paid = BookingRepository.succeededPayment(b.Id);
        return PricingService.refundQuote(b, paid?.Amount__c, System.now());
    }

    private static String describeRefund(Booking__c b, PricingService.RefundQuote q) {
        if (q.paidAmount <= 0) {
            return 'No payment was taken, so there is nothing to refund.';
        }
        if (q.fullRefund) {
            return 'You will receive a full refund of ' + AgentSupport.inr(q.refundAmount) + '.';
        }
        return 'Because it is less than ' + RentalConfig.get().Free_Cancel_Hours__c.intValue() +
            ' hours before pickup, one day\'s rent (' + AgentSupport.inr(q.retainedAmount) +
            ') is retained and ' + AgentSupport.inr(q.refundAmount) + ' will be refunded.';
    }

    // ------------------------------------------------------------------ hold expiry (BookingHoldExpiryBatch)

    /** Pending Payment bookings past Hold_Expires_At__c -> Expired; their Initiated payments -> Failed. */
    public static Integer expireHolds(List<Booking__c> scope) {
        Datetime nowDt = System.now();
        List<Booking__c> toExpire = new List<Booking__c>();
        for (Booking__c b : scope) {
            if (b.Status__c == ST_PENDING && b.Payment_Status__c != PAY_PAID && b.Hold_Expires_At__c != null &&
                b.Hold_Expires_At__c < nowDt) {
                toExpire.add(new Booking__c(Id = b.Id, Status__c = ST_EXPIRED));
            }
        }
        if (toExpire.isEmpty()) {
            return 0;
        }
        BookingRepository.updateBookings(toExpire);
        List<Payment__c> open = BookingRepository.initiatedPayments(new Map<Id, Booking__c>(toExpire).keySet());
        for (Payment__c p : open) {
            p.Status__c = 'Failed';
            p.Failure_Reason__c = 'Hold expired before payment completed';
        }
        if (!open.isEmpty()) {
            BookingRepository.updatePayments(open);
        }
        return toExpire.size();
    }

    // ------------------------------------------------------------------ queries

    public static Booking__c requireOwned(Id contactId, Id bookingId) {
        Booking__c b = BookingRepository.getOwned(contactId, bookingId);
        if (b == null) {
            // Same message whether the booking does not exist or belongs to someone else (no data leak).
            throw new BookingException('Booking not found.');
        }
        return b;
    }

    /** "My Bookings" – USER_MODE so the customer's sharing (sharing set) and FLS apply (TDD 11.2). */
    public static List<Booking__c> bookingsForCustomer(Id contactId) {
        return [
            SELECT Id, Name, Customer__c, Vehicle__c, Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle_Display__c,
                Pickup_Branch__r.Name, Start_DateTime__c, End_DateTime__c, Rental_Days__c, Total_Amount__c,
                Deposit_Amount__c, Late_Fee__c, Refund_Amount__c, Status__c, Payment_Status__c, Hold_Expires_At__c,
                Is_Overdue__c, Source__c
            FROM Booking__c
            WHERE Customer__c = :contactId
            WITH USER_MODE
            ORDER BY Start_DateTime__c DESC
            LIMIT 100
        ];
    }
}