/**
 * Emulator-suite network guard for Bunny.
 *
 * The emulator suites must be deterministic and must never depend on Bunny
 * being reachable (or on a real credential existing). This guard fails the
 * moment any module tries to open an HTTP request to a Bunny host, so a test
 * that accidentally loses its offline guarantee fails loudly instead of
 * silently measuring the live service.
 *
 * Usage (before requiring ../lib/index.js):
 *   const guard = require("./bunny_network_guard").installBunnyNetworkGuard();
 *   ...
 *   guard.assertNoBunnyCalls();
 */

const BUNNY_HOST_PATTERN = /(^|\.)bunnycdn\.com$|(^|\.)b-cdn\.net$|(^|\.)mediadelivery\.net$/;

/**
 * Wrap `global.fetch` so Bunny hosts are rejected and recorded.
 * @return {object} Guard handle with the recorded calls and an assertion.
 */
function installBunnyNetworkGuard() {
  const realFetch = global.fetch;
  const calls = [];
  global.fetch = function guardedFetch(input, init) {
    let url = "";
    try {
      url = typeof input === "string" ? input : String(input && input.url);
    } catch {
      url = "";
    }
    let host = "";
    try {
      host = new URL(url).hostname;
    } catch {
      host = "";
    }
    if (host !== "" && BUNNY_HOST_PATTERN.test(host)) {
      calls.push(url);
      return Promise.reject(
        new Error(`bunny_network_guard: blocked Bunny call to ${host}`),
      );
    }
    return realFetch(input, init);
  };
  return {
    calls,
    /**
     * Fail the suite if any Bunny request was attempted.
     * @return {object} The guard (chainable).
     */
    assertNoBunnyCalls() {
      if (calls.length > 0) {
        throw new Error(
          `bunny_network_guard: ${calls.length} Bunny request(s) attempted; ` +
            "emulator suites must stay offline (mock the transport instead)",
        );
      }
      return this;
    },
  };
}

module.exports = {installBunnyNetworkGuard, BUNNY_HOST_PATTERN};
