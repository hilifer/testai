ToolsRegistry.register({
    id: 'password-generator',
    name: 'Password Generator',
    description: 'Generate strong, secure passwords with customizable options',
    icon: '\u{1F512}',
    category: 'security',
    tags: ['password', 'security', 'random', 'strong', 'generator'],
    render() {
        return `
            <div class="password-display" id="pwdDisplay">Click Generate</div>
            <div class="strength-bar"><div class="strength-fill" id="pwdStrength"></div></div>
            <div id="pwdStrengthText" style="font-size:0.85rem;color:var(--text-muted);margin-bottom:16px;"></div>
            <div class="range-group">
                <label class="tool-label" style="margin:0">Length:</label>
                <input type="range" id="pwdLength" min="6" max="64" value="16" oninput="PasswordGen.updateLength()">
                <span class="range-value" id="pwdLengthVal">16</span>
            </div>
            <div class="checkbox-group">
                <label><input type="checkbox" id="pwdUpper" checked> Uppercase (A-Z)</label>
                <label><input type="checkbox" id="pwdLower" checked> Lowercase (a-z)</label>
                <label><input type="checkbox" id="pwdNumbers" checked> Numbers (0-9)</label>
                <label><input type="checkbox" id="pwdSymbols" checked> Symbols (!@#$)</label>
            </div>
            <div class="tool-actions" style="margin-top:16px;">
                <button class="btn btn-primary btn-sm" onclick="PasswordGen.generate()">Generate</button>
                <button class="btn btn-outline btn-sm" onclick="PasswordGen.copy()">Copy</button>
                <button class="btn btn-outline btn-sm" onclick="PasswordGen.generateBatch()">Generate 5</button>
                <span class="copy-feedback" id="pwdCopyFeedback">Copied!</span>
            </div>
            <div id="pwdBatch" style="margin-top:16px;"></div>
        `;
    }
});

const PasswordGen = {
    generate() {
        const length = parseInt(document.getElementById('pwdLength').value);
        const useUpper = document.getElementById('pwdUpper').checked;
        const useLower = document.getElementById('pwdLower').checked;
        const useNumbers = document.getElementById('pwdNumbers').checked;
        const useSymbols = document.getElementById('pwdSymbols').checked;

        let chars = '';
        if (useUpper) chars += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        if (useLower) chars += 'abcdefghijklmnopqrstuvwxyz';
        if (useNumbers) chars += '0123456789';
        if (useSymbols) chars += '!@#$%^&*()_+-=[]{}|;:,.<>?';

        if (!chars) { chars = 'abcdefghijklmnopqrstuvwxyz'; }

        const array = new Uint32Array(length);
        crypto.getRandomValues(array);
        const password = Array.from(array, x => chars[x % chars.length]).join('');

        document.getElementById('pwdDisplay').textContent = password;
        this._updateStrength(password);
        return password;
    },

    generateBatch() {
        const passwords = Array.from({ length: 5 }, () => this.generate());
        // Show last generated in display, list all in batch area
        const batchDiv = document.getElementById('pwdBatch');
        batchDiv.innerHTML = '<label class="tool-label">Batch Generated:</label>' +
            passwords.map(p =>
                `<div style="font-family:monospace;padding:6px 10px;background:var(--bg-input);border-radius:6px;margin:4px 0;font-size:0.85rem;cursor:pointer;word-break:break-all" onclick="navigator.clipboard.writeText('${p.replace(/'/g, "\\'")}')">${p}</div>`
            ).join('');
    },

    updateLength() {
        document.getElementById('pwdLengthVal').textContent = document.getElementById('pwdLength').value;
    },

    copy() {
        const pwd = document.getElementById('pwdDisplay').textContent;
        if (pwd && pwd !== 'Click Generate') {
            navigator.clipboard.writeText(pwd);
            const fb = document.getElementById('pwdCopyFeedback');
            fb.classList.add('show');
            setTimeout(() => fb.classList.remove('show'), 1500);
        }
    },

    _updateStrength(password) {
        let score = 0;
        if (password.length >= 8) score++;
        if (password.length >= 12) score++;
        if (password.length >= 20) score++;
        if (/[a-z]/.test(password) && /[A-Z]/.test(password)) score++;
        if (/\d/.test(password)) score++;
        if (/[^a-zA-Z0-9]/.test(password)) score++;

        const fill = document.getElementById('pwdStrength');
        const text = document.getElementById('pwdStrengthText');
        const pct = Math.min(100, (score / 6) * 100);
        fill.style.width = pct + '%';

        if (score <= 2) { fill.style.background = '#FF6584'; text.textContent = 'Weak'; }
        else if (score <= 4) { fill.style.background = '#FF8906'; text.textContent = 'Medium'; }
        else { fill.style.background = '#2CB67D'; text.textContent = 'Strong'; }
    }
};
