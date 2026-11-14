import { createElement } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import CarFleetSearch from "c/carFleetSearch";
import searchVehicles from "@salesforce/apex/PortalController.searchVehicles";

jest.mock(
  "@salesforce/apex/PortalController.searchVehicles",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rentals" }),
  {
    virtual: true
  }
);

const START = "2026-11-20T04:30:00.000Z";
const END = "2026-11-22T04:30:00.000Z";
const CARS = [
  {
    id: "a06000000000001AAA",
    make: "Tata",
    model: "Punch",
    dailyRate: 1600,
    days: 2,
    total: 3776,
    imageUrl: "tata-punch.jpg"
  }
];

const flush = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function field(el, name) {
  return el.shadowRoot.querySelector(`[data-field="${name}"]`);
}

function button(el, label) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );
}

/** Makes a lightning-input stub behave like the real one for validity. */
function setValidity(input, valid) {
  input.checkValidity = jest.fn(() => valid);
  input.reportValidity = jest.fn(() => valid);
}

async function renderWithDates() {
  const el = createElement("c-car-fleet-search", { is: CarFleetSearch });
  document.body.appendChild(el);
  CurrentPageReference.emit({
    type: "standard__namedPage",
    attributes: {},
    state: { start: START, end: END }
  });
  await flush();
  return el;
}

