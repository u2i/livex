var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// js/livex/index.js
var livex_exports = {};
__export(livex_exports, {
  enhanceLiveSocket: () => enhanceLiveSocket
});
module.exports = __toCommonJS(livex_exports);

// js/livex/livex_url.js
function safeEncode(str) {
  return encodeURIComponent(str).replace(/%5B/g, "[").replace(/%5D/g, "]");
}
function buildUrl(route, attrs) {
  let url = route;
  const remaining = {};
  Object.entries(attrs).forEach(([key, val]) => {
    const varPattern = new RegExp(`:${key}(?=/|$)`, "g");
    if (varPattern.test(url)) {
      url = url.replace(varPattern, encodeURIComponent(String(val)));
    } else {
      remaining[key] = val;
    }
  });
  const parts = [];
  function serialize(obj, prefix) {
    if (obj == null)
      return;
    if (typeof obj === "object" && !Array.isArray(obj)) {
      Object.entries(obj).forEach(([k, v]) => serialize(v, `${prefix}[${k}]`));
    } else if (Array.isArray(obj)) {
      obj.forEach((v, i) => serialize(v, `${prefix}[${i}]`));
    } else {
      parts.push(`${safeEncode(prefix)}=${encodeURIComponent(String(obj))}`);
    }
  }
  Object.entries(remaining).forEach(([key, value]) => serialize(value, key));
  return parts.length ? `${url}?${parts.join("&")}` : url;
}
function buildLvPageUrls() {
  const pageEl = document.getElementById("lv-page-params");
  if (!pageEl)
    throw new Error('Element with id "lv-page-params" not found.');
  const route = pageEl.getAttribute("lv-route");
  if (!route)
    throw new Error('Attribute "lv-route" not found.');
  const urlAttrs = {};
  const dataAttrs = {};
  Array.from(pageEl.attributes).forEach(({ name, value }) => {
    if (name.startsWith("lv-url-")) {
      const key = name.slice("lv-url-".length);
      urlAttrs[key] = JSON.parse(value);
    } else if (name.startsWith("lv-data-")) {
      const key = name.slice("lv-data-".length);
      dataAttrs[key] = JSON.parse(value);
    }
  });
  document.querySelectorAll("div[data-phx-component]").forEach((comp) => {
    const compId = comp.id;
    if (!compId)
      return;
    const compKey = `_${compId}`;
    Array.from(comp.attributes).forEach(({ name, value }) => {
      if (name.startsWith("lv-url-")) {
        const key = name.slice("lv-url-".length);
        urlAttrs[compKey] = urlAttrs[compKey] || {};
        urlAttrs[compKey][key] = JSON.parse(value);
      } else if (name.startsWith("lv-data-")) {
        const key = name.slice("lv-data-".length);
        dataAttrs[compKey] = dataAttrs[compKey] || {};
        dataAttrs[compKey][key] = JSON.parse(value);
      }
    });
  });
  const primaryUrl = buildUrl(route, urlAttrs);
  const combined = {};
  Object.keys(urlAttrs).forEach((k) => combined[k] = urlAttrs[k]);
  Object.entries(dataAttrs).forEach(([k, v]) => {
    if (combined[k] && typeof combined[k] === "object" && typeof v === "object") {
      combined[k] = { ...combined[k], ...v };
    } else {
      combined[k] = v;
    }
  });
  const combinedUrl = buildUrl(route, combined);
  return { primaryUrl, combinedUrl };
}
function enhanceLiveSocket(liveSocket) {
  liveSocket.domCallbacks.onPatchEnd = function(el) {
    try {
      const uris = buildLvPageUrls();
      const url1 = new URL(uris.primaryUrl, window.location.origin);
      const url = new URL(uris.combinedUrl, window.location.origin);
      console.log("updating view href");
      console.log("before " + window.liveSocket.href);
      console.log("after " + url1.href);
      console.log("after 2" + url.href);
      liveSocket.historyPatch(url1.href, "push");
      window.liveSocket.href = url1.href;
      if (window.liveSocket.main) {
        window.liveSocket.main.setHref(url.href);
      }
    } catch (error) {
      console.error("Error updating URL:", error);
    }
  };
  liveSocket.pushPatchUrl = (href, linkState = {}) => {
    liveSocket.historyPatch(href, linkState);
  };
  window.addEventListener("phx:js-execute", ({ detail }) => {
    console.log("js-execute");
    console.log(detail.ops);
    liveSocket.execJS(document.body, detail.ops);
  });
  return liveSocket;
}
//# sourceMappingURL=livex.cjs.js.map
