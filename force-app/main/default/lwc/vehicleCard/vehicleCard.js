import { LightningElement, api } from 'lwc';
import { formatMoney } from 'c/rentalUtils';

export default class VehicleCard extends LightningElement {
    @api vehicle;
    @api totalPrice;
    @api days;

    imageFailed = false;

    get v() {
        return this.vehicle || {};
    }

    get hasImage() {
        return !!this.v.imageUrl && !this.imageFailed;
    }

    get title() {
        const v = this.v;
        const mm = [v.make, v.model].filter(Boolean).join(' ');
        return mm || v.name || 'Vehicle';
    }

    get imageAlt() {
        return `${this.title} photo`;
    }

    get yearLabel() {
        return this.v.year ? String(this.v.year) : '';
    }

    get seatsLabel() {
        return this.v.seats ? `${this.v.seats} seats` : '';
    }

    get branchLabel() {
        const v = this.v;
        return [v.branchName, v.city].filter(Boolean).join(', ');
    }

    get dailyRate() {
        return formatMoney(this.v.dailyRate);
    }

    get effectiveDays() {
        const d = this.days !== undefined && this.days !== null ? this.days : this.v.days;
        return d ? Number(d) : null;
    }

    get effectiveTotal() {
        if (this.totalPrice !== undefined && this.totalPrice !== null && this.totalPrice !== '') {
            return this.totalPrice;
        }
        return this.v.total;
    }

    get hasTotal() {
        return !!this.effectiveDays && this.effectiveTotal !== undefined && this.effectiveTotal !== null;
    }

    get totalLabel() {
        return formatMoney(this.effectiveTotal);
    }

    get daysLabel() {
        const d = this.effectiveDays;
        return d === 1 ? '1 day' : `${d} days`;
    }

    get selectLabel() {
        return `Select ${this.title}`;
    }

    handleImageError() {
        this.imageFailed = true;
    }

    handleSelect() {
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: { vehicleId: this.v.id }
            })
        );
    }
}