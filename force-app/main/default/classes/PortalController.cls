/**
 * Thin @AuraEnabled entry point for the Experience Cloud LWCs (TDD 4.2, 9.1). Validates input, resolves the
 * customer from the session (never from the browser), calls the services and returns DTOs. Business exceptions
 * become AuraHandledException with a friendly message; nothing else leaks to the browser.
 *
 * Guest users (public Fleet / Vehicle pages) may only call searchVehicles, getVehicleDetail and
 * getCustomerProfile; every other method calls CustomerContext.requireCustomer() first (TDD 11.2).
 */
public with sharing class PortalController {
    // ------------------------------------------------------------------ public browsing

    @AuraEnabled
    public static List<RentalDtos.VehicleDTO> searchVehicles(VehicleSearchService.SearchRequest request) {
        try {
            return VehicleSearchService.searchWithQuotes(request);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static RentalDtos.VehicleDTO getVehicleDetail(Id vehicleId, Datetime startDt, Datetime endDt) {
        try {
            List<Vehicle__c> rows = [
                SELECT Id, Name, Registration_Number__c, Make__c, Model__c, Year__c, Category__c, Seats__c,
                    Transmission__c, Fuel_Type__c, Daily_Rate__c, Security_Deposit__c, Image_URL__c, Status__c,
                    Branch__c, Branch__r.Name, Branch__r.City__c
                FROM Vehicle__c
                WHERE Id = :vehicleId AND Status__c != 'Retired'
                WITH USER_MODE
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new BookingException('This vehicle is not available.');
            }
            PricingService.Quote q = null;
            if (startDt != null && endDt != null) {
                BookingService.validateDates(startDt, endDt);
                q = PricingService.calculate(rows[0], startDt, endDt);
            }
            return new RentalDtos.VehicleDTO(rows[0], q);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static RentalDtos.CustomerProfileDTO getCustomerProfile() {
        try {
            Id contactId = CustomerContext.isGuest() ? null : CustomerContext.runningUserContactId();
            if (contactId == null) {
                RentalDtos.CustomerProfileDTO guest = new RentalDtos.CustomerProfileDTO();
                guest.isGuest = CustomerContext.isGuest();
                return guest;
            }
            return KycService.profile(contactId);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    // ------------------------------------------------------------------ booking (login required)

    @AuraEnabled
    public static RentalDtos.BookingDTO createHold(Id vehicleId, Datetime startDt, Datetime endDt) {
        try {
            Id contactId = CustomerContext.requireCustomer();
            return new RentalDtos.BookingDTO(BookingService.createHold(contactId, vehicleId, startDt, endDt, 'Portal', null));
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    /** Second Apex call of the booking flow (D4): the Stripe callout happens here, never after the hold DML. */
    @AuraEnabled
    public static StripeService.CheckoutResult startCheckout(Id bookingId) {
        try {
            return StripeService.createCheckoutSession(bookingId, CustomerContext.requireCustomer());
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static RentalDtos.PaymentResultDTO confirmPayment(String sessionId) {
        try {
            return StripeService.verifyAndConfirm(sessionId, CustomerContext.requireCustomer());
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static List<RentalDtos.BookingDTO> getMyBookings() {
        try {
            List<RentalDtos.BookingDTO> result = new List<RentalDtos.BookingDTO>();
            for (Booking__c b : BookingService.bookingsForCustomer(CustomerContext.requireCustomer())) {
                result.add(new RentalDtos.BookingDTO(b));
            }
            return result;
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static RentalDtos.CancelResultDTO getCancellationQuote(Id bookingId) {
        try {
            return toCancelDto(BookingService.previewCancel(bookingId, CustomerContext.requireCustomer()));
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @AuraEnabled
    public static RentalDtos.CancelResultDTO cancelBooking(Id bookingId) {
        try {
            return toCancelDto(BookingService.cancel(bookingId, CustomerContext.requireCustomer()));
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    // ------------------------------------------------------------------ KYC (login required)

    @AuraEnabled
    public static Id uploadLicenseImage(String fileName, String base64Data) {
        try {
            return KycService.saveLicenseImage(CustomerContext.requireCustomer(), fileName, base64Data);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    /** @param consentGiven the /verify consent checkbox (TDD 11.3) – enforced server-side too. */
    @AuraEnabled
    public static RentalDtos.KycResultDTO verifyLicense(Id contentVersionId, Boolean consentGiven, Id bookingId) {
        try {
            Id contactId = CustomerContext.requireCustomer();
            if (consentGiven != true) {
                throw new KycException('Please agree to your licence being read for verification.');
            }
            return KycService.verifyLicense(contactId, contentVersionId, bookingId);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    private static RentalDtos.CancelResultDTO toCancelDto(BookingService.CancelOutcome o) {
        RentalDtos.CancelResultDTO dto = new RentalDtos.CancelResultDTO();
        dto.bookingNumber = o.booking.Name;
        dto.refundAmount = o.quote.refundAmount;
        dto.retainedAmount = o.quote.retainedAmount;
        dto.fullRefund = o.quote.fullRefund;
        dto.message = o.message;
        dto.booking = new RentalDtos.BookingDTO(o.booking);
        return dto;
    }
}