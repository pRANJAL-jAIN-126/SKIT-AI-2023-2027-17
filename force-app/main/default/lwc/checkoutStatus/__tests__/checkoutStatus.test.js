import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import CheckoutStatus from 'c/checkoutStatus';
import confirmPayment from '@salesforce/apex/PortalController.confirmPayment';

jest.mock(
    '@salesforce/apex/PortalController.confirmPayment',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/community/basePath', () => ({ default: '/s' }), {
    virtual: true
});

const flushPromises = async () => {
    await Promise.resolve();
    await Promise.resolve();
};

describe('c-checkout-status payment review state', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows manual review instead of claiming the booking is confirmed', async () => {
        confirmPayment.mockResolvedValue({
            status: 'Review',
            message: 'Your payment was received, but the booking needs a quick manual check.'
        });

        const element = createElement('c-checkout-status', { is: CheckoutStatus });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            attributes: {},
            state: { session_id: 'cs_test_12345' }
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="review"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="success"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="review"]').textContent).toContain('manual check');
        expect(confirmPayment).toHaveBeenCalledTimes(1);
    });

    it('shows a refunded payment as a terminal refund result', async () => {
        confirmPayment.mockResolvedValue({
            status: 'Refunded',
            message: 'This payment has been refunded.'
        });

        const element = createElement('c-checkout-status', { is: CheckoutStatus });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            attributes: {},
            state: { session_id: 'cs_test_refunded' }
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="refunded"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="success"]')).toBeNull();
        expect(confirmPayment).toHaveBeenCalledTimes(1);
    });
});
