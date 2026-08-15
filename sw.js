// Fetch A Groomer — offline app-shell cache.
//
// The whole app is a single HTML file, so "is she running the latest version?"
// comes down entirely to how index.html gets served. This worker is
// NETWORK-FIRST for the app shell: on every launch with signal it fetches the
// current file, so an update lands the FIRST time she opens the app rather
// than the second. When the network is slow or absent — common out in the
// field — it falls back to the last cached copy after a short timeout, so the
// app still opens with no bars.
//
// Static odds and ends (icons, manifest) stay cache-first, since they're
// needed instantly and almost never change.
const CACHE = "fag-shell-v2";
const NET_TIMEOUT_MS = 3500;
const SHELL = [
  "./",
  "./index.html",
  "./manifest.json",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// A request for the app shell itself (the HTML) rather than an icon or the
// manifest. Page navigations and explicit index.html hits both qualify — and
// so do the ?report= / ?reportGroup= deep links, which serve the same file.
function isShellDocument(request, url) {
  return request.mode === "navigate"
    || url.pathname.endsWith("/")
    || url.pathname.endsWith("/index.html");
}

// Always try the network for the shell, but never hang on it. `no-store`
// bypasses the browser's own HTTP cache, which would otherwise keep handing
// back a stale index.html for as long as its max-age says to.
async function shellNetworkFirst() {
  const cache = await caches.open(CACHE);
  try {
    const res = await Promise.race([
      fetch("./index.html", { cache: "no-store" }),
      new Promise((_, reject) => setTimeout(() => reject(new Error("sw-timeout")), NET_TIMEOUT_MS)),
    ]);
    if (res && res.status === 200) {
      cache.put("./index.html", res.clone());
      return res;
    }
    throw new Error("sw-bad-status");
  } catch (err) {
    const cached = await cache.match("./index.html");
    if (cached) return cached;
    throw err;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request);
  if (cached) {
    // Quietly refresh in the background so the next launch has the newer copy.
    fetch(request)
      .then((res) => { if (res && res.status === 200) cache.put(request, res.clone()); })
      .catch(() => {});
    return cached;
  }
  const res = await fetch(request);
  if (res && res.status === 200) cache.put(request, res.clone());
  return res;
}

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  // Only handle same-origin GETs for the static shell; everything else
  // (Supabase API/storage calls, cross-origin CDN scripts) hits the network
  // normally and is never cached here.
  if (e.request.method !== "GET" || url.origin !== self.location.origin) return;

  e.respondWith(isShellDocument(e.request, url) ? shellNetworkFirst() : cacheFirst(e.request));
});