function change(input, value) {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

describe("c-car-fleet-search", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    searchVehicles.mockResolvedValue(CARS);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
    window.history.replaceState({}, "", "/");
  });

  it("prefills both dates from the URL and searches", async () => {
    const el = await renderWithDates();
    jest.runAllTimers();
    await flush();
    expect(field(el, "pickupDateTime").value).toBe(START);
    expect(field(el, "returnDateTime").value).toBe(END);
    expect(searchVehicles).toHaveBeenCalledTimes(1);
    expect(searchVehicles.mock.calls[0][0].request).toMatchObject({
      startDt: START,
      endDt: END
    });
  });

  it("keeps the pickup date when the page-reference state holds an unparseable value (issue #10)", async () => {
    window.history.replaceState({}, "", `/rentals/?start=${START}&end=${END}`);
    const el = createElement("c-car-fleet-search", { is: CarFleetSearch });
    document.body.appendChild(el);
    CurrentPageReference.emit({
      type: "standard__namedPage",
      attributes: {},
      state: { start: "2026-11-20T04", end: END }
    });
    await flush();
    expect(field(el, "pickupDateTime").value).toBe(START);
    expect(field(el, "returnDateTime").value).toBe(END);
  });

  it("does not search with an invalid seat count and shows a message (issue #4)", async () => {
    const el = await renderWithDates();
    jest.runAllTimers();
    await flush();
    searchVehicles.mockClear();

    const seats = field(el, "seats");
    setValidity(seats, false); // what lightning-input reports for "abc" / 0 / 2.5
    change(seats, "");
    jest.runAllTimers();
    await flush();

    expect(searchVehicles).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector('[data-id="filter-error"]').textContent
    ).toBe("Fix the highlighted filters to search.");
    expect(seats.reportValidity).toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("c-vehicle-card")).toBeNull(); // stale results are not shown as if filtered
  });

  it("blocks a negative max price on Search click (issue #4)", async () => {
    const el = await renderWithDates();
    jest.runAllTimers();
    await flush();
    searchVehicles.mockClear();

    const price = field(el, "maxDailyRate");
    setValidity(price, false);
    price.value = "-500";
    button(el, "Search").click();
    await flush();

    expect(searchVehicles).not.toHaveBeenCalled();
    expect(price.reportValidity).toHaveBeenCalled();
    expect(field(el, "maxDailyRate").min).toBe("1");
  });

  it("searches again once the invalid filter is corrected", async () => {
    const el = await renderWithDates();
    jest.runAllTimers();
    await flush();
    const seats = field(el, "seats");
    setValidity(seats, false);
    change(seats, "");
    jest.runAllTimers();
    await flush();
    searchVehicles.mockClear();

    setValidity(seats, true);
    change(seats, "7");
    jest.runAllTimers();
    await flush();

    expect(searchVehicles).toHaveBeenCalledTimes(1);
    expect(searchVehicles.mock.calls[0][0].request.minSeats).toBe(7);
    expect(el.shadowRoot.querySelector('[data-id="filter-error"]')).toBeNull();
  });

  it("Clear filters resets every criterion, typed text, messages and results (issue #3)", async () => {
    const el = await renderWithDates();
    jest.runAllTimers();
    await flush();
    expect(el.shadowRoot.querySelectorAll("c-vehicle-card")).toHaveLength(1);

    change(el.shadowRoot.querySelector('[data-field="category"]'), "SUV");
    change(el.shadowRoot.querySelector('[data-field="branchCity"]'), "Delhi");
    const seats = field(el, "seats");
    setValidity(seats, false);
    seats.value = "abc"; // text the browser cannot parse: our state stays null
    button(el, "Search").click();
    await flush();
    expect(
      el.shadowRoot.querySelector('[data-id="filter-error"]')
    ).not.toBeNull();

    setValidity(seats, true);
    seats.setCustomValidity = jest.fn();
    searchVehicles.mockClear();
    button(el, "Clear filters").click();
    await flush();
    jest.runAllTimers();
    await flush();

    expect(field(el, "pickupDateTime").value).toBeNull();
    expect(field(el, "returnDateTime").value).toBeNull();
    expect(el.shadowRoot.querySelector('[data-field="branchCity"]').value).toBe(
      ""
    );
    expect(el.shadowRoot.querySelector('[data-field="category"]').value).toBe(
      ""
    );
    expect(seats.value).toBeNull();
    expect(seats.setCustomValidity).toHaveBeenCalledWith("");
    expect(seats.reportValidity).toHaveBeenCalled(); // clears the red message
    expect(field(el, "maxDailyRate").value).toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="filter-error"]')).toBeNull();
    expect(el.shadowRoot.querySelectorAll("c-vehicle-card")).toHaveLength(0);
    expect(
      el.shadowRoot.querySelector('[data-id="date-prompt"]')
    ).not.toBeNull();
    expect(searchVehicles).not.toHaveBeenCalled();
  });

  it("Clear filters restores the configured default city", async () => {
    const el = createElement("c-car-fleet-search", { is: CarFleetSearch });
    el.defaultCity = "Jaipur";
    document.body.appendChild(el);
    change(el.shadowRoot.querySelector('[data-field="branchCity"]'), "Delhi");
    await flush(); // the browser re-renders between the customer's choice and the click
    expect(el.shadowRoot.querySelector('[data-field="branchCity"]').value).toBe(
      "Delhi"
    );
    button(el, "Clear filters").click();
    await flush();
    expect(el.shadowRoot.querySelector('[data-field="branchCity"]').value).toBe(
      "Jaipur"
    );
  });

  it("shows a clear, locale-based message for unparseable typed dates (issue #8)", async () => {
    const el = await renderWithDates();
    expect(field(el, "pickupDateTime").messageWhenBadInput).toBe(
      "Enter a date like Nov 20, 2026, or pick one from the calendar."
    );
    expect(field(el, "returnDateTime").messageWhenValueMissing).toBe(
      "Choose a return date and time."
    );
  });

  it("collapses secondary filters behind a toggle that reports active filters", async () => {
    const el = await renderWithDates();
    const category = el.shadowRoot.querySelector('[data-field="category"]');
    expect(category.className).toContain("extra-collapsed");
    change(category, "SUV");
    await flush();
    const toggle = el.shadowRoot.querySelector('[data-id="more-filters"]');
    expect(toggle.label).toBe("More filters (1 active)");
    toggle.click();
    await flush();
    expect(category.className).not.toContain("extra-collapsed");
    expect(toggle.label).toBe("Fewer filters");
  });
});
