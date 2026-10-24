import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import getInspectionContext from '@salesforce/apex/InspectionController.getInspectionContext';
import saveInspection from '@salesforce/apex/InspectionController.saveInspection';
import { reduceError, toNumberOrNull } from 'c/rentalUtils';

const toOptions = (values) => values.map((v) => ({ label: v, value: v }));

// Picklist values mirror Inspection__c field metadata.
const FUEL_LEVELS = toOptions(['Empty', '1/4', '1/2', '3/4', 'Full']);
const CONDITIONS = toOptions(['Excellent', 'Good', 'Minor Damage', 'Major Damage']);

export default class InspectionForm extends LightningElement {
    /** Booking__c record id (record page). On an app page the user picks a booking. */
    @api recordId;

    pickedBookingId = null;

    context = null;
    isLoading = false;
    isSaving = false;
    loadError = null;
    saveError = null;

    odometer = null;
    fuelLevel = null;
    exteriorCondition = 'Good';
    interiorCondition = 'Good';
    damageNotes = '';
    damageDetected = false;
    estimatedCharge = null;
    uploadedFiles = [];

    fuelOptions = FUEL_LEVELS;
    conditionOptions = CONDITIONS;
    acceptedFormats = ['.jpg', '.jpeg', '.png', '.heic'];

    connectedCallback() {
        if (this.bookingId) {
            this.loadContext();
        }
    }

    // ---------- derived ----------

    get bookingId() {
        return this.recordId || this.pickedBookingId;
    }

    get showPicker() {
        return !this.recordId;
    }

    get hasContext() {
        return !!this.context;
    }

    get inspectionType() {
        return this.context && this.context.nextType;
    }

    get canInspect() {
        return !!this.inspectionType;
    }

    get isReturn() {
        return this.inspectionType === 'Return';
    }

    get cardTitle() {
        return this.inspectionType ? `${this.inspectionType} inspection` : 'Vehicle inspection';
    }

    get contextMessage() {
        return (this.context && this.context.message) || 'No inspection is due for this booking right now.';
    }

    get minOdometer() {
        if (!this.context) {
            return null;
        }
        const v = this.isReturn ? this.context.pickupOdometer : this.context.currentOdometer;
        return v === null || v === undefined ? null : Number(v);
    }

    get odometerHelp() {
        if (this.minOdometer === null) {
            return '';
        }
        return this.isReturn
            ? `Must be at least the pickup reading (${this.minOdometer} km).`
            : `Must be at least the current reading (${this.minOdometer} km).`;
    }

    get odometerMessage() {
        return this.isReturn
            ? 'Return odometer cannot be lower than the pickup reading.'
            : 'Odometer cannot be lower than the vehicle’s current reading.';
    }

    get hasFiles() {
        return this.uploadedFiles.length > 0;
    }

    get saveDisabled() {
        return this.isSaving || !this.canInspect;
    }

    // ---------- data ----------

    async loadContext() {
        if (!this.bookingId) {
            return;
        }
        this.isLoading = true;
        this.loadError = null;
        try {
            this.context = await getInspectionContext({ bookingId: this.bookingId });
            this.resetForm();
        } catch (error) {
            this.context = null;
            this.loadError = reduceError(error, 'Could not load the booking for inspection.');
        } finally {
            this.isLoading = false;
        }
    }

    resetForm() {
        this.odometer = null;
        this.fuelLevel = null;
        this.exteriorCondition = 'Good';
        this.interiorCondition = 'Good';
        this.damageNotes = '';
        this.damageDetected = false;
        this.estimatedCharge = null;
        this.uploadedFiles = [];
        this.saveError = null;
    }

    // ---------- handlers ----------

    handleBookingPicked(event) {
        this.pickedBookingId = event.detail && event.detail.recordId ? event.detail.recordId : null;
        this.context = null;
        if (this.pickedBookingId) {
            this.loadContext();
        }
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            this[field] = event.target.checked;
        } else {
            this[field] = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        }
    }

    handleUploadFinished(event) {
        const files = (event.detail && event.detail.files) || [];
        this.uploadedFiles = [
            ...this.uploadedFiles,
            ...files.map((f) => ({ documentId: f.documentId, name: f.name }))
        ];
    }

    validate() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')];
        const odo = this.template.querySelector('[data-field="odometer"]');
        if (odo) {
            const value = toNumberOrNull(this.odometer);
            const min = this.minOdometer;
            odo.setCustomValidity(value !== null && min !== null && value < min ? this.odometerMessage : '');
        }
        return inputs.reduce((ok, el) => {
            if (typeof el.reportValidity === 'function') {
                return el.reportValidity() && ok;
            }
            return ok;
        }, true);
    }

    async handleSave() {
        this.saveError = null;
        if (!this.validate()) {
            return;
        }
        this.isSaving = true;
        try {
            const inspection = {
                sobjectType: 'Inspection__c',
                Booking__c: this.bookingId,
                Type__c: this.inspectionType,
                Odometer__c: toNumberOrNull(this.odometer),
                Fuel_Level__c: this.fuelLevel,
                Exterior_Condition__c: this.exteriorCondition,
                Interior_Condition__c: this.interiorCondition,
                Damage_Notes__c: this.damageNotes || null,
                Damage_Detected__c: this.damageDetected === true
            };
            if (this.isReturn) {
                inspection.Estimated_Charge__c = toNumberOrNull(this.estimatedCharge);
            }
            await saveInspection({
                inspection,
                contentDocumentIds: this.uploadedFiles.map((f) => f.documentId)
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Inspection saved',
                    message: `${this.inspectionType} inspection recorded for ${this.context.bookingNumber || 'the booking'}.`,
                    variant: 'success'
                })
            );
            try {
                await notifyRecordUpdateAvailable([{ recordId: this.bookingId }]);
            } catch {
                // non-fatal: record page will refresh on next load
            }
            this.dispatchEvent(new RefreshEvent());
            await this.loadContext();
        } catch (error) {
            this.saveError = reduceError(error, 'Could not save the inspection. Please try again.');
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Inspection not saved', message: this.saveError, variant: 'error' })
            );
        } finally {
            this.isSaving = false;
        }
    }
}