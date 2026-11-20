import { createElement } from 'lwc';
import MyBookings from 'c/myBookings';
import getMyBookings from '@salesforce/apex/PortalController.getMyBookings';
import getCancellationQuote from '@salesforce/apex/PortalController.getCancellationQuote';
import cancelBooking from '@salesforce/apex/PortalController.cancelBooking';
import startCheckout from '@salesforce/apex/PortalController.startCheckout';

jest.mock('@salesforce/apex/PortalController.getMyBookings', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PortalController.getCancellationQuote', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PortalController.cancelBooking', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PortalController.startCheckout', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/community/basePath', () => ({ __esModule: true, default: '/s' }), { virtual: true });

// drain chained promise callbacks (Apex mocks, async handlers, re-render) without timers (@lwc/lwc/no-async-operation)
const flush = async () => {
    for (let i = 0; i < 20; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};

const PENDING = {
    id: 'a01PENDING',
    bookingNumber: 'BK-1001',
    vehicleName: 'Kia Carens',
    status: 'Pending Payment',
    paymentStatus: 'Unpaid',
    startDt: '2026-12-01T04:30:00.000Z',
    endDt: '2026-12-03T04:30:00.000Z',
    rentalDays: 2,
    grandTotal: 13260,
    holdExpiresAt: '2026-11-15T10:00:00.000Z',
    canPay: true,
    canCancel: true
};
const CANCELLED_REFUNDED = {
    id: 'a01CANCELLED',
    bookingNumber: 'BK-1002',
    vehicleName: 'Toyota Innova Crysta',
    status: 'Cancelled',
    paymentStatus: 'Refunded',
    startDt: '2026-12-10T04:30:00.000Z',
    endDt: '2026-12-11T04:30:00.000Z',
    grandTotal: 9956,
    refundAmount: 9956,
    canPay: false,
    canCancel: false
};
const OVERDUE = {
    id: 'a01OVERDUE',
    bookingNumber: 'BK-1003',
    vehicleName: 'Maruti Swift',
    status: 'Active',
    paymentStatus: 'Paid',
    isOverdue: true,
    lateFee: 500,
    grandTotal: 4000,
    canPay: false,
    canCancel: false
};

async function render() {
    const el = createElement('c-my-bookings', { is: MyBookings });
    document.body.appendChild(el);
    await flush();
    return el;
}

const q = (el, sel) => el.shadowRoot.querySelector(sel);
const qa = (el, sel) => [...el.shadowRoot.querySelectorAll(sel)];

describe('c-my-bookings', () => {
    let assignSpy;

    beforeEach(() => {
        assignSpy = jest.fn();
        delete window.location;
        window.location = { assign: assignSpy, search: '' };
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the empty state with a link to the fleet', async () => {
        getMyBookings.mockResolvedValue([]);
        const el = await render();
        expect(q(el, '[data-id="empty"]')).not.toBeNull();
        expect(q(el, '[data-id="fleet-link"]').getAttribute('href')).toBe('/s/fleet');
        expect(qa(el, 'article')).toHaveLength(0);
    });

    it('shows an error when bookings cannot be loaded', async () => {
        getMyBookings.mockRejectedValue({ body: { message: 'Please log in to continue.' } });
        const el = await render();
        expect(q(el, '[data-id="error"]').textContent).toContain('Please log in to continue.');
        expect(q(el, '[data-id="empty"]')).toBeNull();
    });

    it('renders status badges, refund and overdue states', async () => {
        getMyBookings.mockResolvedValue([PENDING, CANCELLED_REFUNDED, OVERDUE]);
        const el = await render();
        const cards = qa(el, 'article');
        expect(cards).toHaveLength(3);

        const badges = qa(el, '[data-id="status-badge"]').map((b) => [b.textContent, b.className]);
        expect(badges[0]).toEqual(['Pending Payment', 'badge badge-pending']);
        expect(badges[1]).toEqual(['Cancelled', 'badge badge-cancelled']);
        expect(badges[2]).toEqual(['Active', 'badge badge-active']);

        // refund row only on the refunded booking
        const cancelledText = cards[1].textContent;
        expect(cancelledText).toContain('Refund');
        expect(cancelledText).toContain('Refunded');
        expect(cards[0].textContent).not.toContain('Refund');

        // overdue warning + late fee only on the overdue booking
        expect(cards[2].querySelector('[data-id="overdue"]')).not.toBeNull();
        expect(cards[2].textContent).toContain('Late fee');
        expect(cards[0].querySelector('[data-id="overdue"]')).toBeNull();

        // pay / cancel actions follow server flags
        expect(cards[0].querySelector('[data-action="pay"]')).not.toBeNull();
        expect(cards[0].querySelector('[data-action="cancel"]')).not.toBeNull();
        expect(cards[1].querySelector('[data-action="pay"]')).toBeNull();
        expect(cards[1].querySelector('[data-action="cancel"]')).toBeNull();
    });

    it('starts Stripe checkout and redirects to the returned url', async () => {
        getMyBookings.mockResolvedValue([PENDING]);
        startCheckout.mockResolvedValue({ url: 'https://checkout.stripe.com/c/pay/cs_test_x', sessionId: 'cs_test_x' });
        const el = await render();
        q(el, '[data-action="pay"]').click();
        await flush();
        expect(startCheckout).toHaveBeenCalledWith({ bookingId: 'a01PENDING' });
        expect(assignSpy).toHaveBeenCalledWith('https://checkout.stripe.com/c/pay/cs_test_x');
    });

    it('shows the server error when checkout is refused (e.g. KYC not verified)', async () => {
        getMyBookings.mockResolvedValue([PENDING]);
        startCheckout.mockRejectedValue({ body: { message: 'Please verify your driving licence before paying.' } });
        const el = await render();
        q(el, '[data-action="pay"]').click();
        await flush();
        expect(q(el, '[data-id="pay-error"]').textContent).toContain('verify your driving licence');
        expect(assignSpy).not.toHaveBeenCalled();
    });

    it('does not redirect when checkout returns no url', async () => {
        getMyBookings.mockResolvedValue([PENDING]);
        startCheckout.mockResolvedValue({});
        const el = await render();
        q(el, '[data-action="pay"]').click();
        await flush();
        expect(q(el, '[data-id="pay-error"]')).not.toBeNull();
        expect(assignSpy).not.toHaveBeenCalled();
    });

    it('previews the refund, then cancels only after explicit confirmation', async () => {
        getMyBookings.mockResolvedValueOnce([PENDING]).mockResolvedValueOnce([{ ...PENDING, status: 'Cancelled', canPay: false, canCancel: false }]);
        getCancellationQuote.mockResolvedValue({ refundAmount: 9760, retainedAmount: 3500, fullRefund: false, message: 'One day retained.' });
        cancelBooking.mockResolvedValue({ bookingNumber: 'BK-1001', message: 'Booking BK-1001 has been cancelled.' });
        const el = await render();

        q(el, '[data-action="cancel"]').click();
        await flush();
        expect(getCancellationQuote).toHaveBeenCalledWith({ bookingId: 'a01PENDING' });
        expect(q(el, '[data-id="cancel-panel"]')).not.toBeNull();
        expect(q(el, '[data-id="quote"]').textContent).toContain('Cancellation charge');
        expect(cancelBooking).not.toHaveBeenCalled();

        q(el, '[data-id="confirm-cancel"]').click();
        await flush();
        expect(cancelBooking).toHaveBeenCalledWith({ bookingId: 'a01PENDING' });
        expect(q(el, '[data-id="success"]').textContent).toContain('has been cancelled');
        expect(q(el, '[data-id="cancel-panel"]')).toBeNull();
        expect(getMyBookings).toHaveBeenCalledTimes(2);
        expect(q(el, '[data-id="status-badge"]').textContent).toBe('Cancelled');
    });

    it('keeps the booking when the customer closes the cancel panel', async () => {
        getMyBookings.mockResolvedValue([PENDING]);
        getCancellationQuote.mockResolvedValue({ refundAmount: 13260, retainedAmount: 0, fullRefund: true });
        const el = await render();
        q(el, '[data-action="cancel"]').click();
        await flush();
        q(el, '[data-id="keep"]').click();
        await flush();
        expect(q(el, '[data-id="cancel-panel"]')).toBeNull();
        expect(cancelBooking).not.toHaveBeenCalled();
    });

    it('disables confirmation when the refund quote fails', async () => {
        getMyBookings.mockResolvedValue([PENDING]);
        getCancellationQuote.mockRejectedValue({ body: { message: 'This booking can no longer be cancelled.' } });
        const el = await render();
        q(el, '[data-action="cancel"]').click();
        await flush();
        expect(q(el, '[data-id="quote-error"]').textContent).toContain('no longer be cancelled');
        expect(q(el, '[data-id="confirm-cancel"]').disabled).toBe(true);
    });

    it('shows a cancellation failure without closing the panel', async () => {
        getMyBookings.mockResolvedValue([PENDING]);
        getCancellationQuote.mockResolvedValue({ refundAmount: 13260, fullRefund: true });
        cancelBooking.mockRejectedValue({ body: { message: 'Booking not found.' } });
        const el = await render();
        q(el, '[data-action="cancel"]').click();
        await flush();
        q(el, '[data-id="confirm-cancel"]').click();
        await flush();
        expect(q(el, '[data-id="cancel-panel"]')).not.toBeNull();
        expect(q(el, '[data-id="quote-error"]').textContent).toContain('Booking not found.');
        expect(q(el, '[data-id="success"]')).toBeNull();
    });
});
