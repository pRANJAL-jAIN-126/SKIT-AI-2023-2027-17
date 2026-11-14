/**
 * Shared UI helpers for the Smart Car Rental components.
 * UI-only: formatting, error reduction, URL/state helpers and timers.
 * No business rules live here.
 */

const TIME_ZONE = 'Asia/Kolkata';
const GENERIC_ERROR = 'Something went wrong. Please try again.';

const dateTimeFormatter = new Intl.DateTimeFormat('en-IN', {
    timeZone: TIME_ZONE,
    dateStyle: 'medium',
    timeStyle: 'short'
});

const dateFormatter = new Intl.DateTimeFormat('en-IN', {
    timeZone: TIME_ZONE,
    dateStyle: 'medium'
});

const moneyFormatter = new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR'
});

function toDate(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const d = value instanceof Date ? value : new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
}

/** Formats a date-time (ISO string / Date / epoch) in Asia/Kolkata. */
export function formatDateTime(value) {
    const d = toDate(value);
    return d ? dateTimeFormatter.format(d) : '';
}

/** Formats a date-only value (e.g. '1990-05-01') without time-zone drift. */
export function formatDate(value) {
    if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
        // Anchor to midday UTC so the calendar day is stable in IST.
        return dateFormatter.format(new Date(`${value}T12:00:00Z`));
    }
    const d = toDate(value);
    return d ? dateFormatter.format(d) : '';
}

/** Formats a number as INR currency. Empty string for null/undefined. */
export function formatMoney(value) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    const n = Number(value);
    return Number.isNaN(n) ? '' : moneyFormatter.format(n);
}

/**
 * Reduces an Apex / LDS / JS error to a single user-safe message.
 * Never returns stack traces.
 */
export function reduceError(error, fallback = GENERIC_ERROR) {
    if (!error) {
        return fallback;
    }
    if (Array.isArray(error)) {
        const msgs = error.map((e) => reduceError(e, '')).filter(Boolean);
        return msgs.length ? msgs.join(', ') : fallback;
    }
    if (typeof error === 'string') {
        return error;
    }
    const body = error.body;
    if (body) {
        if (Array.isArray(body)) {
            const msgs = body.map((b) => b && b.message).filter(Boolean);
            if (msgs.length) {
                return msgs.join(', ');
            }
        } else if (typeof body.message === 'string' && body.message) {
            return body.message;
        } else if (body.pageErrors && body.pageErrors.length) {
            return body.pageErrors.map((p) => p.message).join(', ');
        }
    }
    if (typeof error.message === 'string' && error.message) {
        return error.message;
    }
    return fallback;
}

/** Normalises a datetime value to an ISO string, or null when invalid/empty. */
export function toIso(value) {
    const d = toDate(value);
    return d ? d.toISOString() : null;
}

/**
 * Returns an error message when the date range is not usable, otherwise null.
 * (UI convenience only – the server re-validates everything.)
 */
export function validateDateRange(start, end) {
    const s = toDate(start);
    const e = toDate(end);
    if (!s || !e) {
        return 'Choose both a pickup and a return date and time.';
    }
    if (e.getTime() <= s.getTime()) {
        return 'Return must be after pickup.';
    }
    return null;
}

/**
 * Reads a URL parameter from a CurrentPageReference (state) and falls back to
 * window.location.search so components work in any container.
 */
export function getUrlParam(pageRef, name) {
    const state = pageRef && pageRef.state;
    if (state && state[name] !== undefined && state[name] !== null && state[name] !== '') {
        return state[name];
    }
    try {
        const params = new URLSearchParams(window.location.search);
        const v = params.get(name);
        return v === null || v === '' ? null : v;
    } catch {
        return null;
    }
}

/**
 * Reads a date/time URL parameter as an ISO string, or null.
 * The page-reference state and the real query string are both tried and the first value that parses wins.
 * Needed because hand-typed links with unencoded ":" (e.g. ?start=2026-11-20T04:30:00.000Z) reach the LWR
 * page-reference state in a form that does not parse, while window.location still holds the correct value.
 */
