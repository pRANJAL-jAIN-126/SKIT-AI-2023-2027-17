/**
 * Zero-touch KYC (TDD 7.2): licence image -> OCR (OcrProvider) -> LicenseParser -> rules R1-R6 ->
 * Contact KYC fields + KYC_Log__c -> result. Every attempt is logged with licence numbers masked.
 *
 * Rule outcomes: any R1/R3/R4 failure -> Rejected; otherwise any R2/R5/R6 failure -> Pending Review (flow
 * KYC_Pending_Task creates the review Task); otherwise Verified. Thresholds come from Rental_Config__mdt.
 */
public with sharing class KycService {
    public static final String VERIFIED = 'Verified';
    public static final String PENDING_REVIEW = 'Pending Review';
    public static final String REJECTED = 'Rejected';
    public static final String ERROR = 'Error';
    public static final Set<String> ALLOWED_EXTENSIONS = new Set<String>{ 'jpg', 'jpeg', 'png' };

    @TestVisible
    private static OcrProvider providerOverride;

    public class Evaluation {
        public String status = VERIFIED;
        public List<String> reasons = new List<String>();
    }

    // ------------------------------------------------------------------ upload

    /**
     * Stores the (already client-side compressed) licence image as a Salesforce File linked to the Contact.
     * Enforces the size cap (TDD 7.2 image size rule: synchronous heap is 6 MB, base64 adds ~33 %).
     */
    public static Id saveLicenseImage(Id contactId, String fileName, String base64Data) {
        String ext = extensionOf(fileName);
        if (!ALLOWED_EXTENSIONS.contains(ext)) {
            throw new KycException('Please upload a JPG or PNG photo of your licence.');
        }
        if (String.isBlank(base64Data)) {
            throw new KycException('The selected file is empty.');
        }
        Integer maxBytes = (RentalConfig.get().Max_Image_MB__c * 1024 * 1024).intValue();
        // base64 length * 3/4 ~ decoded size; reject before decoding to protect the heap
        if (base64Data.length() * 3 / 4 > maxBytes) {
            throw new KycException('Please upload an image smaller than ' + RentalConfig.get().Max_Image_MB__c.intValue() + ' MB.');
        }
        Blob data;
        try {
            data = EncodingUtil.base64Decode(base64Data);
        } catch (Exception e) {
            throw new KycException('The selected file could not be read.');
        }
        ContentVersion cv = new ContentVersion(
            Title = 'Driving licence',
            PathOnClient = 'driving-licence.' + ext,
            VersionData = data,
            FirstPublishLocationId = contactId
        );
        new Writer().insertVersion(cv);
        return cv.Id;
    }

    // ------------------------------------------------------------------ verify

    /**
     * @param bookingId optional – when given, R3 checks the licence is valid through that trip's end date.
     * Never throws for provider failures: they are logged (KYC_Log__c Status Error) and returned as status
     * 'Error' with a retry message, leaving the Contact's KYC status unchanged (TDD 10.4, NFR-04).
     */
    public static RentalDtos.KycResultDTO verifyLicense(Id contactId, Id contentVersionId, Id bookingId) {
        Writer db = new Writer();
        Contact c = db.getContact(contactId);
        if (c == null) {
            throw new KycException('A customer account is required for this action.');
        }
        ContentVersion cv = db.getVersion(contentVersionId);
        if (cv == null || (cv.FirstPublishLocationId != contactId && cv.OwnerId != UserInfo.getUserId())) {
            throw new KycException('We could not find the uploaded file. Please upload it again.');
        }
        String ext = (cv.FileExtension ?? '').toLowerCase();
        if (!ALLOWED_EXTENSIONS.contains(ext)) {
            throw new KycException('Please upload a JPG or PNG photo of your licence.');
        }
        if (cv.ContentSize > RentalConfig.get().Max_Image_MB__c * 1024 * 1024) {
            throw new KycException('Please upload an image smaller than ' + RentalConfig.get().Max_Image_MB__c.intValue() + ' MB.');
        }
        Date tripEnd = resolveTripEnd(contactId, bookingId);
        String mime = ext == 'png' ? 'image/png' : 'image/jpeg';

        OcrResult ocr;
        try {
            ocr = provider().extract(cv.VersionData, mime); // callout – no DML has happened yet (D4)
        } catch (KycException e) {
            db.insertLog(new KYC_Log__c(Contact__c = contactId, Status__c = ERROR, Reason__c = e.getMessage().left(255)));
            return errorResult(e.getMessage());
        }

        LicenseParser.ParsedLicense p = LicenseParser.parse(ocr);
        Evaluation ev = evaluate(p, c, tripEnd, Date.today());
        Decimal confidencePct = p.confidence == null ? null : (p.confidence * 100).setScale(0, System.RoundingMode.HALF_UP);

        Contact upd = new Contact(Id = contactId, KYC_Status__c = ev.status, License_File_Id__c = cv.ContentDocumentId);
        upd.KYC_Confidence__c = confidencePct;
        upd.KYC_Verified_At__c = ev.status == VERIFIED ? System.now() : null;
        // never overwrite good data with blanks from an unreadable photo
        if (p.name != null) {
            upd.License_Name_OCR__c = p.name.left(120);
        }
        if (p.licenseNo != null) {
            upd.Driving_License_Number__c = p.licenseNo.left(25);
        }
        if (p.expiry != null) {
            upd.License_Expiry__c = p.expiry;
        }
        if (p.dob != null) {
            upd.Birthdate = p.dob;
        }
        String reason = ev.reasons.isEmpty() ? 'All checks passed.' : String.join(ev.reasons, ' ');
        db.updateContact(upd);
        db.insertLog(
            new KYC_Log__c(
                Contact__c = contactId,
                Status__c = ev.status,
                Confidence__c = confidencePct,
                Extracted_Name__c = p.name == null ? null : p.name.left(120),
                Reason__c = reason.left(255),
                Raw_Response__c = DataMasking.maskLicenseNumbersIn(ocr.rawResponse ?? ocr.text)?.left(32000)
            )
        );

        RentalDtos.KycResultDTO dto = new RentalDtos.KycResultDTO();
        dto.status = ev.status;
        dto.reason = ev.status == VERIFIED ? 'Your licence has been verified.' : reason;
        dto.extractedName = p.name;
        dto.dateOfBirth = p.dob;
        dto.maskedLicenseNumber = DataMasking.maskLicense(p.licenseNo);
        dto.licenseExpiry = p.expiry;
        dto.confidence = confidencePct;
        return dto;
    }

    /** Rules R1-R6 (TDD 7.2). Pure function – unit-tested directly. */
    public static Evaluation evaluate(LicenseParser.ParsedLicense p, Contact c, Date tripEnd, Date today) {
        Rental_Config__mdt cfg = RentalConfig.get();
        Evaluation ev = new Evaluation();
        Boolean isRejected = false, needsReview = false;

        // R1 required fields
        if (String.isBlank(p.name) || String.isBlank(p.licenseNo) || p.dob == null || p.expiry == null) {
            ev.status = REJECTED;
            ev.reasons.add('Could not read licence, please upload a clearer photo.');
            return ev;
        }
        // R3 not expired for the whole trip
        Date mustBeValidAfter = tripEnd ?? today;
        if (p.expiry <= mustBeValidAfter) {
            isRejected = true;
            ev.reasons.add('Licence expired / expires before trip ends.');
        }
        // R4 minimum age
        Integer minAge = cfg.Min_Age__c.intValue();
        if (ageOn(p.dob, today) < minAge) {
            isRejected = true;
            ev.reasons.add('You must be at least ' + minAge + ' years old to rent a car.');
        }
        // R2 licence number format
        if (!LicenseParser.isValidFormat(p.licenseNo)) {
            needsReview = true;
            ev.reasons.add('Licence number format needs a manual check.');
        }
        // R5 name match
        String profileName = ((c.FirstName ?? '') + ' ' + (c.LastName ?? '')).trim();
        if (NameMatcher.similarity(p.name, profileName) < cfg.Name_Match_Threshold__c) {
            needsReview = true;
            ev.reasons.add('Name on the licence does not match your profile name.');
        }
        // R6 OCR confidence (only if the provider returns it)
        if (p.confidence != null && p.confidence < cfg.Min_OCR_Confidence__c) {
            needsReview = true;
            ev.reasons.add('The photo is not clear enough for automatic verification.');
        }
        ev.status = isRejected ? REJECTED : needsReview ? PENDING_REVIEW : VERIFIED;
        return ev;
    }

    public static Integer ageOn(Date dob, Date onDate) {
        Integer age = onDate.year() - dob.year();
        if (onDate < dob.addYears(age)) {
            age--;
        }
        return age;
    }

    /** End date of the given (owned) booking, else the latest upcoming hold/confirmed booking, else null (today). */
    @TestVisible
    private static Date resolveTripEnd(Id contactId, Id bookingId) {
        if (bookingId != null) {
            Booking__c b = BookingRepository.getOwned(contactId, bookingId);
            if (b != null) {
                return b.End_DateTime__c.date();
            }
        }
        Datetime nowDt = System.now();
        List<AggregateResult> rows = [
            SELECT MAX(End_DateTime__c) maxEnd
            FROM Booking__c
            WHERE Customer__c = :contactId AND Status__c IN ('Pending Payment', 'Confirmed') AND End_DateTime__c > :nowDt
            WITH SYSTEM_MODE
        ];
        Object maxEnd = rows.isEmpty() ? null : rows[0].get('maxEnd');
        return maxEnd == null ? null : ((Datetime) maxEnd).date();
    }

    public static RentalDtos.CustomerProfileDTO profile(Id contactId) {
        RentalDtos.CustomerProfileDTO dto = new RentalDtos.CustomerProfileDTO();
        Contact c = BookingRepository.getCustomer(contactId);
        if (c == null) {
            return dto;
        }
        dto.contactId = c.Id;
        dto.name = c.Name;
        dto.kycStatus = c.KYC_Status__c;
        dto.maskedLicenseNumber = c.License_Number_Masked__c;
        dto.licenseExpiry = c.License_Expiry__c;
        dto.kycVerifiedAt = c.KYC_Verified_At__c;
        return dto;
    }

    private static OcrProvider provider() {
        if (providerOverride != null) {
            return providerOverride;
        }
        String className = RentalConfig.get().OCR_Provider_Class__c;
        Type t = Type.forName(className);
        Object instance = t == null ? null : t.newInstance();
        if (!(instance instanceof OcrProvider)) {
            throw new KycException('Verification service is not configured. Please contact support.');
        }
        return (OcrProvider) instance;
    }

    private static RentalDtos.KycResultDTO errorResult(String message) {
        RentalDtos.KycResultDTO dto = new RentalDtos.KycResultDTO();
        dto.status = ERROR;
        dto.reason = message;
        return dto;
    }

    private static String extensionOf(String fileName) {
        return String.isBlank(fileName) || !fileName.contains('.') ? '' : fileName.substringAfterLast('.').toLowerCase();
    }

    /**
     * WITHOUT sharing on purpose (documented exception, TDD 11.1 "Read/Edit own Contact KYC fields via Apex only"):
     * customers have no edit access to Contact KYC fields or KYC_Log__c. Every method is called only with the
     * Contact Id resolved from the authenticated session (CustomerContext).
     */
    private without sharing class Writer {
        Contact getContact(Id contactId) {
            List<Contact> rows = [SELECT Id, FirstName, LastName, KYC_Status__c FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        ContentVersion getVersion(Id versionId) {
            List<ContentVersion> rows = [
                SELECT Id, ContentDocumentId, FileExtension, ContentSize, VersionData, FirstPublishLocationId, OwnerId
                FROM ContentVersion
                WHERE Id = :versionId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        void insertVersion(ContentVersion cv) {
            insert as system cv;
        }

        void updateContact(Contact c) {
            update as system c;
        }

        void insertLog(KYC_Log__c log) {
            insert as system log;
        }
    }
}