import { createElement } from "lwc";
import SiteNotFound from "c/siteNotFound";

jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rentals" }),
  { virtual: true }
);

describe("c-site-not-found", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("explains the problem and links back to search and home (issue #6)", () => {
    const el = createElement("c-site-not-found", { is: SiteNotFound });
    document.body.appendChild(el);
    expect(el.shadowRoot.querySelector('[data-id="heading"]').textContent).toBe(
      "We couldn't find that page"
    );
    const search = el.shadowRoot.querySelector('[data-id="search"]');
    expect(search.textContent).toBe("Back to search");
    expect(search.getAttribute("href")).toBe("/rentals/fleet");
    expect(
      el.shadowRoot.querySelector('[data-id="home"]').getAttribute("href")
    ).toBe("/rentals/");
  });
});
