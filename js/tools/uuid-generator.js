ToolsRegistry.register({
    id: 'uuid-generator',
    name: 'UUID Generator',
    description: 'Generate UUID v4, nanoid, and other unique identifiers',
    icon: '\u{1F194}',
    category: 'developer',
    tags: ['uuid', 'guid', 'unique', 'id', 'random', 'nanoid'],
    render() {
        return `
            <div class="tool-group">
                <label class="tool-label">Generated UUID</label>
                <div class="password-display" id="uuidDisplay" style="font-size:1rem">Click Generate</div>
            </div>
            <div class="tool-row">
                <div class="tool-group">
                    <label class="tool-label">Format</label>
                    <select class="tool-select" id="uuidFormat">
                        <option value="v4">UUID v4 (Random)</option>
                        <option value="v4upper">UUID v4 (Uppercase)</option>
                        <option value="short">Short ID (8 chars)</option>
                        <option value="nanoid">Nano ID (21 chars)</option>
                        <option value="timestamp">Timestamp-based</option>
                    </select>
                </div>
                <div class="tool-group">
                    <label class="tool-label">Count</label>
                    <select class="tool-select" id="uuidCount">
                        <option value="1">1</option>
                        <option value="5">5</option>
                        <option value="10">10</option>
                        <option value="25">25</option>
                        <option value="50">50</option>
                    </select>
                </div>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="UuidGen.generate()">Generate</button>
                <button class="btn btn-outline btn-sm" onclick="UuidGen.copyAll()">Copy All</button>
                <span class="copy-feedback" id="uuidCopyFeedback">Copied!</span>
            </div>
            <div class="tool-group">
                <textarea class="tool-output" id="uuidOutput" style="min-height:150px" readonly placeholder="Generated IDs will appear here..."></textarea>
            </div>
        `;
    }
});

const UuidGen = {
    generate() {
        const format = document.getElementById('uuidFormat').value;
        const count = parseInt(document.getElementById('uuidCount').value);
        const ids = [];

        for (let i = 0; i < count; i++) {
            switch (format) {
                case 'v4': ids.push(this._uuidv4()); break;
                case 'v4upper': ids.push(this._uuidv4().toUpperCase()); break;
                case 'short': ids.push(this._shortId(8)); break;
                case 'nanoid': ids.push(this._nanoid(21)); break;
                case 'timestamp': ids.push(this._timestampId()); break;
            }
        }

        if (count === 1) {
            document.getElementById('uuidDisplay').textContent = ids[0];
        } else {
            document.getElementById('uuidDisplay').textContent = ids[0];
        }
        document.getElementById('uuidOutput').value = ids.join('\n');
    },

    _uuidv4() {
        const bytes = new Uint8Array(16);
        crypto.getRandomValues(bytes);
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
        return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
    },

    _shortId(len) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        const arr = new Uint8Array(len);
        crypto.getRandomValues(arr);
        return Array.from(arr, b => chars[b % chars.length]).join('');
    },

    _nanoid(len) {
        const chars = '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        const arr = new Uint8Array(len);
        crypto.getRandomValues(arr);
        return Array.from(arr, b => chars[b & 63]).join('');
    },

    _timestampId() {
        const ts = Date.now().toString(36);
        const rand = this._shortId(8);
        return `${ts}-${rand}`;
    },

    copyAll() {
        const output = document.getElementById('uuidOutput').value;
        if (output) {
            navigator.clipboard.writeText(output);
            const fb = document.getElementById('uuidCopyFeedback');
            fb.classList.add('show');
            setTimeout(() => fb.classList.remove('show'), 1500);
        }
    }
};
