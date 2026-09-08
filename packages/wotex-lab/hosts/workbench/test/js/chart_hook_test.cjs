const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

class Element {
  constructor() { this.hidden = false; this.children = []; this.events = new Map(); }
  appendChild(child) { this.children.push(child); child.parent = this; }
  replaceChildren() { this.children = []; }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((child) => child !== this); }
  addEventListener(name, fn) { this.events.set(name, fn); }
  removeEventListener(name) { this.events.delete(name); }
  setAttribute(name) { if (name === "hidden") this.hidden = true; }
  removeAttribute(name) { if (name === "hidden") this.hidden = false; }
}

function setup(embed) {
  const svg = new Element();
  const target = new Element();
  const reset = new Element();
  const element = new Element();
  element.dataset = {spec: JSON.stringify({mark: {type: "line"}, data: {values: []}})};
  element.querySelector = (selector) => ({".wl-chart-svg": svg, ".wl-chart-enhanced": target, "[data-chart-reset]": reset})[selector];
  element.closest = () => element;
  const media = new Element();
  let hooks;
  const context = {
    window: {
      vegaEmbed: embed, Phoenix: {Socket: class {}}, matchMedia: () => media,
      LiveView: {LiveSocket: class {constructor(_url, _socket, options) { hooks = options.hooks; } connect() {}}}
    },
    document: {querySelector: () => ({getAttribute: () => "test-csrf"}), createElement: () => new Element()},
    getComputedStyle: () => ({getPropertyValue: () => "#123456"}),
    MutationObserver: class {observe() {} disconnect() { this.disconnected = true; }}
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../../priv/static/js/app.js"), "utf8"), context);
  const hook = Object.assign({el: element}, hooks.WotexChart);
  hook.mounted();
  return {hook, svg, target, reset, media, element};
}

const flush = () => new Promise(setImmediate);
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
};

test("uses the LiveView element, the CSP interpreter and a closed local zoom", async () => {
  let finalized = 0;
  let options;
  const state = setup((_element, spec, opts) => {
    options = opts;
    assert.equal(spec.params[0].bind, "scales");
    assert.equal(spec.params[0].select.encodings[0], "x");
    return Promise.resolve({finalize() { finalized++; }});
  });
  await flush();
  assert.equal(options.ast, true);
  assert.equal(options.defaultStyle, false);
  assert.equal(options.actions, false);
  await assert.rejects(options.loader.load("https://example.test"));
  await assert.rejects(options.loader.sanitize("https://example.test"));
  assert.equal(state.svg.hidden, true);
  assert.equal(state.target.hidden, false);
  state.reset.events.get("click")();
  await flush();
  assert.equal(finalized, 1);
  state.hook.destroyed();
  assert.equal(finalized, 2);
  assert.equal(state.media.events.size, 0);
  assert.equal(state.reset.events.size, 0);
  assert.equal(state.hook.themeObserver.disconnected, true);
});

test("superseded async results are finalized and cannot replace the new chart", async () => {
  const first = deferred();
  const second = deferred();
  let calls = 0, staleFinalized = 0, activeFinalized = 0;
  const state = setup(() => (++calls === 1 ? first.promise : second.promise));
  state.hook.updated();
  second.resolve({finalize() { activeFinalized++; }});
  await flush();
  first.resolve({finalize() { staleFinalized++; }});
  await flush();
  assert.equal(staleFinalized, 1);
  assert.equal(activeFinalized, 0);
  assert.equal(state.target.children.length, 1);
  assert.equal(state.svg.hidden, true);
  state.hook.destroyed();
  assert.equal(activeFinalized, 1);
});

test("destruction during rendering disposes late views", async () => {
  const work = deferred();
  let finalized = 0;
  const state = setup(() => work.promise);
  state.hook.destroyed();
  work.resolve({finalize() { finalized++; }});
  await flush();
  assert.equal(finalized, 1);
  assert.equal(state.svg.hidden, false);
});

test("failed or unavailable enhancement leaves the accessible fallback visible", async () => {
  const state = setup(() => Promise.reject(new Error("renderer failed")));
  await flush();
  assert.equal(state.svg.hidden, false);
  assert.equal(state.target.hidden, true);
  assert.equal(state.target.children.length, 0);
  state.element.dataset.spec = "invalid JSON";
  state.hook.updated();
  assert.equal(state.svg.hidden, false);
  state.hook.destroyed();
  const absent = setup(undefined);
  assert.equal(absent.svg.hidden, false);
  absent.hook.destroyed();
});

test("an obsolete rejection cannot hide the latest successful render", async () => {
  const old = deferred();
  let calls = 0;
  const state = setup(() => (++calls === 1 ? old.promise : Promise.resolve({finalize() {}})));
  state.hook.updated();
  await flush();
  old.reject(new Error("obsolete"));
  await flush();
  assert.equal(state.svg.hidden, true);
  assert.equal(state.target.hidden, false);
  state.hook.destroyed();
});
