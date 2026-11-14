import { createElement } from "lwc";
import SiteHeader from "c/siteHeader";

jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rentals" }),
  { virtual: true }
);
// Guest visitor. The logged-in variant lives in siteHeader.member.test.js (the import is captured at load time).
jest.mock(
  "@salesforce/user/isGuest",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);

const flush = () => Promise.resolve();

function render(props = {}) {
  const el = createElement("c-site-header", { is: SiteHeader });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

const linkLabels = (el) =>
  [...el.shadowRoot.querySelectorAll("nav .links a")].map((a) => a.textContent);
const q = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

describe("c-site-header (guest)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    window.history.replaceState({}, "", "/");
  });

  it("shows Home, Search cars and Log in, but no customer-only or admin links", () => {
    const el = render();
    expect(linkLabels(el)).toEqual(["Home", "Search cars"]);
    expect(q(el, "home").getAttribute("href")).toBe("/rentals/");
    expect(q(el, "fleet").getAttribute("href")).toBe("/rentals/fleet");
    expect(q(el, "login").textContent).toBe("Log in");
    expect(q(el, "logout")).toBeNull();
    expect(q(el, "signup")).toBeNull(); // self-registration is off by default
    expect(el.shadowRoot.textContent).not.toMatch(
      /admin|inspection|dashboard|setup/i
    );
  });

  it("returns the guest to the current page after logging in", () => {
    window.history.replaceState(
      {},
      "",
      "/rentals/vehicle/a06000000000001AAA?start=2026-11-20"
    );
    const el = render();
    const href = q(el, "login").getAttribute("href");
    expect(href.startsWith("/rentals/login?startURL=")).toBe(true);
    expect(decodeURIComponent(href.split("startURL=")[1])).toBe(
      "/rentals/vehicle/a06000000000001AAA?start=2026-11-20"
    );
  });

  it("shows Sign up only when enabled", () => {
    const el = render({ showSignUp: true });
    expect(q(el, "signup").getAttribute("href")).toBe("/rentals/SelfRegister");
  });

  it("marks the current section as active", () => {
    window.history.replaceState({}, "", "/rentals/vehicle/a06000000000001AAA");
    const el = render();
    const fleet = q(el, "fleet");
    expect(fleet.getAttribute("aria-current")).toBe("page");
    expect(fleet.className).toContain("active");
    expect(q(el, "home").getAttribute("aria-current")).toBeNull();
  });

  it("opens and closes the mobile menu, and Escape closes it", async () => {
    const el = render();
    const toggle = q(el, "menu-toggle");
    const nav = el.shadowRoot.querySelector("nav");
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    toggle.click();
    await flush();
    expect(toggle.getAttribute("aria-expanded")).toBe("true");
    expect(nav.className).toBe("menu open");
    el.shadowRoot
      .querySelector("header")
      .dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await flush();
    expect(nav.className).toBe("menu");
  });
});
