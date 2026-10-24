import { LightningElement, api } from 'lwc';
import chat from '@salesforce/apex/RentalAssistantController.chat';
import basePath from '@salesforce/community/basePath';
import { buildUrl, formatDateTime, formatMoney, reduceError } from 'c/rentalUtils';

const MAX_HISTORY = 20;
const WELCOME =
    'Hi! I can help you find a car, check a booking or explain our rental policies. Try "SUV in Jaipur from Friday 10am to Sunday 6pm".';

let seq = 0;
const nextId = () => `m${++seq}`;

export default class RentalAssistant extends LightningElement {
    /** Optional heading shown above the chat. */
    @api title = 'Rental Assistant';

    draft = '';
    isSending = false;
    errorMessage = null;
    messages = [{ id: nextId(), role: 'assistant', text: WELCOME, vehicles: [], links: [], booking: null }];
    history = [];

    _scrollPending = false;

    renderedCallback() {
        if (this._scrollPending) {
            this._scrollPending = false;
            const list = this.template.querySelector('[data-id="messages"]');
            if (list) {
                list.scrollTop = list.scrollHeight;
            }
        }
    }

    // ---------- derived ----------

    get viewMessages() {
        return this.messages.map((m) => {
            const isUser = m.role === 'user';
            return {
                ...m,
                rowClass: isUser ? 'row user' : 'row assistant',
                bubbleClass: isUser ? 'bubble user' : 'bubble assistant',
                srLabel: isUser ? 'You said' : 'Assistant said',
                hasVehicles: !!m.vehicles && m.vehicles.length > 0,
                hasLinks: !!m.links && m.links.length > 0,
                vehicleViews: (m.vehicles || []).map((v) => ({
                    key: `${m.id}-${v.id}`,
                    title: [v.make, v.model].filter(Boolean).join(' ') || v.name,
                    meta: [v.category, v.seats ? `${v.seats} seats` : null, v.fuelType, v.transmission, v.city]
                        .filter(Boolean)
                        .join(' · '),
                    rate: formatMoney(v.dailyRate),
                    total: v.total !== undefined && v.total !== null && v.days ? `${formatMoney(v.total)} for ${v.days} ${Number(v.days) === 1 ? 'day' : 'days'}` : '',
                    url: buildUrl(basePath, `/vehicle/${v.id}`)
                })),
                linkViews: (m.links || []).map((l, i) => ({ key: `${m.id}-l${i}`, label: l.label, url: l.url })),
                bookingView: m.booking
                    ? {
                          number: m.booking.bookingNumber,
                          vehicle: m.booking.vehicleName,
                          status: m.booking.status,
                          start: formatDateTime(m.booking.startDt),
                          end: formatDateTime(m.booking.endDt),
                          amount: formatMoney(m.booking.grandTotal)
                      }
                    : null
            };
        });
    }

    get sendDisabled() {
        return this.isSending || !this.draft || !this.draft.trim();
    }

    // ---------- handlers ----------

    handleInput(event) {
        this.draft = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    }

    handleKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    async handleSend() {
        const text = (this.draft || '').trim();
        if (!text || this.isSending) {
            return;
        }
        this.errorMessage = null;
        const historyJson = JSON.stringify(this.history.slice(-MAX_HISTORY));
        this.messages = [...this.messages, { id: nextId(), role: 'user', text, vehicles: [], links: [], booking: null }];
        this.draft = '';
        this.isSending = true;
        this._scrollPending = true;
        try {
            const res = (await chat({ message: text, historyJson })) || {};
            const reply = res.reply || 'Sorry, I did not catch that. Could you rephrase?';
            const vehicles = Array.isArray(res.vehicles) ? res.vehicles : [];
            this.messages = [
                ...this.messages,
                {
                    id: nextId(),
                    role: 'assistant',
                    text: reply,
                    intent: res.intent,
                    vehicles,
                    links: Array.isArray(res.links) ? res.links : [],
                    booking: res.booking || null
                }
            ];
            this.history = [...this.history, { role: 'user', text }, { role: 'assistant', text: reply }].slice(
                -MAX_HISTORY
            );
        } catch (error) {
            this.errorMessage = reduceError(error, 'The assistant is unavailable right now. Please try again.');
            this.history = [...this.history, { role: 'user', text }].slice(-MAX_HISTORY);
        } finally {
            this.isSending = false;
            this._scrollPending = true;
        }
    }
}