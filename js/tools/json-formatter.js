ToolsRegistry.register({
    id: 'json-formatter',
    name: 'JSON Formatter',
    description: 'Format, validate, and minify JSON data with syntax highlighting',
    icon: '{ }',
    category: 'developer',
    tags: ['json', 'format', 'validate', 'minify', 'prettify'],
    render() {
        return `
            <div class="tool-group">
                <label class="tool-label">Input JSON</label>
                <textarea class="tool-input" id="jsonInput" placeholder='Paste your JSON here...\n{"name": "example", "value": 123}'></textarea>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="JsonFormatter.format()">Format</button>
                <button class="btn btn-outline btn-sm" onclick="JsonFormatter.minify()">Minify</button>
                <button class="btn btn-outline btn-sm" onclick="JsonFormatter.validate()">Validate</button>
                <button class="btn btn-outline btn-sm" onclick="JsonFormatter.copy()">Copy</button>
                <button class="btn btn-outline btn-sm" onclick="JsonFormatter.clear()">Clear</button>
                <span class="copy-feedback" id="jsonCopyFeedback">Copied!</span>
            </div>
            <div class="tool-group">
                <label class="tool-label">Output</label>
                <textarea class="tool-output" id="jsonOutput" readonly></textarea>
            </div>
            <div id="jsonStatus" style="margin-top:8px;font-size:0.85rem;"></div>
        `;
    }
});

const JsonFormatter = {
    format() {
        try {
            const input = document.getElementById('jsonInput').value.trim();
            if (!input) return;
            const parsed = JSON.parse(input);
            document.getElementById('jsonOutput').value = JSON.stringify(parsed, null, 2);
            document.getElementById('jsonStatus').innerHTML = '<span style="color:var(--success)">Valid JSON - Formatted successfully</span>';
        } catch (e) {
            document.getElementById('jsonStatus').innerHTML = `<span style="color:var(--secondary)">Error: ${e.message}</span>`;
        }
    },
    minify() {
        try {
            const input = document.getElementById('jsonInput').value.trim();
            if (!input) return;
            const parsed = JSON.parse(input);
            document.getElementById('jsonOutput').value = JSON.stringify(parsed);
            document.getElementById('jsonStatus').innerHTML = '<span style="color:var(--success)">Minified successfully</span>';
        } catch (e) {
            document.getElementById('jsonStatus').innerHTML = `<span style="color:var(--secondary)">Error: ${e.message}</span>`;
        }
    },
    validate() {
        try {
            const input = document.getElementById('jsonInput').value.trim();
            if (!input) { document.getElementById('jsonStatus').innerHTML = 'Enter JSON to validate'; return; }
            JSON.parse(input);
            document.getElementById('jsonStatus').innerHTML = '<span style="color:var(--success)">Valid JSON</span>';
        } catch (e) {
            document.getElementById('jsonStatus').innerHTML = `<span style="color:var(--secondary)">Invalid: ${e.message}</span>`;
        }
    },
    copy() {
        const output = document.getElementById('jsonOutput').value;
        if (output) {
            navigator.clipboard.writeText(output);
            const fb = document.getElementById('jsonCopyFeedback');
            fb.classList.add('show');
            setTimeout(() => fb.classList.remove('show'), 1500);
        }
    },
    clear() {
        document.getElementById('jsonInput').value = '';
        document.getElementById('jsonOutput').value = '';
        document.getElementById('jsonStatus').innerHTML = '';
    }
};
