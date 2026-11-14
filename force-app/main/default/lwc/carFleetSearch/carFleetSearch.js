import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import searchVehicles from '@salesforce/apex/PortalController.searchVehicles';
import basePath from '@salesforce/community/basePath';
import LOCALE from '@salesforce/i18n/locale';
import {
    buildUrl,
    createDebouncer,
    dateBadInputMessage,
    getUrlDateParam,
    getUrlParam,
    reduceError,
    toIso,
    toNumberOrNull,
    validateDateRange
} from 'c/rentalUtils';

const DEBOUNCE_MS = 400;
const ANY = '';
const INVALID_FILTERS_MESSAGE = 'Fix the highlighted filters to search.';

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
    filterError = null;
    hasSearched = false;
    dateBadInputMessage = dateBadInputMessage(LOCALE);

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
        const start = getUrlDateParam(pageRef, 'start');
        const end = getUrlDateParam(pageRef, 'end');
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

    // ---------- "More filters" (collapsed on phones only, see CSS) ----------

    showMoreFilters = false;

    get extraClass() {
        return this.showMoreFilters ? 'extra' : 'extra extra-collapsed';
    }

    get activeExtraFilterCount() {
        return [this.category, this.seats, this.transmission, this.fuelType, this.maxDailyRate].filter(
            (v) => v !== null && v !== undefined && v !== ANY
        ).length;
    }

    get moreFiltersLabel() {
        if (this.showMoreFilters) {
            return 'Fewer filters';
        }
        const n = this.activeExtraFilterCount;
        return n ? `More filters (${n} active)` : 'More filters';
    }

    get moreFiltersIcon() {
        return this.showMoreFilters ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get moreFiltersExpanded() {
        return this.showMoreFilters ? 'true' : 'false';
    }

    handleToggleMoreFilters() {
        this.showMoreFilters = !this.showMoreFilters;
    }

    get searchDisabled() {
        return !this.datesValid || this.isLoading;
    }

    get hasResults() {
        return !this.isLoading && !this.errorMessage && !this.filterError && this.vehicles.length > 0;
    }

    get showEmpty() {
        return (
            this.hasSearched && !this.isLoading && !this.errorMessage && !this.filterError && this.vehicles.length === 0
        );
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
        this.filterError = null;
        this.scheduleSearch();
    }

    handleSearchClick() {
        this._debouncer.cancel();
        if (!this.validateFilters(true)) {
            this.blockSearch();
            return;
        }
        this.runSearch();
    }

    /** Resets every search criterion (dates, city, filters), the typed text, validation messages and results. */
    handleReset() {
        this._debouncer.cancel();
        this._requestSeq++; // ignore any search still in flight
        this.pickupDateTime = null;
        this.returnDateTime = null;
        this.branchCity = this.defaultCity || ANY;
        this.category = ANY;
        this.seats = null;
        this.transmission = ANY;
        this.fuelType = ANY;
        this.maxDailyRate = null;
        this.vehicles = [];
        this.isLoading = false;
        this.errorMessage = null;
        this.filterError = null;
        this.hasSearched = false;
        this._dirty = false;
        // A number field holding unparseable text (e.g. "abc") already reports value '' to lightning-input, so
        // setting it to null again is "no change" and the typed text stays on screen. Give number fields a
        // different value first, then the real (empty) value after that render, then re-check validity so the
        // red messages disappear. Each .then runs after the re-render queued by the previous step.
        this.filterFields().forEach((field) => {
            field.value = field.type === 'number' ? '0' : null;
            if (typeof field.setCustomValidity === 'function') {
                field.setCustomValidity('');
            }
        });
        Promise.resolve()
            .then(() => {
                this.filterFields().forEach((field) => {
                    if (field.dataset.field && field.tagName && field.tagName.toLowerCase() === 'lightning-input') {
                        field.value = this[field.dataset.field];
                    }
                });
            })
            .then(() => {
                this.filterFields().forEach((field) => {
                    if (typeof field.reportValidity === 'function' && !field.required) {
                        field.reportValidity();
                    }
                });
            });
    }

    filterFields() {
        return [...this.template.querySelectorAll('[data-validate]')];
    }

    /**
     * True when every filter field holds a usable value. With report=true each invalid field shows its own message.
     * Only an explicit `false` counts as invalid (lightning base components always return a boolean).
     */
    validateFilters(report = false) {
        let ok = true;
        this.filterFields().forEach((field) => {
            const fn = report ? field.reportValidity : field.checkValidity;
            if (typeof fn === 'function' && fn.call(field) === false) {
                ok = false;
            }
        });
        return ok;
    }

    blockSearch() {
        this._requestSeq++;
        this.isLoading = false;
        this.vehicles = [];
        this.hasSearched = false;
        this.filterError = INVALID_FILTERS_MESSAGE;
        this.showMoreFilters = true; // never hide the field that is blocking the search
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
        this._debouncer.run(() => {
            if (!this.validateFilters(true)) {
                this.blockSearch();
                return;
            }
            this.runSearch();
        });
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
        // Never search with a filter the customer typed but we could not understand (e.g. "abc" seats, -500 price).
        if (!this.validateFilters(false)) {
            this.blockSearch();
            return;
        }
        this.filterError = null;
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