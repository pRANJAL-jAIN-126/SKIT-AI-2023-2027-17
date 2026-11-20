import { createElement } from 'lwc';
import VehicleCard from 'c/vehicleCard';

const flush = () => Promise.resolve();
const q = (el, sel) => el.shadowRoot.querySelector(sel);

const VEHICLE = {
    id: 'a0V1',
    make: 'Toyota',
    model: 'Innova Crysta',
    year: 2023,
    category: 'MUV',
    seats: 7,
    fuelType: 'Diesel',
    transmission: 'Automatic',
    branchName: 'Jaipur Central',
    city: 'Jaipur',
    dailyRate: 4200,
    imageUrl: '/resource/VehicleImages/toyota-innova-crysta.jpg'
};

function render(props) {
    const el = createElement('c-vehicle-card', { is: VehicleCard });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-vehicle-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders title, specs, branch and daily rate', async () => {
        const el = render({ vehicle: VEHICLE });
        await flush();
        const text = el.shadowRoot.textContent;
        expect(q(el, '.title').textContent).toBe('Toyota Innova Crysta');
        expect(text).toContain('2023');
        expect(text).toContain('MUV');
        expect(text).toContain('7 seats');
        expect(text).toContain('Diesel');
        expect(text).toContain('Automatic');
        expect(text).toContain('Jaipur Central, Jaipur');
        expect(q(el, '.rate').textContent).toMatch(/4,200/);
        expect(q(el, 'c-vehicle-photo').alt).toBe('Toyota Innova Crysta photo');
        expect(q(el, '[data-id="total"]')).toBeNull();
    });

    it('shows the trip total for the selected number of days', async () => {
        const el = render({ vehicle: VEHICLE, totalPrice: 14868, days: 3 });
        await flush();
        expect(q(el, '[data-id="total"]').textContent).toMatch(/14,868(\.00)? total for 3 days/);
        el.days = 1;
        await flush();
        expect(q(el, '[data-id="total"]').textContent).toMatch(/for 1 day$/);
    });

    it('falls back to the quote on the vehicle and a generic title', async () => {
        const el = render({ vehicle: { id: 'a0V2', total: 5000, days: 2 } });
        await flush();
        expect(q(el, '.title').textContent).toBe('Vehicle');
        expect(q(el, '[data-id="total"]').textContent).toMatch(/5,000(\.00)? total for 2 days/);
    });

    it('handles a missing vehicle without crashing', async () => {
        const el = render({});
        await flush();
        expect(q(el, '.title').textContent).toBe('Vehicle');
    });

    it('fires select with the vehicle id', async () => {
        const el = render({ vehicle: VEHICLE });
        const handler = jest.fn();
        el.addEventListener('select', handler);
        await flush();
        q(el, 'lightning-button').click();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ vehicleId: 'a0V1' });
    });
});
