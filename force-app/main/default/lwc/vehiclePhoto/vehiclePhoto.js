import { LightningElement, api } from "lwc";
import VEHICLE_IMAGES from "@salesforce/resourceUrl/VehicleImages";
import { resolveImageUrl } from "c/rentalUtils";
import CREDITS from "./credits";

/**
 * Single place that renders a vehicle photo for cards and the detail page.
 * Missing, invalid or failing image URLs always fall back to a styled placeholder (never a broken-image icon).
 */
export default class VehiclePhoto extends LightningElement {
  /** Raw Vehicle__c.Image_URL__c value: bundled file name (e.g. tata-punch.jpg), https URL, or site-relative path. */
  @api
  get src() {
    return this._src;
  }
  set src(value) {
    this._src = value;
    this.failed = false; // a new source gets a fresh chance to load
  }

  /** Accessible description, e.g. "Tata Punch photo". */
  @api alt = "Vehicle photo";

  /** 'card' (lazy-loaded, no caption) or 'hero' (eager, shows the licence credit). */
  @api variant = "card";

  _src;
  failed = false;

  get resolvedUrl() {
    return resolveImageUrl(this._src, VEHICLE_IMAGES);
  }

  get showImage() {
    return !!this.resolvedUrl && !this.failed;
  }

  get loadingMode() {
    return this.variant === "hero" ? "eager" : "lazy";
  }

  get frameClass() {
    return `frame ${this.variant === "hero" ? "hero" : "card"}`;
  }

  get credit() {
    const v = typeof this._src === "string" ? this._src.trim() : "";
    return CREDITS[v] || null;
  }

  get creditLabel() {
    const c = this.credit;
    return c ? `Photo: ${c.author} / ${c.license}` : "";
  }

  get showCredit() {
    return this.variant === "hero" && this.showImage && !!this.credit;
  }

  handleError() {
    this.failed = true;
  }
}
