import { createElement } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import BookingForm from "c/bookingForm";
import getVehicleDetail from "@salesforce/apex/PortalController.getVehicleDetail";
import getCustomerProfile from "@salesforce/apex/PortalController.getCustomerProfile";

jest.mock(
  "@salesforce/apex/PortalController.getVehicleDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalController.getCustomerProfile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalController.createHold",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalController.startCheckout",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/community/basePath", () => ({ __esModule: true, default: "/s" }), {
  virtual: true
});

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-booking-form licence validity", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function renderWithExpiry(licenseExpiry) {
    getCustomerProfile.mockResolvedValue({
      isGuest: false,
      kycStatus: "Verified",
      licenseExpiry
    });
    getVehicleDetail.mockResolvedValue({
      id: "a01000000000001AAA",
      days: 2,
      grandTotal: 10000
    });

    const element = createElement("c-booking-form", { is: BookingForm });
    element.vehicleId = "a01000000000001AAA";
    document.body.appendChild(element);
    CurrentPageReference.emit({
      attributes: {},
      state: {
        start: "2030-01-01T10:00:00.000Z",
        end: "2030-01-03T10:00:00.000Z"
      }
    });
    await flushPromises();
    await flushPromises();
    return element;
  }

  it("sends a verified customer to licence verification when expiry is on the return date", async () => {
    const element = await renderWithExpiry("2030-01-03");

    expect(
      element.shadowRoot.querySelector('[data-id="book-button"]').label
    ).toBe("Book and verify licence");
    expect(
      element.shadowRoot.querySelector('[data-id="kyc-notice"]').textContent
    ).toContain("Expires before return");
  });

  it("allows checkout when the licence remains valid beyond the return date", async () => {
    const element = await renderWithExpiry("2030-01-04");

    expect(
      element.shadowRoot.querySelector('[data-id="book-button"]').label
    ).toBe("Book and pay");
    expect(
      element.shadowRoot.querySelector('[data-id="kyc-notice"]')
    ).toBeNull();
  });
});

describe("c-booking-form photo and unavailable car", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function render(vehicleResult) {
    getCustomerProfile.mockResolvedValue({ isGuest: true });
    if (vehicleResult instanceof Error) {
      getVehicleDetail.mockRejectedValue({ body: { message: vehicleResult.message } });
    } else {
      getVehicleDetail.mockResolvedValue(vehicleResult);
    }
    const element = createElement("c-booking-form", { is: BookingForm });
    element.vehicleId = "a06000000000001AAA";
    document.body.appendChild(element);
    CurrentPageReference.emit({
      attributes: {},
      state: { start: "2030-01-01T10:00:00.000Z", end: "2030-01-03T10:00:00.000Z" }
    });
    await flushPromises();
    await flushPromises();
    return element;
  }

  it("renders the vehicle photo through c-vehicle-photo, never a raw <img> (issue #2)", async () => {
    const element = await render({ id: "a06000000000001AAA", make: "Tata", model: "Punch", imageUrl: "tata-punch.jpg" });
    const photo = element.shadowRoot.querySelector("c-vehicle-photo");
    expect(photo.src).toBe("tata-punch.jpg");
    expect(photo.alt).toBe("Tata Punch photo");
    expect(photo.variant).toBe("hero");
    expect(element.shadowRoot.querySelector("img")).toBeNull();
  });

  it("still renders c-vehicle-photo (placeholder) when the car has no image", async () => {
    const element = await render({ id: "a06000000000001AAA", make: "Kia", model: "Carens", imageUrl: null });
    expect(element.shadowRoot.querySelector("c-vehicle-photo")).not.toBeNull();
  });

  it("shows a useful unknown-car message with Back to search that keeps the dates (issue #6)", async () => {
    const element = await render(new Error("This vehicle is not available."));
    const box = element.shadowRoot.querySelector('[data-id="load-error"]');
    expect(box.textContent).toContain("Car not available");
    expect(box.textContent).toContain("This vehicle is not available.");
    const back = element.shadowRoot.querySelector('[data-id="back-to-search"]');
    expect(back.textContent).toBe("Back to search");
    expect(back.getAttribute("href")).toBe(
      "/s/fleet?start=2030-01-01T10%3A00%3A00.000Z&end=2030-01-03T10%3A00%3A00.000Z"
    );
  });

  it("offers only log in to guests (self-registration is not enabled on the site)", async () => {
    const element = await render({ id: "a06000000000001AAA", make: "Tata", model: "Punch", days: 2, grandTotal: 5776 });
    element.shadowRoot.querySelector('[data-id="book-button"]').click();
    await flushPromises();
    const prompt = element.shadowRoot.querySelector('[data-id="login-prompt"]');
    expect(prompt.textContent).toContain("Please log in to book this car.");
    expect(prompt.textContent).not.toContain("create an account");
  });
});
