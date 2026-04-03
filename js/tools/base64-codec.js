ToolsRegistry.register({
    id: 'base64-codec',
    name: 'Base64 Encoder/Decoder',
    description: 'Encode text to Base64 or decode Base64 to text. Supports file to Base64.',
    icon: '\u{1F504}',
    category: 'developer',
    tags: ['base64', 'encode', 'decode', 'convert', 'binary'],
    render() {
        return `
            <div class="tool-group">
                <label class="tool-label">Input</label>
                <textarea class="tool-input" id="b64Input" placeholder="Enter text to encode or Base64 to decode..."></textarea>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="Base64Codec.encode()">Encode</button>
                <button class="btn btn-primary btn-sm" onclick="Base64Codec.decode()">Decode</button>
                <button class="btn btn-outline btn-sm" onclick="Base64Codec.swap()">Swap</button>
                <button class="btn btn-outline btn-sm" onclick="Base64Codec.copy()">Copy Output</button>
                <span class="copy-feedback" id="b64CopyFeedback">Copied!</span>
            </div>
            <div class="tool-group">
                <label class="tool-label">Output</label>
                <textarea class="tool-output" id="b64Output" readonly></textarea>
            </div>
            <div class="tool-group" style="margin-top:16px;padding-top:16px;border-top:1px solid var(--border)">
                <label class="tool-label">File to Base64</label>
                <input type="file" id="b64File" style="color:var(--text-muted)" onchange="Base64Codec.fileToBase64(this)">
                <textarea class="tool-output" id="b64FileOutput" readonly style="margin-top:8px;min-height:60px;font-size:0.8rem" placeholder="Base64 output will appear here..."></textarea>
            </div>
        `;
    }
});

const Base64Codec = {
    encode() {
        const input = document.getElementById('b64Input').value;
        try {
            document.getElementById('b64Output').value = btoa(unescape(encodeURIComponent(input)));
        } catch (e) {
            document.getElementById('b64Output').value = 'Error: ' + e.message;
        }
    },
    decode() {
        const input = document.getElementById('b64Input').value.trim();
        try {
            document.getElementById('b64Output').value = decodeURIComponent(escape(atob(input)));
        } catch (e) {
            document.getElementById('b64Output').value = 'Error: Invalid Base64 string';
        }
    },
    swap() {
        const output = document.getElementById('b64Output').value;
        if (output && !output.startsWith('Error:')) {
            document.getElementById('b64Input').value = output;
            document.getElementById('b64Output').value = '';
        }
    },
    copy() {
        const output = document.getElementById('b64Output').value;
        if (output) {
            navigator.clipboard.writeText(output);
            const fb = document.getElementById('b64CopyFeedback');
            fb.classList.add('show');
            setTimeout(() => fb.classList.remove('show'), 1500);
        }
    },
    fileToBase64(input) {
        const file = input.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            document.getElementById('b64FileOutput').value = reader.result;
        };
        reader.readAsDataURL(file);
    }
};
