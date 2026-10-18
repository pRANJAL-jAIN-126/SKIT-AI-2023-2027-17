import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import searchVehicles from '@salesforce/apex/PortalController.searchVehicles';
import basePath from '@salesforce/community/basePath';
import {
    buildUrl,
    createDebouncer,
    getUrlParam,
    reduceError,
    toIso,
    toNumberOrNull,
    validateDateRange
} from 'c/rentalUtils';

const DEBOUNCE_MS = 400;
const ANY = '';

const withAny = (values) => [{ label: 'Any', value: ANY }, ...values.map((v) => ({ label: v, value: v }))];

export default class CarFleetSearch extends NavigationMixin(LightningElement) {
    /** City pre-selected when the URL does not provide one (configurable in Experience Builder). */
    @api defaultCity;

    pickupDateTime = null;
    returnDateTime = null;
    branchCity = ANY;
    category = ANY;
    seats = null;
    transmission = ANY;
    fuelType = ANY;
    maxDailyRate = null;

    vehicles = [];
    isLoading = false;
    errorMessage = null;
    hasSearched = false;

    cityOptions = withAny(['Jaipur', 'Delhi']);
    categoryOptions = withAny(['Hatchback', 'Sedan', 'SUV', 'MUV', 'Luxury', 'Electric']);
    transmissionOptions = withAny(['Manual', 'Automatic']);
    fuelOptions = withAny(['Petrol', 'Diesel', 'CNG', 'Electric']);

    _debouncer = createDebouncer(DEBOUNCE_MS);
    _requestSeq = 0;
    _stateApplied = false;
    _dirty = false;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        if (this._stateApplied || !pageRef) {
            return;
        }
        this._stateApplied = true;
        const start = toIso(getUrlParam(pageRef, 'start'));
        const end = toIso(getUrlParam(pageRef, 'end'));
        const city = getUrlParam(pageRef, 'city');
        if (start) {
            this.pickupDateTime = start;
        }
        if (end) {
            this.returnDateTime = end;
        }
        if (city) {
            this.branchCity = city;
        }
        if (start || end || city) {
            this._dirty = true;
            this.scheduleSearch();
        }
    }

    connectedCallback() {
        if (!this.branchCity && this.defaultCity) {
            this.branchCity = this.defaultCity;
        }
    }

    disconnectedCallback() {
        this._debouncer.cancel();
    }

    // ---------- derived state ----------

    get dateError() {
        if (!this.pickupDateTime && !this.returnDateTime) {
            return null;
        }
        return validateDateRange(this.pickupDateTime, this.returnDateTime);
    }

    get datesValid() {
        return !!this.pickupDateTime && !!this.returnDateTime && !this.dateError;
    }

    get showDatePrompt() {
        return !this.pickupDateTime && !this.returnDateTime;
    }

    get searchDisabled() {
        return !this.datesValid || this.isLoading;
    }

    get hasResults() {
        return !this.isLoading && !this.errorMessage && this.vehicles.length > 0;
    }

    get showEmpty() {
        return this.hasSearched && !this.isLoading && !this.errorMessage && this.vehicles.length === 0;
    }

    get resultCountLabel() {
        const n = this.vehicles.length;
        return n === 1 ? '1 car available' : `${n} cars available`;
    }

    // ---------- handlers ----------

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this[field] = value === undefined ? null : value;
        this._dirty = true;
        this.scheduleSearch();
    }

    handleSearchClick() {
        this._debouncer.cancel();
        this.runSearch();
    }

    handleReset() {
        this.category = ANY;
        this.seats = null;
        this.transmission = ANY;
        this.fuelType = ANY;
        this.maxDailyRate = null;
        this.scheduleSearch();
    }

    handleVehicleSelect(event) {
        const vehicleId = event.detail && event.detail.vehicleId;
        if (!vehicleId) {
            return;
        }
        const url = buildUrl(basePath, `/vehicle/${vehicleId}`, {
            start: toIso(this.pickupDateTime),
            end: toIso(this.returnDateTime)
        });
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url }
        });
    }

    // ---------- search ----------

    scheduleSearch() {
        if (!this.datesValid) {
            this._debouncer.cancel();
            return;
        }
        this._debouncer.run(() => this.runSearch());
    }

    buildRequest() {
        return {
            startDt: toIso(this.pickupDateTime),
            endDt: toIso(this.returnDateTime),
            city: this.branchCity || null,
            category: this.category || null,
            transmission: this.transmission || null,
            fuelType: this.fuelType || null,
            minSeats: toNumberOrNull(this.seats),
            maxDailyRate: toNumberOrNull(this.maxDailyRate)
        };
    }

    async runSearch() {
        if (!this.datesValid) {
            return;
        }
        const seq = ++this._requestSeq;
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const result = await searchVehicles({ request: this.buildRequest() });
            if (seq !== this._requestSeq) {
                return; // a newer search superseded this one
            }
            this.vehicles = Array.isArray(result) ? result : [];
        } catch (error) {
            if (seq !== this._requestSeq) {
                return;
            }
            this.vehicles = [];
            this.errorMessage = reduceError(error, 'We could not load cars right now. Please try again.');
        } finally {
            if (seq === this._requestSeq) {
                this.isLoading = false;
                this.hasSearched = true;
            }
        }
    }
}