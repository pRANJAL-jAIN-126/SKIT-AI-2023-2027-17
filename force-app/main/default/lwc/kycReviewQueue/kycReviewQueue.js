import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPendingReviews from '@salesforce/apex/KycReviewController.getPendingReviews';
import approve from '@salesforce/apex/KycReviewController.approve';
import reject from '@salesforce/apex/KycReviewController.reject';
import { formatDate, formatDateTime, reduceError } from 'c/rentalUtils';

/**
 * Staff screen ("KYC Review" tab): every customer whose driving licence is Pending Review, with the uploaded photo.
 * Approve needs the expiry date read from the photo; Reject needs a reason the customer can act on.
 */
export default class KycReviewQueue extends LightningElement {
    rows = [];
    isLoading = true;
    loadError = null;
    busyId = null;
    // per-customer form values: { [contactId]: { expiry, dob, licence, reason, error } }
    forms = {};

    connectedCallback() {
        this.load();
    }

    async load() {
        this.isLoading = true;
        this.loadError = null;
        try {
            const result = await getPendingReviews();
            this.rows = Array.isArray(result) ? result : [];
            const forms = {};
            this.rows.forEach((r) => {
                forms[r.contactId] = {
                    expiry: r.licenseExpiry || null,
                    dob: r.dateOfBirth || null,
                    licence: r.licenseNumber || '',
                    reason: '',
                    error: null
                };
            });
            this.forms = forms;
        } catch (error) {
            this.rows = [];
            this.loadError = reduceError(error, 'Could not load the licences waiting for review.');
        } finally {
            this.isLoading = false;
        }
    }

    get hasRows() {
        return !this.isLoading && !this.loadError && this.rows.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.loadError && this.rows.length === 0;
    }

    get countLabel() {
        const n = this.rows.length;
        return `${n} licence${n === 1 ? '' : 's'} waiting for review`;
    }

    get viewRows() {
        return this.rows.map((r) => {
            const f = this.forms[r.contactId] || {};
            return {
                ...r,
                submittedLabel: formatDateTime(r.submittedAt),
                validUntilLabel: r.mustBeValidUntil ? formatDate(r.mustBeValidUntil) : '',
                hasPhoto: !!r.photoUrl,
                photoAlt: `Driving licence uploaded by ${r.name}`,
                expiry: f.expiry,
                dob: f.dob,
                licence: f.licence,
                reasonText: f.reason,
                formError: f.error,
                isBusy: this.busyId === r.contactId,
                recordUrl: `/lightning/r/Contact/${r.contactId}/view`
            };
        });
    }

    handleField(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.forms = { ...this.forms, [id]: { ...this.forms[id], [field]: value, error: null } };
    }

    async handleApprove(event) {
        const id = event.target.dataset.id;
        const f = this.forms[id] || {};
        if (!f.expiry) {
            this.setError(id, 'Enter the licence expiry date shown on the photo before approving.');
            return;
        }
        await this.decide(id, () =>
            approve({ contactId: id, licenseExpiry: f.expiry, dateOfBirth: f.dob || null, licenseNumber: f.licence || null }),
            'Licence approved — the customer can now pay for their booking.'
        );
    }

    async handleReject(event) {
        const id = event.target.dataset.id;
        const f = this.forms[id] || {};
        if (!f.reason || !f.reason.trim()) {
            this.setError(id, 'Enter a reason so the customer knows what to fix.');
            return;
        }
        await this.decide(id, () => reject({ contactId: id, reason: f.reason }), 'Licence rejected — the customer can upload a new photo.');
    }

    async decide(id, call, successMessage) {
        this.busyId = id;
        try {
            await call();
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: successMessage, variant: 'success' }));
            await this.load();
        } catch (error) {
            this.setError(id, reduceError(error, 'Could not save the decision. Please try again.'));
        } finally {
            this.busyId = null;
        }
    }

    setError(id, message) {
        this.forms = { ...this.forms, [id]: { ...this.forms[id], error: message } };
    }
}
