const CACHE_NAME = 'toolbox-pro-v1';
const ASSETS = [
    '/',
    '/index.html',
    '/css/style.css',
    '/js/tools-registry.js',
    '/js/tools/json-formatter.js',
    '/js/tools/qr-generator.js',
    '/js/tools/base64-codec.js',
    '/js/tools/color-palette.js',
    '/js/tools/password-generator.js',
    '/js/tools/markdown-preview.js',
    '/js/tools/text-diff.js',
    '/js/tools/uuid-generator.js',
    '/js/tools/url-codec.js',
    '/js/tools/hash-generator.js',
    '/js/app.js',
    '/manifest.json'
];

// Install - cache all assets
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(ASSETS))
            .then(() => self.skipWaiting())
    );
});

// Activate - clean old caches
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys
                .filter(key => key !== CACHE_NAME)
                .map(key => caches.delete(key))
            )
        ).then(() => self.clients.claim())
    );
});

// Fetch - cache first, fallback to network
self.addEventListener('fetch', event => {
    event.respondWith(
        caches.match(event.request)
            .then(cached => cached || fetch(event.request)
                .then(response => {
                    // Cache new requests dynamically
                    if (response.status === 200) {
                        const clone = response.clone();
                        caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                    }
                    return response;
                })
            )
            .catch(() => {
                // Offline fallback
                if (event.request.destination === 'document') {
                    return caches.match('/index.html');
                }
            })
    );
});
