import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getMyBookings from '@salesforce/apex/PortalController.getMyBookings';
import getCancellationQuote from '@salesforce/apex/PortalController.getCancellationQuote';
import cancelBooking from '@salesforce/apex/PortalController.cancelBooking';
import startCheckout from '@salesforce/apex/PortalController.startCheckout';
import basePath from '@salesforce/community/basePath';
import { buildUrl, formatDateTime, formatMoney, getUrlParam, redirectTo, reduceError } from 'c/rentalUtils';

const BADGE_CLASS = {
    Confirmed: 'badge badge-confirmed',
    'Pending Payment': 'badge badge-pending',
    Completed: 'badge badge-completed',
    Cancelled: 'badge badge-cancelled',
    Active: 'badge badge-active',
    Expired: 'badge badge-expired'
};

export default class MyBookings extends LightningElement {
    bookings = [];
    isLoading = true;
    errorMessage = null;
    successMessage = null;

    payBookingId = null;
    payingId = null;
    payError = null;

    // cancellation panel
    cancelTarget = null;
    quote = null;
    quoteLoading = false;
    quoteError = null;
    cancelling = false;

    _scrolled = false;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        const pay = getUrlParam(pageRef, 'pay');
        if (pay && pay !== this.payBookingId) {
            this.payBookingId = pay;
            this._scrolled = false;
        }
    }

    connectedCallback() {
        if (!this.payBookingId) {
            this.payBookingId = getUrlParam(null, 'pay');
        }
        this.loadBookings();
    }

    renderedCallback() {
        if (this._scrolled || !this.payBookingId || this.isLoading) {
            return;
        }
        const el = this.template.querySelector(`[data-booking-id="${this.payBookingId}"]`);
        if (el) {
            this._scrolled = true;
            if (typeof el.scrollIntoView === 'function') {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            if (typeof el.focus === 'function') {
                el.focus();
            }
        }
    }

    async loadBookings() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const result = await getMyBookings();
            this.bookings = Array.isArray(result) ? result : [];
        } catch (error) {
            this.bookings = [];
            this.errorMessage = reduceError(error, 'We could not load your bookings. Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    // ---------- derived ----------

    get viewBookings() {
        return this.bookings.map((b) => {
            const highlighted = !!this.payBookingId && b.id === this.payBookingId;
            return {
                ...b,
                badgeClass: BADGE_CLASS[b.status] || 'badge badge-expired',
                cardClass: highlighted ? 'booking-card highlighted' : 'booking-card',
                isHighlighted: highlighted,
                startLabel: formatDateTime(b.startDt),
                endLabel: formatDateTime(b.endDt),
                amountLabel: formatMoney(b.grandTotal !== undefined && b.grandTotal !== null ? b.grandTotal : b.totalAmount),
                hasLateFee: !!b.lateFee && Number(b.lateFee) > 0,
                lateFeeLabel: formatMoney(b.lateFee),
                hasRefund: !!b.refundAmount && Number(b.refundAmount) > 0,
                refundLabel: formatMoney(b.refundAmount),
                holdLabel: b.status === 'Pending Payment' && b.holdExpiresAt ? formatDateTime(b.holdExpiresAt) : '',
                daysLabel: b.rentalDays ? `${b.rentalDays} ${Number(b.rentalDays) === 1 ? 'day' : 'days'}` : '',
                isPaying: this.payingId === b.id,
                payLabel: `Pay now for booking ${b.bookingNumber || ''}`.trim(),
                cancelLabel: `Cancel booking ${b.bookingNumber || ''}`.trim()
            };
        });
    }

    get hasBookings() {
        return !this.isLoading && !this.errorMessage && this.bookings.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.errorMessage && this.bookings.length === 0;
    }

    get fleetUrl() {
        return buildUrl(basePath, '/fleet');
    }

    get showCancelPanel() {
        return !!this.cancelTarget;
    }

    get quoteView() {
        const q = this.quote || {};
        return {
            refund: formatMoney(q.refundAmount),
            retained: formatMoney(q.retainedAmount),
            fullRefund: q.fullRefund === true,
            hasRetained: !!q.retainedAmount && Number(q.retainedAmount) > 0,
            message: q.message || ''
        };
    }

    get confirmCancelDisabled() {
        return this.quoteLoading || this.cancelling || !!this.quoteError || !this.quote;
    }

    // ---------- pay ----------

    async handlePay(event) {
        const bookingId = event.currentTarget.dataset.id;
        this.payError = null;
        this.successMessage = null;
        this.payingId = bookingId;
        try {
            const res = await startCheckout({ bookingId });
            if (res && res.url) {
                redirectTo(res.url);
            } else {
                this.payError = 'We could not start the payment. Please try again.';
                this.payingId = null;
            }
        } catch (error) {
            this.payError = reduceError(error, 'We could not start the payment. Please try again.');
            this.payingId = null;
        }
    }

    // ---------- cancel ----------

    async handleCancelClick(event) {
        const bookingId = event.currentTarget.dataset.id;
        this.cancelTarget = this.bookings.find((b) => b.id === bookingId) || { id: bookingId };
        this.quote = null;
        this.quoteError = null;
        this.successMessage = null;
        this.quoteLoading = true;
        try {
            this.quote = await getCancellationQuote({ bookingId });
        } catch (error) {
            this.quoteError = reduceError(error, 'We could not work out the refund. Please try again.');
        } finally {
            this.quoteLoading = false;
        }
    }

    handleCloseCancel() {
        if (this.cancelling) {
            return;
        }
        this.cancelTarget = null;
        this.quote = null;
        this.quoteError = null;
    }

    handlePanelKeydown(event) {
        if (event.key === 'Escape') {
            this.handleCloseCancel();
        }
    }

    async handleConfirmCancel() {
        if (!this.cancelTarget) {
            return;
        }
        this.cancelling = true;
        this.quoteError = null;
        try {
            const res = await cancelBooking({ bookingId: this.cancelTarget.id });
            const number = (res && res.bookingNumber) || this.cancelTarget.bookingNumber || '';
            this.successMessage =
                (res && res.message) || `Booking ${number} has been cancelled.`;
            this.cancelTarget = null;
            this.quote = null;
            await this.loadBookings();
        } catch (error) {
            this.quoteError = reduceError(error, 'We could not cancel this booking. Please try again.');
        } finally {
            this.cancelling = false;
        }
    }
}