/**
 * OCR provider abstraction (TDD D6, 9.5). Swap the implementation through
 * Rental_Config__mdt.OCR_Provider_Class__c without touching KYC business logic.
 */
public interface OcrProvider {
    /** @throws KycException with a customer-safe message when the provider fails. */
    OcrResult extract(Blob image, String mimeType);
}