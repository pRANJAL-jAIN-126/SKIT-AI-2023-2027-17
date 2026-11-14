import { createElement } from "lwc";
import SiteHeader from "c/siteHeader";

jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rentals" }),
  { virtual: true }
);
// Logged-in customer.
jest.mock(
  "@salesforce/user/isGuest",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);

describe("c-site-header (logged-in customer)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows My bookings, Assistant and Log out, and no Log in / admin links", () => {
    const el = createElement("c-site-header", { is: SiteHeader });
    document.body.appendChild(el);
    const labels = [...el.shadowRoot.querySelectorAll("nav .links a")].map(
      (a) => a.textContent
    );
    expect(labels).toEqual(["Home", "Search cars", "My bookings", "Assistant"]);
    expect(
      el.shadowRoot.querySelector('[data-id="bookings"]').getAttribute("href")
    ).toBe("/rentals/my-bookings");
    expect(
      el.shadowRoot.querySelector('[data-id="logout"]').getAttribute("href")
    ).toBe("/rentals/secur/logout.jsp?retUrl=%2Frentals%2F");
    expect(el.shadowRoot.querySelector('[data-id="login"]')).toBeNull();
    expect(el.shadowRoot.textContent).not.toMatch(
      /admin|inspection|dashboard|setup/i
    );
  });
});
