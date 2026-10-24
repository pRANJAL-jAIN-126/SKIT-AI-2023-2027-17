/**
 * Single access point for Rental_Config__mdt (record 'Default', TDD 6.7).
 * Missing values fall back to the TDD defaults so a partially configured org still behaves predictably.
 */
public with sharing class RentalConfig {
    @TestVisible
    private static Rental_Config__mdt cached;

    public static Rental_Config__mdt get() {
        if (cached == null) {
            Rental_Config__mdt cfg = Rental_Config__mdt.getInstance('Default');
            cached = applyDefaults(cfg == null ? new Rental_Config__mdt() : cfg);
        }
        return cached;
    }

    /** Custom metadata records are read-only in memory, so a new record is built with defaults applied. */
    @TestVisible
    private static Rental_Config__mdt applyDefaults(Rental_Config__mdt c) {
        return applyDefaults(c, new Map<String, Object>());
    }

    @TestVisible
    private static Rental_Config__mdt applyDefaults(Rental_Config__mdt c, Map<String, Object> overrides) {
        Map<String, Object> v = new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Hold_Minutes__c' => c.Hold_Minutes__c ?? 15,
            'Min_Age__c' => c.Min_Age__c ?? 21,
            'Tax_Rate__c' => c.Tax_Rate__c ?? 0.18,
            'Min_OCR_Confidence__c' => c.Min_OCR_Confidence__c ?? 0.80,
            'Name_Match_Threshold__c' => c.Name_Match_Threshold__c ?? 0.80,
            'Late_Fee_Per_Hour__c' => c.Late_Fee_Per_Hour__c ?? 0.10,
            'Free_Cancel_Hours__c' => c.Free_Cancel_Hours__c ?? 24,
            'Damage_Approval_Threshold__c' => c.Damage_Approval_Threshold__c ?? 5000,
            'Max_Rental_Days__c' => c.Max_Rental_Days__c ?? 30,
            'Currency_Code__c' => String.isBlank(c.Currency_Code__c) ? 'inr' : c.Currency_Code__c.toLowerCase(),
            'Max_Image_MB__c' => c.Max_Image_MB__c ?? 3,
            'License_Retention_Days__c' => c.License_Retention_Days__c ?? 30,
            'OCR_Provider_Class__c' => String.isBlank(c.OCR_Provider_Class__c) ? 'OcrSpaceClient' : c.OCR_Provider_Class__c,
            'Support_Email__c' => c.Support_Email__c ?? 'support@smartcarrental.example',
            'Site_URL__c' => c.Site_URL__c == null ? '' : c.Site_URL__c.removeEnd('/')
        };
        v.putAll(overrides);
        return (Rental_Config__mdt) JSON.deserialize(JSON.serialize(v), Rental_Config__mdt.class);
    }

    /** Experience Cloud base URL without trailing slash. */
    public static String siteUrl() {
        return get().Site_URL__c;
    }

    public static String verifyUrl(Id bookingId) {
        return siteUrl() + '/verify' + (bookingId == null ? '' : '?booking=' + bookingId);
    }

    public static String paymentUrl(Id bookingId) {
        return siteUrl() + '/my-bookings?pay=' + bookingId;
    }
}