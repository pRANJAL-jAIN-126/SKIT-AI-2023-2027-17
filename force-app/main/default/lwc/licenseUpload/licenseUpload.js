import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getCustomerProfile from '@salesforce/apex/PortalController.getCustomerProfile';
import uploadLicenseImage from '@salesforce/apex/PortalController.uploadLicenseImage';
import verifyLicense from '@salesforce/apex/PortalController.verifyLicense';
import basePath from '@salesforce/community/basePath';
import { buildUrl, formatDate, formatDateTime, getUrlParam, reduceError } from 'c/rentalUtils';
import { compressImage, CompressionError } from './imageCompressor';

const STATUS_VERIFIED = 'Verified';
const STATUS_PENDING = 'Pending Review';
const STATUS_REJECTED = 'Rejected';
const STATUS_ERROR = 'Error'; // OCR service outage – retryable, KYC status unchanged

const CONSENT_LABEL = 'I agree to my licence being read for verification.';

export default class LicenseUpload extends NavigationMixin(LightningElement) {
    consentLabel = CONSENT_LABEL;
    consentGiven = false;

    profile = null;
    profileLoading = true;
    profileError = null;

    isProcessing = false;
    errorMessage = null;
    result = null;
    bookingId = null;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        const booking = getUrlParam(pageRef, 'booking');
        this.bookingId = booking || null;
    }

    connectedCallback() {
        if (!this.bookingId) {
            this.bookingId = getUrlParam(null, 'booking');
        }
        this.loadProfile();
    }

    async loadProfile() {
        this.profileLoading = true;
        this.profileError = null;
        try {
            this.profile = await getCustomerProfile();
        } catch (error) {
            this.profileError = reduceError(error, 'We could not load your verification status.');
        } finally {
            this.profileLoading = false;
        }
    }

    // ---------- derived ----------

    get isGuest() {
        return !!this.profile && this.profile.isGuest === true;
    }

    get showForm() {
        return !this.profileLoading && !this.isGuest && !this.isResultVerified && !this.isResultPending;
    }

    get showCurrentStatus() {
        return !!this.profile && !this.isGuest;
    }

    get showConsentHint() {
        return !this.consentGiven && !this.isProcessing;
    }

    get currentStatus() {
        return (this.profile && this.profile.kycStatus) || 'Not Started';
    }

    get currentStatusClass() {
        const s = this.currentStatus;
        if (s === STATUS_VERIFIED) {
            return 'status-pill verified';
        }
        if (s === STATUS_PENDING) {
            return 'status-pill pending';
        }
        if (s === STATUS_REJECTED) {
            return 'status-pill rejected';
        }
        return 'status-pill neutral';
    }

    get alreadyVerified() {
        return !this.result && this.currentStatus === STATUS_VERIFIED;
    }

    get verifiedAtLabel() {
        return this.profile && this.profile.kycVerifiedAt ? formatDateTime(this.profile.kycVerifiedAt) : '';
    }

    get profileLicenseExpiry() {
        return this.profile && this.profile.licenseExpiry ? formatDate(this.profile.licenseExpiry) : '';
    }

    get uploadDisabled() {
        return !this.consentGiven || this.isProcessing;
    }

    get hasBooking() {
        return !!this.bookingId;
    }

    get isResultVerified() {
        return !!this.result && this.result.status === STATUS_VERIFIED;
    }

    get isResultPending() {
        return !!this.result && this.result.status === STATUS_PENDING;
    }

    get isResultRejected() {
        return !!this.result && this.result.status === STATUS_REJECTED;
    }

    get isResultError() {
        return !!this.result && this.result.status === STATUS_ERROR;
    }

    get canRetry() {
        return this.isResultRejected || this.isResultError;
    }

    get serviceErrorMessage() {
        return (
            (this.result && this.result.reason) ||
            'Our verification service is busy right now. Please try again in a moment.'
        );
    }

    get showExtracted() {
        if (this.isResultError) {
            return false;
        }
        const r = this.result;
        return !!r && !!(r.extractedName || r.dateOfBirth || r.maskedLicenseNumber || r.licenseExpiry);
    }

    get extracted() {
        const r = this.result || {};
        return {
            name: r.extractedName || '—',
            dob: r.dateOfBirth ? formatDate(r.dateOfBirth) : '—',
            licence: r.maskedLicenseNumber || '—',
            expiry: r.licenseExpiry ? formatDate(r.licenseExpiry) : '—'
        };
    }

    get rejectReason() {
        return (this.result && this.result.reason) || 'We could not verify this licence.';
    }

    get fleetUrl() {
        return buildUrl(basePath, '/fleet');
    }

    get loginUrl() {
        return buildUrl(basePath, '/login');
    }

    // ---------- handlers ----------

    handleConsentChange(event) {
        this.consentGiven = event.target.checked;
    }

    async handleFileChange(event) {
        const input = event.target;
        const file = input.files && input.files[0];
        if (!file) {
            return;
        }
        this.errorMessage = null;
        this.result = null;
        if (!this.consentGiven) {
            this.errorMessage = 'Please tick the consent box before uploading.';
            return;
        }
        this.isProcessing = true;
        try {
            let compressed;
            try {
                compressed = await compressImage(file);
            } catch (e) {
                this.errorMessage =
                    e instanceof CompressionError ? e.message : 'We could not process that photo. Please try another one.';
                return;
            }
            const contentVersionId = await uploadLicenseImage({
                fileName: compressed.fileName,
                base64Data: compressed.base64Data
            });
            this.result = await verifyLicense({
                contentVersionId,
                consentGiven: true,
                bookingId: this.bookingId || null
            });
            if (this.result && this.profile && this.result.status !== STATUS_ERROR) {
                this.profile = { ...this.profile, kycStatus: this.result.status };
            }
        } catch (error) {
            this.errorMessage = reduceError(error, 'We could not verify your licence right now. Please try again.');
        } finally {
            this.isProcessing = false;
            try {
                input.value = '';
            } catch {
                // ignore – some browsers disallow resetting file inputs
            }
        }
    }

    handleRetry() {
        this.result = null;
        this.errorMessage = null;
    }

    handleContinueToPayment() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: buildUrl(basePath, '/my-bookings', { pay: this.bookingId }) }
        });
    }
}