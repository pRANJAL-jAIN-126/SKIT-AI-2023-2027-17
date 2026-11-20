import { createElement } from 'lwc';
import RentalAssistant from 'c/rentalAssistant';
import chat from '@salesforce/apex/RentalAssistantController.chat';

jest.mock('@salesforce/apex/RentalAssistantController.chat', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/community/basePath', () => ({ __esModule: true, default: '/s' }), { virtual: true });

// drain chained promise callbacks (Apex mocks, async handlers, re-render) without timers (@lwc/lwc/no-async-operation)
const flush = async () => {
    for (let i = 0; i < 20; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const bubbles = (el) => [...el.shadowRoot.querySelectorAll('.bubble')].filter((b) => !b.classList.contains('typing'));

async function render() {
    const el = createElement('c-rental-assistant', { is: RentalAssistant });
    document.body.appendChild(el);
    await flush();
    return el;
}

async function type(el, text) {
    const input = q(el, '[data-id="input"]');
    input.value = text;
    input.dispatchEvent(new CustomEvent('change', { detail: { value: text } }));
    await flush();
}

describe('c-rental-assistant', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the welcome message and disables send for an empty draft', async () => {
        const el = await render();
        expect(bubbles(el)).toHaveLength(1);
        expect(bubbles(el)[0].textContent).toContain('I can help you find a car');
        expect(q(el, '[data-id="send"]').disabled).toBe(true);
        await type(el, '   ');
        expect(q(el, '[data-id="send"]').disabled).toBe(true);
    });

    it('sends the message with history and renders vehicles from the server reply only', async () => {
        chat.mockResolvedValue({
            reply: 'Here are cars free for those dates.',
            intent: 'search',
            vehicles: [
                { id: 'a0V1', make: 'Kia', model: 'Carens', category: 'MUV', seats: 7, dailyRate: 3800, total: 13452, days: 3, city: 'Jaipur' }
            ],
            links: []
        });
        const el = await render();
        await type(el, 'SUV in Jaipur from Friday 10am to Sunday 6pm');
        q(el, '[data-id="send"]').click();
        await flush();

        expect(chat).toHaveBeenCalledWith({ message: 'SUV in Jaipur from Friday 10am to Sunday 6pm', historyJson: '[]' });
        const all = bubbles(el);
        expect(all[1].textContent).toContain('SUV in Jaipur');
        expect(all[2].textContent).toContain('Here are cars free');
        const vehicleLink = el.shadowRoot.querySelector('a[href="/s/vehicle/a0V1"]');
        expect(vehicleLink).not.toBeNull();
        expect(el.shadowRoot.textContent).toContain('Kia Carens');

        // second turn carries the first exchange as history
        chat.mockResolvedValue({ reply: 'Anything else?' });
        await type(el, 'thanks');
        q(el, '[data-id="send"]').click();
        await flush();
        const history = JSON.parse(chat.mock.calls[1][0].historyJson);
        expect(history).toEqual([
            { role: 'user', text: 'SUV in Jaipur from Friday 10am to Sunday 6pm' },
            { role: 'assistant', text: 'Here are cars free for those dates.' }
        ]);
    });

    it('renders booking details and links returned by the server', async () => {
        chat.mockResolvedValue({
            reply: 'Booking BK-1001 is pending payment.',
            booking: { bookingNumber: 'BK-1001', vehicleName: 'Kia Carens', status: 'Pending Payment', grandTotal: 13260 },
            links: [{ label: 'Pay now', url: '/s/my-bookings?pay=a01X' }]
        });
        const el = await render();
        await type(el, 'status of BK-1001');
        q(el, '[data-id="send"]').click();
        await flush();
        expect(el.shadowRoot.textContent).toContain('BK-1001');
        expect(el.shadowRoot.textContent).toContain('Pending Payment');
        expect(el.shadowRoot.querySelector('a[href="/s/my-bookings?pay=a01X"]')).not.toBeNull();
    });

    it('sends on Enter but not on Shift+Enter', async () => {
        chat.mockResolvedValue({ reply: 'ok' });
        const el = await render();
        await type(el, 'hello');
        q(el, '[data-id="input"]').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', shiftKey: true }));
        await flush();
        expect(chat).not.toHaveBeenCalled();
        q(el, '[data-id="input"]').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
        await flush();
        expect(chat).toHaveBeenCalledTimes(1);
    });

    it('shows an error and keeps the conversation when the server fails', async () => {
        chat.mockRejectedValue({ body: { message: 'Please log in to continue.' } });
        const el = await render();
        await type(el, 'cancel BK-1001');
        q(el, '[data-id="send"]').click();
        await flush();
        expect(q(el, '[data-id="error"]').textContent).toContain('Please log in to continue.');
        expect(bubbles(el)).toHaveLength(2); // welcome + user message, no invented assistant reply
        expect(q(el, '[data-id="typing"]')).toBeNull();
    });

    it('uses a neutral fallback reply when the server returns nothing', async () => {
        chat.mockResolvedValue(null);
        const el = await render();
        await type(el, '???');
        q(el, '[data-id="send"]').click();
        await flush();
        expect(bubbles(el)[2].textContent).toContain('Could you rephrase');
    });
});
