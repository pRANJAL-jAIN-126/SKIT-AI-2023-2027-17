import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getVehicleDetail from '@salesforce/apex/PortalController.getVehicleDetail';
import getCustomerProfile from '@salesforce/apex/PortalController.getCustomerProfile';
import createHold from '@salesforce/apex/PortalController.createHold';
import startCheckout from '@salesforce/apex/PortalController.startCheckout';
import basePath from '@salesforce/community/basePath';
import {
    buildUrl,
    createDebouncer,
    formatDateTime,
    formatMoney,
    getUrlParam,
    redirectTo,
    reduceError,
    toIso,
    validateDateRange
} from 'c/rentalUtils';

const SF_ID = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

export default class BookingForm extends NavigationMixin(LightningElement) {
    /** Vehicle record id when placed on a Vehicle__c record page. */
    @api recordId;
    /** Vehicle id when placed on the /vehicle/:id route (or set by a parent). */
    @api vehicleId;

    startDt = null;
    endDt = null;

    vehicle = null;
    profile = null;
    hold = null;

    isLoading = false;
    isQuoting = false;
    isBooking = false;
    loadError = null;
    bookingError = null;
    infoMessage = null;
    showLoginPrompt = false;

    _pageRef;
    _routeVehicleId;
    _quoteDebouncer = createDebouncer(400);
    _initialised = false;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        this._pageRef = pageRef;
        if (!pageRef) {
            return;
        }
        const start = toIso(getUrlParam(pageRef, 'start'));
        const end = toIso(getUrlParam(pageRef, 'end'));
        if (start && !this.startDt) {
            this.startDt = start;
        }
        if (end && !this.endDt) {
            this.endDt = end;
        }
        const attrs = pageRef.attributes || {};
        const candidate = attrs.recordId || getUrlParam(pageRef, 'vehicleId');
        if (candidate && SF_ID.test(candidate)) {
            this._routeVehicleId = candidate;
        }
        if (this._initialised) {
            this.loadVehicle();
        }
    }

    connectedCallback() {
        this._initialised = true;
        this.loadAll();
    }

    disconnectedCallback() {
        this._quoteDebouncer.cancel();
    }

    // ---------- derived ----------

    get effectiveVehicleId() {
        return this.vehicleId || this.recordId || this._routeVehicleId || this.vehicleIdFromPath();
    }

    vehicleIdFromPath() {
        try {
            const match = /\/vehicle\/([a-zA-Z0-9]{15,18})(?:[/?#]|$)/.exec(window.location.pathname || '');
            return match ? match[1] : null;
        } catch {
            return null;
        }
    }

    get dateError() {
        if (!this.startDt && !this.endDt) {
            return 'Choose your pickup and return times to see the price.';
        }
        return validateDateRange(this.startDt, this.endDt);
    }

    get datesValid() {
        return !validateDateRange(this.startDt, this.endDt);
    }

    get hasVehicle() {
        return !!this.vehicle;
    }

    get vehicleTitle() {
        const v = this.vehicle || {};
        return [v.make, v.model].filter(Boolean).join(' ') || v.name || 'Vehicle';
    }

    get vehicleMeta() {
        const v = this.vehicle || {};
        return [v.year, v.category, v.seats ? `${v.seats} seats` : null, v.fuelType, v.transmission]
            .filter(Boolean)
            .join(' · ');
    }

    get branchLabel() {
        const v = this.vehicle || {};
        return [v.branchName, v.city].filter(Boolean).join(', ');
    }

    get hasQuote() {
        const v = this.vehicle;
        return !!v && this.datesValid && v.days !== null && v.days !== undefined && v.grandTotal !== undefined && v.grandTotal !== null;
    }

    get breakdown() {
        const v = this.vehicle || {};
        const days = Number(v.days) || 0;
        return {
            rateLine: `${formatMoney(v.dailyRate)} × ${days} ${days === 1 ? 'day' : 'days'}`,
            subtotal: formatMoney(v.subtotal),
            tax: formatMoney(v.tax),
            total: formatMoney(v.total),
            deposit: formatMoney(v.deposit !== undefined && v.deposit !== null ? v.deposit : v.securityDeposit),
            grandTotal: formatMoney(v.grandTotal)
        };
    }

    get dailyRateLabel() {
        return formatMoney(this.vehicle && this.vehicle.dailyRate);
    }

    get isGuest() {
        return !!this.profile && this.profile.isGuest === true;
    }

    get kycVerified() {
        return !!this.profile && this.profile.kycStatus === 'Verified';
    }

    get showKycNotice() {
        return !!this.profile && !this.isGuest && !this.kycVerified;
    }

    get kycStatusLabel() {
        return (this.profile && this.profile.kycStatus) || 'Not Started';
    }

    get bookDisabled() {
        return !this.hasQuote || this.isBooking || this.isQuoting;
    }

    get bookLabel() {
        if (this.isGuest) {
            return 'Log in to book';
        }
        return this.kycVerified ? 'Book and pay' : 'Book and verify licence';
    }

    get loginUrl() {
        let startUrl = '';
        try {
            startUrl = `${window.location.pathname}${window.location.search}`;
        } catch {
            startUrl = '';
        }
        return buildUrl(basePath, '/login', { startURL: startUrl || null });
    }

    get holdExpiryLabel() {
        return this.hold && this.hold.holdExpiresAt ? formatDateTime(this.hold.holdExpiresAt) : '';
    }

    // ---------- data ----------

    async loadAll() {
        this.isLoading = true;
        this.loadError = null;
        try {
            await Promise.all([this.loadProfile(), this.loadVehicle(true)]);
        } finally {
            this.isLoading = false;
        }
    }

    async loadProfile() {
        try {
            this.profile = await getCustomerProfile();
        } catch {
            // Profile is only needed to decide the booking path; treat failure as guest-unknown.
            this.profile = null;
        }
    }

    async loadVehicle(initial = false) {
        const vehicleId = this.effectiveVehicleId;
        if (!vehicleId) {
            if (initial) {
                this.loadError = 'We could not tell which car you picked. Please go back to the fleet and choose again.';
            }
            return;
        }
        this.isQuoting = !initial;
        try {
            const params = { vehicleId, startDt: null, endDt: null };
            if (this.datesValid) {
                params.startDt = toIso(this.startDt);
                params.endDt = toIso(this.endDt);
            }
            this.vehicle = await getVehicleDetail(params);
            this.loadError = null;
        } catch (error) {
            this.loadError = reduceError(error, 'We could not load this car. Please try again.');
        } finally {
            this.isQuoting = false;
        }
    }

    // ---------- handlers ----------

    handleDateChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value || null;
        this.bookingError = null;
        this.hold = null;
        if (this.datesValid) {
            this._quoteDebouncer.run(() => this.loadVehicle());
        } else {
            this._quoteDebouncer.cancel();
        }
    }

    async handleBook() {
        this.bookingError = null;
        this.infoMessage = null;
        if (!this.profile) {
            await this.loadProfile();
        }
        if (!this.profile || this.isGuest) {
            this.showLoginPrompt = true;
            return;
        }
        if (!this.datesValid) {
            this.bookingError = validateDateRange(this.startDt, this.endDt);
            return;
        }
        this.isBooking = true;
        try {
            if (!this.hold) {
                this.hold = await createHold({
                    vehicleId: this.effectiveVehicleId,
                    startDt: toIso(this.startDt),
                    endDt: toIso(this.endDt)
                });
            }
            if (!this.kycVerified) {
                this.infoMessage =
                    'Your car is on hold. Before paying we need to verify your driving licence — taking you there now.';
                this.navigateToUrl(buildUrl(basePath, '/verify', { booking: this.hold.id }));
                return;
            }
            const checkout = await startCheckout({ bookingId: this.hold.id });
            if (checkout && checkout.url) {
                this.infoMessage = 'Redirecting you to secure payment…';
                redirectTo(checkout.url);
            } else {
                this.bookingError = 'We could not start the payment. Please try again from My Bookings.';
            }
        } catch (error) {
            this.bookingError = reduceError(error, 'We could not complete your booking. Please try again.');
        } finally {
            this.isBooking = false;
        }
    }

    handleCloseLoginPrompt() {
        this.showLoginPrompt = false;
    }

    navigateToUrl(url) {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url }
        });
    }
}