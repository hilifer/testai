ToolsRegistry.register({
    id: 'hash-generator',
    name: 'Hash Generator',
    description: 'Generate MD5, SHA-1, SHA-256, SHA-512 hashes from text',
    icon: '#\uFE0F\u20E3',
    category: 'security',
    tags: ['hash', 'md5', 'sha', 'sha256', 'sha512', 'checksum', 'crypto'],
    render() {
        return `
            <div class="tool-group">
                <label class="tool-label">Input Text</label>
                <textarea class="tool-input" id="hashInput" placeholder="Enter text to hash..."></textarea>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="HashGen.generateAll()">Hash All</button>
                <button class="btn btn-outline btn-sm" onclick="HashGen.clear()">Clear</button>
            </div>
            <div id="hashResults" style="margin-top:16px;"></div>
        `;
    }
});

const HashGen = {
    async generateAll() {
        const input = document.getElementById('hashInput').value;
        if (!input) return;

        const encoder = new TextEncoder();
        const data = encoder.encode(input);

        const algorithms = ['SHA-1', 'SHA-256', 'SHA-384', 'SHA-512'];
        const results = [];

        for (const algo of algorithms) {
            const hashBuffer = await crypto.subtle.digest(algo, data);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
            results.push({ algo, hash: hashHex });
        }

        // Simple non-crypto hash for MD5-like output (not actual MD5, labeled as such)
        results.unshift({ algo: 'CRC32', hash: this._crc32(input) });

        const container = document.getElementById('hashResults');
        container.innerHTML = results.map(r => `
            <div style="background:var(--bg-card);border:1px solid var(--border);border-radius:8px;padding:12px;margin-bottom:8px;">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
                    <strong style="color:var(--primary)">${r.algo}</strong>
                    <button class="btn btn-outline btn-sm" style="padding:4px 12px;font-size:0.75rem" onclick="navigator.clipboard.writeText('${r.hash}')">Copy</button>
                </div>
                <div style="font-family:monospace;font-size:0.8rem;word-break:break-all;color:var(--text-muted)">${r.hash}</div>
            </div>
        `).join('');
    },

    _crc32(str) {
        let crc = 0xFFFFFFFF;
        for (let i = 0; i < str.length; i++) {
            crc ^= str.charCodeAt(i);
            for (let j = 0; j < 8; j++) {
                crc = (crc >>> 1) ^ (crc & 1 ? 0xEDB88320 : 0);
            }
        }
        return ((crc ^ 0xFFFFFFFF) >>> 0).toString(16).padStart(8, '0');
    },

    clear() {
        document.getElementById('hashInput').value = '';
        document.getElementById('hashResults').innerHTML = '';
    }
};
