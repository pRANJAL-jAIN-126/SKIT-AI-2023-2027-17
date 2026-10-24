import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import confirmPayment from '@salesforce/apex/PortalController.confirmPayment';
import basePath from '@salesforce/community/basePath';
import {
    buildUrl,
    cancelScheduled,
    formatDateTime,
    formatMoney,
    getUrlParam,
    reduceError,
    schedule
} from 'c/rentalUtils';

const MAX_ATTEMPTS = 5;
const POLL_INTERVAL_MS = 2000;

/** UI states */
const STATE_CHECKING = 'checking';
const STATE_SUCCESS = 'success';
const STATE_FAILED = 'failed';
const STATE_PROCESSING = 'processing';
const STATE_ERROR = 'error';

export default class CheckoutStatus extends LightningElement {
    sessionId = null;
    state = STATE_CHECKING;
    result = null;
    errorMessage = null;
    attempts = 0;

    _timer = null;
    _started = false;
    _connected = false;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        const sid = getUrlParam(pageRef, 'session_id');
        if (sid && sid !== this.sessionId) {
            this.sessionId = sid;
            if (this._connected) {
                this.startPolling();
            }
        }
    }

    connectedCallback() {
        this._connected = true;
        if (!this.sessionId) {
            this.sessionId = getUrlParam(null, 'session_id');
        }
        if (this.sessionId) {
            this.startPolling();
        } else {
            // Give the page reference wire a moment to deliver state before declaring an error.
            this._timer = schedule(() => {
                if (!this.sessionId) {
                    this.state = STATE_ERROR;
                    this.errorMessage = 'We could not find your payment reference. Please check My Bookings.';
                }
            }, 1000);
        }
    }

    disconnectedCallback() {
        this._connected = false;
        cancelScheduled(this._timer);
        this._timer = null;
    }

    // ---------- derived ----------

    get isChecking() {
        return this.state === STATE_CHECKING;
    }
    get isSuccess() {
        return this.state === STATE_SUCCESS;
    }
    get isFailed() {
        return this.state === STATE_FAILED;
    }
    get isProcessing() {
        return this.state === STATE_PROCESSING;
    }
    get isError() {
        return this.state === STATE_ERROR;
    }

    get booking() {
        return (this.result && this.result.booking) || null;
    }

    get summary() {
        const b = this.booking || {};
        return {
            bookingNumber: b.bookingNumber || '',
            vehicleName: b.vehicleName || '',
            branchName: b.branchName || '',
            start: formatDateTime(b.startDt),
            end: formatDateTime(b.endDt),
            amount: formatMoney(b.grandTotal !== undefined && b.grandTotal !== null ? b.grandTotal : b.totalAmount),
            status: b.status || ''
        };
    }

    get resultMessage() {
        return (this.result && this.result.message) || '';
    }

    get myBookingsUrl() {
        return buildUrl(basePath, '/my-bookings');
    }

    get retryPayUrl() {
        const b = this.booking;
        return buildUrl(basePath, '/my-bookings', { pay: b && b.id });
    }

    // ---------- polling ----------

    startPolling() {
        if (this._started && this.state === STATE_CHECKING) {
            return;
        }
        this._started = true;
        cancelScheduled(this._timer);
        this.attempts = 0;
        this.errorMessage = null;
        this.state = STATE_CHECKING;
        this.poll();
    }

    async poll() {
        this._timer = null;
        this.attempts += 1;
        try {
            const res = await confirmPayment({ sessionId: this.sessionId });
            if (!this._connected) {
                return;
            }
            this.result = res;
            const status = res && res.status;
            if (status === 'Succeeded') {
                this.state = STATE_SUCCESS;
            } else if (status === 'Failed') {
                this.state = STATE_FAILED;
            } else if (this.attempts < MAX_ATTEMPTS) {
                this._timer = schedule(() => this.poll(), POLL_INTERVAL_MS);
            } else {
                this.state = STATE_PROCESSING;
            }
        } catch (error) {
            if (!this._connected) {
                return;
            }
            this.state = STATE_ERROR;
            this.errorMessage = reduceError(error, 'We could not check your payment. Please try again.');
        }
    }

    handleCheckAgain() {
        this._started = false;
        this.startPolling();
    }
}