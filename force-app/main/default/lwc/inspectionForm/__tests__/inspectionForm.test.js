import { createElement } from 'lwc';
import InspectionForm from 'c/inspectionForm';
import getInspectionContext from '@salesforce/apex/InspectionController.getInspectionContext';
import saveInspection from '@salesforce/apex/InspectionController.saveInspection';

jest.mock('@salesforce/apex/InspectionController.getInspectionContext', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/InspectionController.saveInspection', () => ({ default: jest.fn() }), { virtual: true });

const TOAST_EVENT = 'lightning__showtoast'; // lightning/platformShowToastEvent event name
// drain chained promise callbacks (Apex mocks, async handlers, re-render) without timers (@lwc/lwc/no-async-operation)
const flush = async () => {
    for (let i = 0; i < 20; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};
const q = (el, sel) => el.shadowRoot.querySelector(sel);

const PICKUP_CTX = {
    bookingId: 'a01B',
    bookingNumber: 'BK-1001',
    bookingStatus: 'Confirmed',
    vehicleName: 'Kia Carens',
    currentOdometer: 10000,
    nextType: 'Pickup',
    message: 'Record the pickup inspection when handing over the car.'
};
const RETURN_CTX = {
    ...PICKUP_CTX,
    bookingStatus: 'Active',
    pickupOdometer: 10050,
    pickupFuel: 'Full',
    nextType: 'Return',
    message: 'Record the return inspection when the car comes back.'
};

async function render(ctx) {
    getInspectionContext.mockResolvedValue(ctx);
    const el = createElement('c-inspection-form', { is: InspectionForm });
    el.recordId = 'a01B';
    document.body.appendChild(el);
    await flush();
    return el;
}

function setField(el, field, value) {
    const input = q(el, `[data-field="${field}"]`);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

function stubValidity(el) {
    const calls = [];
    el.shadowRoot.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea').forEach((node) => {
        node.reportValidity = jest.fn(() => !node._customError);
        node.setCustomValidity = jest.fn((msg) => {
            node._customError = msg;
            calls.push(msg);
        });
    });
    return calls;
}

const saveButton = (el) => q(el, 'lightning-button');

describe('c-inspection-form', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the pickup context for the record page booking', async () => {
        const el = await render(PICKUP_CTX);
        expect(getInspectionContext).toHaveBeenCalledWith({ bookingId: 'a01B' });
        expect(q(el, 'lightning-card').title).toBe('Pickup inspection');
        expect(el.shadowRoot.textContent).toContain('Current odometer: 10000 km');
        expect(q(el, '[data-field="estimatedCharge"]')).toBeNull();
        expect(q(el, 'lightning-record-picker')).toBeNull();
    });

    it('shows the server message when no inspection is due', async () => {
        const el = await render({ ...PICKUP_CTX, nextType: null, message: 'Inspections can only be recorded for Confirmed (pickup) or Active (return) bookings. Current status: Pending Payment.' });
        expect(q(el, '[data-id="no-inspection"]').textContent).toContain('Current status: Pending Payment');
        expect(saveButton(el)).toBeNull();
    });

    it('shows a load error', async () => {
        getInspectionContext.mockRejectedValue({ body: { message: 'Booking not found.' } });
        const el = createElement('c-inspection-form', { is: InspectionForm });
        el.recordId = 'a01X';
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.textContent).toContain('Booking not found.');
    });

    it('blocks a return odometer lower than the pickup reading without calling the server', async () => {
        const el = await render(RETURN_CTX);
        expect(q(el, '[data-field="estimatedCharge"]')).not.toBeNull();
        const validityCalls = stubValidity(el);
        setField(el, 'odometer', '10010');
        saveButton(el).click();
        await flush();
        expect(validityCalls).toContain('Return odometer cannot be lower than the pickup reading.');
        expect(saveInspection).not.toHaveBeenCalled();
    });

    it('saves a return inspection with damage details and photos, then reloads', async () => {
        saveInspection.mockResolvedValue('a0I1');
        const el = await render(RETURN_CTX);
        const toast = jest.fn();
        el.addEventListener(TOAST_EVENT, toast);
        stubValidity(el);
        setField(el, 'odometer', '10420');
        setField(el, 'fuelLevel', '1/2');
        setField(el, 'exteriorCondition', 'Minor Damage');
        setField(el, 'damageNotes', 'Scratch on rear bumper');
        setField(el, 'estimatedCharge', '2500');
        const damage = q(el, '[data-field="damageDetected"]');
        damage.type = 'checkbox';
        damage.checked = true;
        damage.dispatchEvent(new CustomEvent('change'));
        q(el, 'lightning-file-upload').dispatchEvent(
            new CustomEvent('uploadfinished', { detail: { files: [{ documentId: '069A', name: 'bumper.jpg' }] } })
        );
        await flush();

        saveButton(el).click();
        await flush();

        expect(saveInspection).toHaveBeenCalledTimes(1);
        const arg = saveInspection.mock.calls[0][0];
        expect(arg.contentDocumentIds).toEqual(['069A']);
        expect(arg.inspection).toMatchObject({
            sobjectType: 'Inspection__c',
            Booking__c: 'a01B',
            Type__c: 'Return',
            Odometer__c: 10420,
            Fuel_Level__c: '1/2',
            Exterior_Condition__c: 'Minor Damage',
            Damage_Notes__c: 'Scratch on rear bumper',
            Damage_Detected__c: true,
            Estimated_Charge__c: 2500
        });
        expect(toast).toHaveBeenCalled();
        expect(toast.mock.calls[0][0].detail.variant).toBe('success');
        expect(getInspectionContext).toHaveBeenCalledTimes(2);
    });

    it('does not send an estimated charge for a pickup inspection', async () => {
        saveInspection.mockResolvedValue('a0I2');
        const el = await render(PICKUP_CTX);
        stubValidity(el);
        setField(el, 'odometer', '10000');
        saveButton(el).click();
        await flush();
        const arg = saveInspection.mock.calls[0][0].inspection;
        expect(arg.Type__c).toBe('Pickup');
        expect(arg).not.toHaveProperty('Estimated_Charge__c');
    });

    it('shows a server rejection as an error toast and message', async () => {
        saveInspection.mockRejectedValue({ body: { message: 'A Return inspection already exists for this booking.' } });
        const el = await render(RETURN_CTX);
        const toast = jest.fn();
        el.addEventListener(TOAST_EVENT, toast);
        stubValidity(el);
        setField(el, 'odometer', '10500');
        saveButton(el).click();
        await flush();
        expect(toast.mock.calls[0][0].detail.variant).toBe('error');
        expect(el.shadowRoot.textContent).toContain('already exists');
    });
});
