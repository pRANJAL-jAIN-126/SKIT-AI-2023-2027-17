/**
 * Data transfer objects returned to LWC (and reused by the fallback chat). DTOs never carry raw licence
 * numbers – only masked values (TDD NFR-03).
 */
public with sharing class RentalDtos {
    public class VehicleDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String make;
        @AuraEnabled public String model;
        @AuraEnabled public Decimal year;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal seats;
        @AuraEnabled public String transmission;
        @AuraEnabled public String fuelType;
        @AuraEnabled public Decimal dailyRate;
        @AuraEnabled public Decimal securityDeposit;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Id branchId;
        @AuraEnabled public String branchName;
        @AuraEnabled public String city;
        @AuraEnabled public Integer days;
        @AuraEnabled public Decimal subtotal;
        @AuraEnabled public Decimal tax;
        @AuraEnabled public Decimal deposit;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Decimal grandTotal;

        public VehicleDTO(Vehicle__c v, PricingService.Quote q) {
            id = v.Id;
            name = v.Name;
            registrationNumber = v.Registration_Number__c;
            make = v.Make__c;
            model = v.Model__c;
            year = v.Year__c;
            category = v.Category__c;
            seats = v.Seats__c;
            transmission = v.Transmission__c;
            fuelType = v.Fuel_Type__c;
            dailyRate = v.Daily_Rate__c;
            securityDeposit = v.Security_Deposit__c;
            imageUrl = v.Image_URL__c;
            branchId = v.Branch__c;
            branchName = v.Branch__r?.Name;
            city = v.Branch__r?.City__c;
            if (q != null) {
                days = q.days;
                subtotal = q.subtotal;
                tax = q.tax;
                deposit = q.deposit;
                total = q.total;
                grandTotal = q.grandTotal;
            }
        }

        public String displayName() {
            return make + ' ' + model;
        }
    }

    public class BookingDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String bookingNumber;
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public String branchName;
        @AuraEnabled public Datetime startDt;
        @AuraEnabled public Datetime endDt;
        @AuraEnabled public Decimal rentalDays;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal depositAmount;
        @AuraEnabled public Decimal grandTotal;
        @AuraEnabled public Decimal lateFee;
        @AuraEnabled public Decimal refundAmount;
        @AuraEnabled public String status;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Datetime holdExpiresAt;
        @AuraEnabled public Boolean isOverdue;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean canCancel;
        @AuraEnabled public Boolean canPay;

        public BookingDTO(Booking__c b) {
            id = b.Id;
            bookingNumber = b.Name;
            vehicleId = b.Vehicle__c;
            vehicleName = b.Vehicle__r == null ? b.Vehicle_Display__c : b.Vehicle__r.Make__c + ' ' + b.Vehicle__r.Model__c;
            branchName = b.Pickup_Branch__r?.Name;
            startDt = b.Start_DateTime__c;
            endDt = b.End_DateTime__c;
            rentalDays = b.Rental_Days__c;
            totalAmount = b.Total_Amount__c;
            depositAmount = b.Deposit_Amount__c;
            grandTotal = (b.Total_Amount__c ?? 0) + (b.Deposit_Amount__c ?? 0);
            lateFee = b.Late_Fee__c;
            refundAmount = b.Refund_Amount__c;
            status = b.Status__c;
            paymentStatus = b.Payment_Status__c;
            holdExpiresAt = b.Hold_Expires_At__c;
            isOverdue = b.Is_Overdue__c == true;
            source = b.Source__c;
            canCancel = BookingService.isCancellable(b);
            canPay = BookingService.isPayable(b);
        }
    }

    public class CustomerProfileDTO {
        @AuraEnabled public Boolean isGuest = false;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String kycStatus;
        @AuraEnabled public String maskedLicenseNumber;
        @AuraEnabled public Date licenseExpiry;
        @AuraEnabled public Datetime kycVerifiedAt;
    }

    public class PaymentResultDTO {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public BookingDTO booking;

        public PaymentResultDTO(String status, String message, BookingDTO booking) {
            this.status = status;
            this.message = message;
            this.booking = booking;
        }
    }

    public class CancelResultDTO {
        @AuraEnabled public String bookingNumber;
        @AuraEnabled public Decimal refundAmount;
        @AuraEnabled public Decimal retainedAmount;
        @AuraEnabled public Boolean fullRefund;
        @AuraEnabled public String message;
        @AuraEnabled public BookingDTO booking;
    }

    public class KycResultDTO {
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public String extractedName;
        @AuraEnabled public Date dateOfBirth;
        @AuraEnabled public String maskedLicenseNumber;
        @AuraEnabled public Date licenseExpiry;
        @AuraEnabled public Decimal confidence;
    }

    public class InspectionContextDTO {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public String bookingNumber;
        @AuraEnabled public String bookingStatus;
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public Decimal currentOdometer;
        @AuraEnabled public String nextType;
        @AuraEnabled public Decimal pickupOdometer;
        @AuraEnabled public String pickupFuel;
        @AuraEnabled public String message;
    }
}