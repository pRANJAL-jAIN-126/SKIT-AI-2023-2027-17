import { LightningElement, api } from "lwc";
import basePath from "@salesforce/community/basePath";
import isGuest from "@salesforce/user/isGuest";
import { buildUrl } from "c/rentalUtils";

/**
 * Customer-facing site header for the Smart Car Rental portal (Experience Builder: Theme Header region).
 * Guests see Home / Search cars / Log in (and Sign up only when self-registration is switched on).
 * Logged-in customers see Home / Search cars / My bookings / Assistant / Log out.
 * There are deliberately no staff or admin links here.
 */
export default class SiteHeader extends LightningElement {
  /** Brand text next to the logo mark. */
  @api brandName = "Smart Car Rental";
  /** Show "Sign up" for guests. Leave off until self-registration is enabled for the site. */
  @api showSignUp = false;

  menuOpen = false;

  get isGuest() {
    return isGuest;
  }

  url(path, params) {
    return buildUrl(basePath, path, params);
  }

  currentPath() {
    try {
      const path = window.location.pathname || "";
      const rel =
        basePath && path.startsWith(basePath)
          ? path.slice(basePath.length)
          : path;
      return rel.replace(/\/+$/, "") || "/";
    } catch {
      return "/";
    }
  }

  link(key, label, path, match) {
    const here = this.currentPath();
    const active = match ? match.test(here) : here === path;
    return {
      key,
      label,
      href: this.url(path),
      className: active ? "nav-link active" : "nav-link",
      ariaCurrent: active ? "page" : null
    };
  }

  get homeUrl() {
    return this.url("/");
  }

  get links() {
    const links = [
      this.link("home", "Home", "/"),
      this.link("fleet", "Search cars", "/fleet", /^\/(fleet|vehicle)(\/|$)/)
    ];
    if (!this.isGuest) {
      links.push(
        this.link(
          "bookings",
          "My bookings",
          "/my-bookings",
          /^\/(my-bookings|payment-result|verify)(\/|$)/
        )
      );
      links.push(this.link("assistant", "Assistant", "/assistant"));
    }
    return links;
  }

  get loginUrl() {
    let startUrl = null;
    try {
      const here = `${window.location.pathname}${window.location.search}`;
      startUrl = /\/login(\/|$|\?)/.test(here) ? null : here;
    } catch {
      startUrl = null;
    }
    return this.url("/login", { startURL: startUrl });
  }

  get signUpUrl() {
    return this.url("/SelfRegister");
  }

  get showSignUpLink() {
    return this.isGuest && this.showSignUp;
  }

  get logoutUrl() {
    return this.url("/secur/logout.jsp", { retUrl: `${basePath || ""}/` });
  }

  get menuClass() {
    return this.menuOpen ? "menu open" : "menu";
  }

  get menuExpanded() {
    return this.menuOpen ? "true" : "false";
  }

  get menuIcon() {
    return this.menuOpen ? "utility:close" : "utility:rows";
  }

  get menuToggleLabel() {
    return this.menuOpen ? "Close menu" : "Open menu";
  }

  handleToggleMenu() {
    this.menuOpen = !this.menuOpen;
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.menuOpen) {
      this.menuOpen = false;
      const toggle = this.template.querySelector('[data-id="menu-toggle"]');
      if (toggle) {
        toggle.focus();
      }
    }
  }
}
