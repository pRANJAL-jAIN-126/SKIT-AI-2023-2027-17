import { LightningElement, api } from "lwc";
import basePath from "@salesforce/community/basePath";
import { buildUrl } from "c/rentalUtils";

/** Friendly "page not found" content for the site's Error page, with ways back into the booking flow. */
export default class SiteNotFound extends LightningElement {
  @api heading = "We couldn't find that page";
  @api message =
    "The link may be out of date or mistyped. You can search for a car or go back to the home page.";

  get searchUrl() {
    return buildUrl(basePath, "/fleet");
  }

  get homeUrl() {
    return buildUrl(basePath, "/");
  }
}