export function getUrlDateParam(pageRef, name) {
    const candidates = [];
    const state = pageRef && pageRef.state;
    if (state && state[name] !== undefined && state[name] !== null && state[name] !== '') {
        candidates.push(state[name]);
    }
    try {
        const v = new URLSearchParams(window.location.search).get(name);
        if (v) {
            candidates.push(v);
        }
    } catch {
        // no window (tests / non-browser container)
    }
    for (const raw of candidates) {
        let value = raw;
        try {
            value = decodeURIComponent(String(raw));
        } catch {
            value = String(raw);
        }
        const iso = toIso(value);
        if (iso) {
            return iso;
        }
    }
    return null;
}

/** Builds a site-relative URL with encoded query parameters (null values skipped). */
export function buildUrl(base, path, params) {
    let url = `${base || ''}${path}`;
    if (params) {
        const parts = Object.keys(params)
            .filter((k) => params[k] !== null && params[k] !== undefined && params[k] !== '')
            .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`);
        if (parts.length) {
            url += `?${parts.join('&')}`;
        }
    }
    return url;
}

/** Full-page redirect (used for the external Stripe hosted checkout page). */
export function redirectTo(url) {
    window.location.assign(url);
}

/** Schedules fn after ms; returns a handle for cancelScheduled. */
export function schedule(fn, ms) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return setTimeout(fn, ms);
}

export function cancelScheduled(handle) {
    if (handle) {
        clearTimeout(handle);
    }
}

/**
 * Creates a debouncer: run(fn) postpones fn until `wait` ms have passed
 * without another call. cancel() drops the pending call.
 */
export function createDebouncer(wait = 400) {
    let handle = null;
    return {
        run(fn) {
            cancelScheduled(handle);
            handle = schedule(() => {
                handle = null;
                fn();
            }, wait);
        },
        cancel() {
            cancelScheduled(handle);
            handle = null;
        }
    };
}

/** Converts a value from a lightning-input to a number or null. */
export function toNumberOrNull(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const n = Number(value);
    return Number.isNaN(n) ? null : n;
}

/**
 * Message for a date/time field whose typed text cannot be parsed. The example date follows the user's locale,
 * which is the format lightning-input shows ("Nov 20, 2026" for en-US). The value sent to Apex is always ISO-8601.
 */
export function dateBadInputMessage(locale) {
    let example = 'Nov 20, 2026';
    try {
        example = new Intl.DateTimeFormat(locale || undefined, { dateStyle: 'medium', timeZone: 'UTC' }).format(
            new Date(Date.UTC(2026, 10, 20))
        );
    } catch {
        // keep the en-US example
    }
    return `Enter a date like ${example}, or pick one from the calendar.`;
}

const BUNDLED_IMAGE =/^[A-Za-z0-9][A-Za-z0-9_-]*(\/[A-Za-z0-9][A-Za-z0-9_-]*)*\.(jpe?g|png|webp|gif)$/i;

/**
 * Turns a Vehicle__c.Image_URL__c value into a URL the browser can load, or null when it is unusable.
 * - "tata-punch.jpg" (bare file name) -> file inside the VehicleImages static resource (resourceBase)
 * - "https://..." -> used as-is
 * - "/path" (site-relative) -> used as-is
 * Anything else (blank, "javascript:", "..", other schemes) returns null so callers show the fallback.
 */
export function resolveImageUrl(value, resourceBase) {
    const v = typeof value === 'string' ? value.trim() : '';
    if (!v || v.includes('..') || /[\s"'<>\\]/.test(v)) {
        return null;
    }
    if (/^https:\/\//i.test(v) || (v.startsWith('/') && !v.startsWith('//'))) {
        return v;
    }
    if (BUNDLED_IMAGE.test(v) && resourceBase) {
        return `${String(resourceBase).replace(/\/+$/, '')}/${v}`;
    }
    return null;
}

export const GENERIC_ERROR_MESSAGE = GENERIC_ERROR;