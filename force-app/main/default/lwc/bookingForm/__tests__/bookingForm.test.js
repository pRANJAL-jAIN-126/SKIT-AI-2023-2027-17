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
jest.mock("@salesforce/community/basePath", () => ({ default: "/s" }), {
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
