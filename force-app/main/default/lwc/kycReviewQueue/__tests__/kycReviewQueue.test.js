import { createElement } from 'lwc';
import KycReviewQueue from 'c/kycReviewQueue';
import getPendingReviews from '@salesforce/apex/KycReviewController.getPendingReviews';
import approve from '@salesforce/apex/KycReviewController.approve';
import reject from '@salesforce/apex/KycReviewController.reject';

jest.mock('@salesforce/apex/KycReviewController.getPendingReviews', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/KycReviewController.approve', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/KycReviewController.reject', () => ({ default: jest.fn() }), { virtual: true });

const TOAST_EVENT = 'lightning__showtoast';
// drain chained promise callbacks without timers (@lwc/lwc/no-async-operation)
const flush = async () => {
    for (let i = 0; i < 20; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};
const q = (el, sel) => el.shadowRoot.querySelector(sel);

const ROW = {
    contactId: '003RITVIK',
    name: 'Ritvik Jolia',
    email: 'ritvik@example.test',
    submittedAt: '2026-11-16T04:26:43.000Z',
    reason: 'Automatic check was not available (Verification service is busy, try again.). Please read the licence photo.',
    photoUrl: '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=068X',
    downloadUrl: '/sfc/servlet.shepherd/version/download/068X',
    mustBeValidUntil: '2026-11-20',
    openBookings: 1
};

async function render() {
    const el = createElement('c-kyc-review-queue', { is: KycReviewQueue });
    document.body.appendChild(el);
    await flush();
    return el;
}

function setField(el, field, value) {
    const input = q(el, `[data-field="${field}"]`);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-kyc-review-queue', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the empty state when nothing is pending', async () => {
        getPendingReviews.mockResolvedValue([]);
        const el = await render();
        expect(q(el, '[data-id="empty"]')).not.toBeNull();
    });

    it('lists pending customers with photo, reason and validity requirement', async () => {
        getPendingReviews.mockResolvedValue([ROW]);
        const el = await render();
        expect(q(el, '[data-id="count"]').textContent).toBe('1 licence waiting for review');
        expect(q(el, 'img').getAttribute('src')).toBe(ROW.photoUrl);
        expect(q(el, '[data-id="reason"]').textContent).toContain('Automatic check was not available');
        expect(el.shadowRoot.textContent).toContain('Ritvik Jolia');
    });

    it('requires the expiry date before approving', async () => {
        getPendingReviews.mockResolvedValue([ROW]);
        const el = await render();
        q(el, '[data-action="approve"]').click();
        await flush();
        expect(approve).not.toHaveBeenCalled();
        expect(q(el, '[data-id="form-error"]').textContent).toContain('expiry date');
    });

    it('approves with the entered details, toasts and reloads', async () => {
        getPendingReviews.mockResolvedValueOnce([ROW]).mockResolvedValueOnce([]);
        approve.mockResolvedValue();
        const el = await render();
        const toast = jest.fn();
        el.addEventListener(TOAST_EVENT, toast);
        setField(el, 'expiry', '2045-08-10');
        setField(el, 'dob', '2005-08-11');
        setField(el, 'licence', 'RJ59 2023 0022340');
        await flush();
        q(el, '[data-action="approve"]').click();
        await flush();
        expect(approve).toHaveBeenCalledWith({
            contactId: '003RITVIK',
            licenseExpiry: '2045-08-10',
            dateOfBirth: '2005-08-11',
            licenseNumber: 'RJ59 2023 0022340'
        });
        expect(toast.mock.calls[0][0].detail.variant).toBe('success');
        expect(q(el, '[data-id="empty"]')).not.toBeNull();
    });

    it('requires a reason to reject and shows server errors', async () => {
        getPendingReviews.mockResolvedValue([ROW]);
        reject.mockRejectedValue({ body: { message: 'This licence was already reviewed (status Verified). Refresh the list.' } });
        const el = await render();
        q(el, '[data-action="reject"]').click();
        await flush();
        expect(reject).not.toHaveBeenCalled();
        expect(q(el, '[data-id="form-error"]').textContent).toContain('reason');

        setField(el, 'reason', 'Photo is blurred');
        await flush();
        q(el, '[data-action="reject"]').click();
        await flush();
        expect(reject).toHaveBeenCalledWith({ contactId: '003RITVIK', reason: 'Photo is blurred' });
        expect(q(el, '[data-id="form-error"]').textContent).toContain('already reviewed');
    });

    it('shows a load error', async () => {
        getPendingReviews.mockRejectedValue({ body: { message: 'Only rental staff can review driving licences.' } });
        const el = await render();
        expect(q(el, '[data-id="load-error"]').textContent).toContain('Only rental staff');
    });
});
