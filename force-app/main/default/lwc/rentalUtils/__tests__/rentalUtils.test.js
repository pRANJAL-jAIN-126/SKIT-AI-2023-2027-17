import {
  dateBadInputMessage,
  getUrlDateParam,
  resolveImageUrl
} from "c/rentalUtils";

describe("resolveImageUrl", () => {
  const BASE = "/rentals/resource/1700000000000/VehicleImages";

  it("maps a bare file name into the VehicleImages static resource", () => {
    expect(resolveImageUrl("tata-punch.jpg", BASE)).toBe(
      `${BASE}/tata-punch.jpg`
    );
    expect(resolveImageUrl("  kia-carens.JPG ", `${BASE}/`)).toBe(
      `${BASE}/kia-carens.JPG`
    );
  });

  it("keeps https and site-relative URLs", () => {
    expect(resolveImageUrl("https://cdn.example.com/a.jpg", BASE)).toBe(
      "https://cdn.example.com/a.jpg"
    );
    expect(
      resolveImageUrl("/sfc/servlet.shepherd/version/download/068xx", BASE)
    ).toBe("/sfc/servlet.shepherd/version/download/068xx");
  });

  it.each([
    [null],
    [undefined],
    [""],
    ["   "],
    [["javascript", "alert(1)"].join(":")],
    ["data:image/png;base64,AAAA"],
    ["http://insecure.example.com/a.jpg"],
    ["//evil.example.com/a.jpg"],
    ["../secret.jpg"],
    ["folder/../../x.jpg"],
    ["photo.exe"],
    ['a" onerror="x.jpg'],
    [42]
  ])("returns null for unusable value %p so the fallback is shown", (value) => {
    expect(resolveImageUrl(value, BASE)).toBeNull();
  });

  it("returns null for a bundled name when no resource base is available", () => {
    expect(resolveImageUrl("tata-punch.jpg", "")).toBeNull();
  });
});

describe("getUrlDateParam", () => {
  afterEach(() => {
    window.history.replaceState({}, "", "/");
  });

  it("reads an ISO value from page-reference state", () => {
    expect(
      getUrlDateParam({ state: { start: "2026-11-20T04:30:00.000Z" } }, "start")
    ).toBe("2026-11-20T04:30:00.000Z");
  });

  it("decodes a percent-encoded state value", () => {
    expect(
      getUrlDateParam(
        { state: { start: "2026-11-20T04%3A30%3A00.000Z" } },
        "start"
      )
    ).toBe("2026-11-20T04:30:00.000Z");
  });

  it("falls back to the real query string when the state value does not parse (issue #10)", () => {
    window.history.replaceState(
      {},
      "",
      "/rentals/?start=2026-11-20T04:30:00.000Z&end=2026-11-22T04:30:00.000Z"
    );
    const pageRef = {
      state: { start: "2026-11-20T04", end: "2026-11-22T04:30:00.000Z" }
    };
    expect(getUrlDateParam(pageRef, "start")).toBe("2026-11-20T04:30:00.000Z");
    expect(getUrlDateParam(pageRef, "end")).toBe("2026-11-22T04:30:00.000Z");
  });

  it("returns null when neither source has a usable date", () => {
    window.history.replaceState({}, "", "/rentals/?start=not-a-date");
    expect(
      getUrlDateParam({ state: { start: "garbage" } }, "start")
    ).toBeNull();
    expect(getUrlDateParam(null, "end")).toBeNull();
  });
});

describe("dateBadInputMessage", () => {
  it("gives an example in the user's locale format", () => {
    expect(dateBadInputMessage("en-US")).toBe(
      "Enter a date like Nov 20, 2026, or pick one from the calendar."
    );
  });

  it("still returns a usable message for an unknown locale", () => {
    expect(dateBadInputMessage("not_a_locale")).toMatch(
      /^Enter a date like .+, or pick one from the calendar\.$/
    );
  });
});
