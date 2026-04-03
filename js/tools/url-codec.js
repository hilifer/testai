ToolsRegistry.register({
    id: 'url-codec',
    name: 'URL Encoder/Decoder',
    description: 'Encode and decode URLs, parse query parameters',
    icon: '\u{1F517}',
    category: 'developer',
    tags: ['url', 'encode', 'decode', 'uri', 'query', 'parameter'],
    render() {
        return `
            <div class="tool-group">
                <label class="tool-label">Input URL or Text</label>
                <textarea class="tool-input" id="urlInput" style="min-height:80px" placeholder="Enter URL to decode or text to encode..."></textarea>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="UrlCodec.encode()">Encode</button>
                <button class="btn btn-primary btn-sm" onclick="UrlCodec.decode()">Decode</button>
                <button class="btn btn-outline btn-sm" onclick="UrlCodec.encodeComponent()">Encode Component</button>
                <button class="btn btn-outline btn-sm" onclick="UrlCodec.parse()">Parse URL</button>
                <button class="btn btn-outline btn-sm" onclick="UrlCodec.copy()">Copy</button>
                <span class="copy-feedback" id="urlCopyFeedback">Copied!</span>
            </div>
            <div class="tool-group">
                <label class="tool-label">Output</label>
                <textarea class="tool-output" id="urlOutput" readonly></textarea>
            </div>
            <div id="urlParsed" style="margin-top:12px;"></div>
        `;
    }
});

const UrlCodec = {
    encode() {
        const input = document.getElementById('urlInput').value;
        document.getElementById('urlOutput').value = encodeURI(input);
    },
    decode() {
        const input = document.getElementById('urlInput').value;
        try {
            document.getElementById('urlOutput').value = decodeURI(input);
        } catch (e) {
            document.getElementById('urlOutput').value = 'Error: ' + e.message;
        }
    },
    encodeComponent() {
        const input = document.getElementById('urlInput').value;
        document.getElementById('urlOutput').value = encodeURIComponent(input);
    },
    parse() {
        const input = document.getElementById('urlInput').value.trim();
        try {
            const url = new URL(input);
            const params = Array.from(url.searchParams.entries());
            let html = `
                <div style="background:var(--bg-card);border:1px solid var(--border);border-radius:8px;padding:16px;font-size:0.9rem;">
                    <div><strong>Protocol:</strong> ${url.protocol}</div>
                    <div><strong>Host:</strong> ${url.host}</div>
                    <div><strong>Pathname:</strong> ${url.pathname}</div>
                    <div><strong>Hash:</strong> ${url.hash || '(none)'}</div>
            `;
            if (params.length > 0) {
                html += '<div style="margin-top:12px"><strong>Query Parameters:</strong></div>';
                html += '<table style="width:100%;margin-top:8px;border-collapse:collapse;">';
                params.forEach(([key, value]) => {
                    html += `<tr style="border-bottom:1px solid var(--border)">
                        <td style="padding:6px;color:var(--primary);font-family:monospace">${key}</td>
                        <td style="padding:6px;font-family:monospace">${value}</td>
                    </tr>`;
                });
                html += '</table>';
            }
            html += '</div>';
            document.getElementById('urlParsed').innerHTML = html;
            document.getElementById('urlOutput').value = url.href;
        } catch (e) {
            document.getElementById('urlParsed').innerHTML = `<span style="color:var(--secondary)">Not a valid URL. Try encoding instead.</span>`;
        }
    },
    copy() {
        const output = document.getElementById('urlOutput').value;
        if (output) {
            navigator.clipboard.writeText(output);
            const fb = document.getElementById('urlCopyFeedback');
            fb.classList.add('show');
            setTimeout(() => fb.classList.remove('show'), 1500);
        }
    }
};
