var LiveView = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getOwnPropSymbols = Object.getOwnPropertySymbols;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __propIsEnum = Object.prototype.propertyIsEnumerable;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __spreadValues = (a, b) => {
    for (var prop in b || (b = {}))
      if (__hasOwnProp.call(b, prop))
        __defNormalProp(a, prop, b[prop]);
    if (__getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(b)) {
        if (__propIsEnum.call(b, prop))
          __defNormalProp(a, prop, b[prop]);
      }
    return a;
  };
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
    document.querySelectorAll("[data-phx-component]").forEach((comp) => {
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
        combined[k] = __spreadValues(__spreadValues({}, combined[k]), v);
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
    window.addEventListener("phx:js-execute", (event) => {
      const selector = event.detail.to || "body";
      document.querySelectorAll(selector).forEach((element) => {
        window.liveSocket.execJS(element, event.detail.ops);
      });
    });
    return liveSocket;
  }
  return __toCommonJS(livex_exports);
})();
