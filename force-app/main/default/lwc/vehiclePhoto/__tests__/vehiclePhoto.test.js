import { createElement } from "lwc";
import VehiclePhoto from "c/vehiclePhoto";
import CREDITS from "../credits";

const flush = () => Promise.resolve();

function render(props) {
  const el = createElement("c-vehicle-photo", { is: VehiclePhoto });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

const img = (el) => el.shadowRoot.querySelector('[data-id="photo"]');
const placeholder = (el) =>
  el.shadowRoot.querySelector('[data-id="placeholder"]');

describe("c-vehicle-photo", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("loads a bundled photo from the VehicleImages static resource", () => {
    const el = render({ src: "tata-punch.jpg", alt: "Tata Punch photo" });
    const photo = img(el);
    expect(photo).not.toBeNull();
    expect(photo.getAttribute("src")).toMatch(
      /VehicleImages\/tata-punch\.jpg$/
    );
    expect(photo.alt).toBe("Tata Punch photo");
    expect(photo.getAttribute("loading")).toBe("lazy");
    expect(placeholder(el)).toBeNull();
  });

  const SCRIPT_URL = ["javascript", "alert(1)"].join(":");

  it.each([[null], [""], [SCRIPT_URL], ["http://insecure.example.com/x.jpg"]])(
    "shows the placeholder (no <img>) for missing or invalid src %p",
    (src) => {
      const el = render({ src, alt: "Kia Carens photo" });
      expect(img(el)).toBeNull();
      expect(placeholder(el).getAttribute("aria-label")).toBe(
        "Kia Carens photo"
      );
    }
  );

  it("swaps a failing image for the placeholder instead of a broken-image icon", async () => {
    const el = render({ src: "https://cdn.example.com/missing.jpg" });
    img(el).dispatchEvent(new CustomEvent("error"));
    await flush();
    expect(img(el)).toBeNull();
    expect(placeholder(el)).not.toBeNull();
  });

  it("gives a new src a fresh chance after a failure", async () => {
    const el = render({ src: "https://cdn.example.com/missing.jpg" });
    img(el).dispatchEvent(new CustomEvent("error"));
    await flush();
    el.src = "honda-city.jpg";
    await flush();
    expect(img(el).getAttribute("src")).toMatch(/honda-city\.jpg$/);
  });

  it("shows the licence credit on the hero variant only", async () => {
    const hero = render({ src: "kia-sonet.jpg", variant: "hero" });
    const credit = hero.shadowRoot.querySelector('[data-id="credit"]');
    expect(credit.textContent).toBe(
      `Photo: ${CREDITS["kia-sonet.jpg"].author} / ${CREDITS["kia-sonet.jpg"].license}`
    );
    expect(credit.querySelector("a").href).toBe(
      CREDITS["kia-sonet.jpg"].source
    );
    expect(img(hero).getAttribute("loading")).toBe("eager");

    const card = render({ src: "kia-sonet.jpg", variant: "card" });
    expect(card.shadowRoot.querySelector('[data-id="credit"]')).toBeNull();
  });
});

describe("vehicle photo credits", () => {
  it("has author, licence and Commons source for every bundled photo", () => {
    const files = Object.keys(CREDITS);
    expect(files).toHaveLength(20);
    files.forEach((file) => {
      const c = CREDITS[file];
      expect(file).toMatch(/^[a-z0-9-]+\.jpg$/);
      expect(c.author).toBeTruthy();
      expect(c.license).toMatch(/^(CC0|Public domain|CC BY(-SA)? \d\.\d)$/);
      expect(c.source).toMatch(
        /^https:\/\/commons\.wikimedia\.org\/wiki\/File:/
      );
    });
  });
});
