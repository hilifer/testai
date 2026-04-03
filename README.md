# ToolBox Pro - Monetizable Online Developer Toolbox

A free, fast, offline-capable developer toolbox built as a PWA that can be published to Google Play Store via TWA (Trusted Web Activity).

## Live Tools (10 tools)

| Tool | Category | Description |
|------|----------|-------------|
| JSON Formatter | Developer | Format, validate, minify JSON |
| QR Code Generator | Design | Generate QR codes with custom colors |
| Base64 Encoder/Decoder | Developer | Encode/decode Base64, file to Base64 |
| Color Palette Generator | Design | Generate palettes, convert HEX/RGB/HSL |
| Password Generator | Security | Cryptographically secure password generation |
| Markdown Preview | Text | Live Markdown editor with preview |
| Text Diff Checker | Text | Compare texts with LCS algorithm |
| UUID Generator | Developer | UUID v4, Nano ID, Short ID, Timestamp ID |
| URL Encoder/Decoder | Developer | Encode/decode URLs, parse query params |
| Hash Generator | Security | SHA-1, SHA-256, SHA-384, SHA-512, CRC32 |

## Tech Stack

- **Frontend**: Pure HTML/CSS/JavaScript (zero dependencies, fast loading)
- **PWA**: Service Worker + Web App Manifest (installable, works offline)
- **Android**: TWA wrapper for Google Play Store publication
- **Design**: Dark theme, responsive, mobile-first

## Monetization Strategy

### 1. Advertising (Estimated $2-8 CPM)
- Ad zones built into the layout (top banner, between tools)
- Integrate Google AdSense or Carbon Ads
- PRO users see no ads

### 2. Freemium Subscription ($2.99/mo or $19.99/yr)
- Free: All tools, daily usage limits, ads
- PRO: Unlimited usage, no ads, batch processing, API access
- Integrate Stripe Checkout or Google Play Billing

### 3. API Access (Pay-per-use)
- Expose tools as REST API endpoints
- Charge per 1000 API calls
- Target developers who need programmatic access

### 4. Google Play Store
- Package as TWA (Trusted Web Activity) - config in `/twa/`
- One-time $25 Google Play developer fee
- In-app purchases for PRO subscription

## Deployment Guide

### Step 1: Deploy the Website
```bash
# Option A: Vercel (recommended, free tier)
npx vercel --prod

# Option B: Netlify
npx netlify deploy --prod --dir=.

# Option C: GitHub Pages
# Push to gh-pages branch

# Option D: Cloudflare Pages
# Connect your GitHub repo
```

### Step 2: Add Monetization
```html
<!-- Add to index.html for AdSense -->
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js"
    crossorigin="anonymous"></script>

<!-- Replace ad-placeholder divs with actual ad units -->
<ins class="adsbygoogle" data-ad-client="ca-pub-XXXX" data-ad-slot="XXXX"></ins>
```

### Step 3: Build Android App (TWA)
```bash
# Install Bubblewrap CLI (Google's TWA tool)
npm install -g @aspect-build/aspect-cli @nicolo-ribaudo/bubblewrap-cli

# Or use the manual TWA config in /twa/ directory
# 1. Set up Android Studio
# 2. Import the TWA project
# 3. Update assetlinks.json with your SHA256 fingerprint
# 4. Build and sign the APK
# 5. Upload to Google Play Console
```

### Step 4: SEO Optimization
- Each tool page is accessible via hash URL (#tool-id)
- Meta tags optimized for search engines
- Add structured data (JSON-LD) for rich snippets
- Submit sitemap to Google Search Console

## Revenue Projections

| Traffic | Ad Revenue | PRO Subs (2%) | Total/mo |
|---------|-----------|---------------|----------|
| 10K/mo  | $30-80    | $60-120       | $90-200  |
| 50K/mo  | $150-400  | $300-600      | $450-1000|
| 100K/mo | $300-800  | $600-1200     | $900-2000|

## File Structure

```
├── index.html          # Main SPA page
├── privacy.html        # Privacy policy (required for stores)
├── terms.html          # Terms of service
├── manifest.json       # PWA manifest
├── sw.js              # Service worker (offline support)
├── assetlinks.json    # Digital Asset Links for TWA
├── css/
│   └── style.css      # All styles (dark theme)
├── js/
│   ├── tools-registry.js  # Tool registration system
│   ├── app.js             # Main app controller
│   └── tools/
│       ├── json-formatter.js
│       ├── qr-generator.js
│       ├── base64-codec.js
│       ├── color-palette.js
│       ├── password-generator.js
│       ├── markdown-preview.js
│       ├── text-diff.js
│       ├── uuid-generator.js
│       ├── url-codec.js
│       └── hash-generator.js
├── assets/
│   └── icon.svg       # App icon
└── twa/
    ├── build.gradle   # Android build config
    └── AndroidManifest.xml
```

## Adding New Tools

```javascript
// In js/tools/my-new-tool.js
ToolsRegistry.register({
    id: 'my-tool',
    name: 'My Tool',
    description: 'What it does',
    icon: '🔧',
    category: 'developer', // developer | security | text | media
    tags: ['keyword1', 'keyword2'],
    render() {
        return `<div>Your tool HTML here</div>`;
    }
});
```

Then add `<script src="js/tools/my-new-tool.js"></script>` to index.html.

## License

Proprietary - All rights reserved.
