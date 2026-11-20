import { createElement } from 'lwc';
import LicenseUpload from 'c/licenseUpload';
import getCustomerProfile from '@salesforce/apex/PortalController.getCustomerProfile';
import uploadLicenseImage from '@salesforce/apex/PortalController.uploadLicenseImage';
import verifyLicense from '@salesforce/apex/PortalController.verifyLicense';
import { compressImage, CompressionError } from '../imageCompressor';

jest.mock('@salesforce/apex/PortalController.getCustomerProfile', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PortalController.uploadLicenseImage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PortalController.verifyLicense', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/community/basePath', () => ({ __esModule: true, default: '/s' }), { virtual: true });
jest.mock('../imageCompressor', () => {
    class MockCompressionError extends Error {}
    return { compressImage: jest.fn(), CompressionError: MockCompressionError };
});

// drain chained promise callbacks (Apex mocks, async handlers, re-render) without timers (@lwc/lwc/no-async-operation)
const flush = async () => {
    for (let i = 0; i < 20; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};
const q = (el, sel) => el.shadowRoot.querySelector(sel);

const PROFILE = { isGuest: false, kycStatus: 'Not Submitted', name: 'Rahul Sharma' };

async function render(profile = PROFILE) {
    getCustomerProfile.mockResolvedValue(profile);
    const el = createElement('c-license-upload', { is: LicenseUpload });
    document.body.appendChild(el);
    await flush();
    return el;
}

async function giveConsent(el) {
    const consent = q(el, '[data-id="consent"]');
    consent.checked = true;
    consent.dispatchEvent(new CustomEvent('change'));
    await flush();
}

async function chooseFile(el, file = new File(['x'], 'licence.jpg', { type: 'image/jpeg' })) {
    const input = q(el, '[data-id="file-input"]');
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    input.dispatchEvent(new CustomEvent('change'));
    await flush();
    await flush();
}

describe('c-license-upload', () => {
    beforeEach(() => {
        compressImage.mockResolvedValue({ fileName: 'licence.jpg', base64Data: 'AAAA' });
        uploadLicenseImage.mockResolvedValue('068CV');
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('asks guests to log in and hides the upload form', async () => {
        const el = await render({ isGuest: true });
        expect(q(el, '[data-id="guest"]')).not.toBeNull();
        expect(q(el, '[data-id="file-input"]')).toBeNull();
    });

    it('keeps upload disabled until consent is given', async () => {
        const el = await render();
        expect(q(el, '[data-id="current-status"]').textContent).toContain('Not Submitted');
        expect(q(el, '[data-id="file-input"]').disabled).toBe(true);
        expect(q(el, '[data-id="consent-hint"]')).not.toBeNull();
        await giveConsent(el);
        expect(q(el, '[data-id="file-input"]').disabled).toBe(false);
    });

    it('uploads, verifies and shows the masked extracted details on success', async () => {
        verifyLicense.mockResolvedValue({
            status: 'Verified',
            extractedName: 'RAHUL SHARMA',
            maskedLicenseNumber: 'XXXX2345',
            licenseExpiry: '2035-01-01',
            dateOfBirth: '1998-05-10'
        });
        const el = await render();
        await giveConsent(el);
        await chooseFile(el);

        expect(uploadLicenseImage).toHaveBeenCalledWith({ fileName: 'licence.jpg', base64Data: 'AAAA' });
        expect(verifyLicense).toHaveBeenCalledWith({ contentVersionId: '068CV', consentGiven: true, bookingId: null });
        expect(q(el, '[data-id="result-verified"]')).not.toBeNull();
        expect(q(el, '[data-id="ex-licence"]').textContent).toBe('XXXX2345');
        expect(q(el, '[data-id="current-status"]').textContent).toContain('Verified');
    });

    it('shows the rejection reason (e.g. licence expires before trip end) with a retry option', async () => {
        verifyLicense.mockResolvedValue({ status: 'Rejected', reason: 'Licence expired / expires before trip ends.' });
        const el = await render();
        await giveConsent(el);
        await chooseFile(el);
        expect(q(el, '[data-id="result-rejected"]').textContent).toContain('expires before trip ends');
        q(el, '[data-id="retry"]').click();
        await flush();
        expect(q(el, '[data-id="result-rejected"]')).toBeNull();
        expect(q(el, '[data-id="file-input"]')).not.toBeNull();
    });

    it('shows pending review for a name mismatch', async () => {
        verifyLicense.mockResolvedValue({ status: 'Pending Review', reason: 'Name on the licence does not match your profile name.' });
        const el = await render();
        await giveConsent(el);
        await chooseFile(el);
        expect(q(el, '[data-id="result-pending"]')).not.toBeNull();
        expect(q(el, '[data-id="file-input"]')).toBeNull();
    });

    it('treats an OCR outage as retryable and leaves the KYC status unchanged', async () => {
        verifyLicense.mockResolvedValue({ status: 'Error', reason: 'Verification service unavailable.' });
        const el = await render();
        await giveConsent(el);
        await chooseFile(el);
        expect(q(el, '[data-id="result-error"]').textContent).toContain('unavailable');
        expect(q(el, '[data-id="extracted"]')).toBeNull();
        expect(q(el, '[data-id="current-status"]').textContent).toContain('Not Submitted');
        expect(q(el, '[data-id="retry"]')).not.toBeNull();
    });

    it('reports an unsupported or unreadable photo without calling the server', async () => {
        compressImage.mockRejectedValue(new CompressionError('Please choose a JPG or PNG photo.'));
        const el = await render();
        await giveConsent(el);
        await chooseFile(el, new File(['x'], 'licence.pdf', { type: 'application/pdf' }));
        expect(q(el, '[data-id="error"]').textContent).toContain('JPG or PNG');
        expect(uploadLicenseImage).not.toHaveBeenCalled();
        expect(verifyLicense).not.toHaveBeenCalled();
    });

    it('shows the server error when the upload is refused', async () => {
        uploadLicenseImage.mockRejectedValue({ body: { message: 'Please upload an image smaller than 4 MB.' } });
        const el = await render();
        await giveConsent(el);
        await chooseFile(el);
        expect(q(el, '[data-id="error"]').textContent).toContain('smaller than 4 MB');
        expect(verifyLicense).not.toHaveBeenCalled();
    });

    it('shows the already-verified state for a verified customer', async () => {
        const el = await render({ isGuest: false, kycStatus: 'Verified', maskedLicenseNumber: 'XXXX2345', licenseExpiry: '2035-01-01' });
        expect(q(el, '[data-id="already-verified"]')).not.toBeNull();
    });

    it('shows a warning when the profile cannot be loaded', async () => {
        getCustomerProfile.mockRejectedValue({ body: { message: 'Session expired.' } });
        const el = createElement('c-license-upload', { is: LicenseUpload });
        document.body.appendChild(el);
        await flush();
        expect(q(el, '[data-id="profile-error"]').textContent).toContain('Session expired.');
    });
});
