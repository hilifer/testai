ToolsRegistry.register({
    id: 'color-palette',
    name: 'Color Palette Generator',
    description: 'Generate beautiful color palettes. Convert between HEX, RGB, and HSL.',
    icon: '\u{1F3A8}',
    category: 'media',
    tags: ['color', 'palette', 'hex', 'rgb', 'hsl', 'design', 'css'],
    render() {
        return `
            <div class="tool-row">
                <div class="tool-group">
                    <label class="tool-label">Base Color</label>
                    <div style="display:flex;gap:8px;align-items:center">
                        <input type="color" id="colorPicker" value="#6C63FF" style="height:40px;width:60px;border:none;cursor:pointer;" onchange="ColorPalette.generate()">
                        <input type="text" class="tool-select" id="colorHex" value="#6C63FF" style="width:120px" onchange="ColorPalette.fromHex()">
                    </div>
                </div>
                <div class="tool-group">
                    <label class="tool-label">Palette Type</label>
                    <select class="tool-select" id="paletteType" onchange="ColorPalette.generate()">
                        <option value="analogous">Analogous</option>
                        <option value="complementary">Complementary</option>
                        <option value="triadic">Triadic</option>
                        <option value="monochromatic">Monochromatic</option>
                        <option value="random">Random Harmony</option>
                    </select>
                </div>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="ColorPalette.generate()">Generate</button>
                <button class="btn btn-outline btn-sm" onclick="ColorPalette.randomBase()">Random Base</button>
                <button class="btn btn-outline btn-sm" onclick="ColorPalette.exportCSS()">Export CSS</button>
            </div>
            <div class="color-grid" id="colorGrid"></div>
            <div class="tool-group" style="margin-top:16px;">
                <label class="tool-label">Color Converter</label>
                <div class="tool-row">
                    <div>
                        <input type="text" class="tool-select" id="convertInput" placeholder="#6C63FF or rgb(108,99,255)" style="width:100%">
                    </div>
                    <div>
                        <button class="btn btn-outline btn-sm" onclick="ColorPalette.convert()">Convert</button>
                    </div>
                </div>
                <div id="convertOutput" style="font-size:0.9rem;color:var(--text-muted);margin-top:8px;"></div>
            </div>
        `;
    }
});

const ColorPalette = {
    generate() {
        const hex = document.getElementById('colorPicker').value;
        document.getElementById('colorHex').value = hex;
        const type = document.getElementById('paletteType').value;
        const hsl = this._hexToHSL(hex);
        let colors = [];

        switch (type) {
            case 'analogous':
                colors = [-30, -15, 0, 15, 30].map(offset =>
                    this._hslToHex((hsl.h + offset + 360) % 360, hsl.s, hsl.l));
                break;
            case 'complementary':
                colors = [0, 30, 180, 210, 330].map(offset =>
                    this._hslToHex((hsl.h + offset) % 360, hsl.s, hsl.l));
                break;
            case 'triadic':
                colors = [0, 60, 120, 180, 240].map(offset =>
                    this._hslToHex((hsl.h + offset) % 360, hsl.s, hsl.l));
                break;
            case 'monochromatic':
                colors = [20, 35, 50, 65, 80].map(l =>
                    this._hslToHex(hsl.h, hsl.s, l));
                break;
            case 'random':
                colors = Array.from({ length: 5 }, () =>
                    this._hslToHex(Math.random() * 360, 50 + Math.random() * 40, 40 + Math.random() * 30));
                break;
        }

        const grid = document.getElementById('colorGrid');
        grid.innerHTML = colors.map(c => {
            const textColor = this._isLight(c) ? '#000' : '#FFF';
            return `<div class="color-swatch" style="background:${c};color:${textColor}" onclick="ColorPalette.copySwatch('${c}')">${c}</div>`;
        }).join('');
    },

    fromHex() {
        const hex = document.getElementById('colorHex').value;
        if (/^#[0-9A-Fa-f]{6}$/.test(hex)) {
            document.getElementById('colorPicker').value = hex;
            this.generate();
        }
    },

    randomBase() {
        const hex = this._hslToHex(Math.random() * 360, 50 + Math.random() * 40, 40 + Math.random() * 30);
        document.getElementById('colorPicker').value = hex;
        document.getElementById('colorHex').value = hex;
        this.generate();
    },

    copySwatch(hex) {
        navigator.clipboard.writeText(hex);
    },

    exportCSS() {
        const swatches = document.querySelectorAll('.color-swatch');
        if (!swatches.length) return;
        const css = Array.from(swatches).map((s, i) =>
            `  --color-${i + 1}: ${s.textContent};`
        ).join('\n');
        const output = `:root {\n${css}\n}`;
        navigator.clipboard.writeText(output);
        alert('CSS copied to clipboard!');
    },

    convert() {
        const input = document.getElementById('convertInput').value.trim();
        const output = document.getElementById('convertOutput');
        let r, g, b;

        const hexMatch = input.match(/^#?([0-9a-f]{6})$/i);
        const rgbMatch = input.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);

        if (hexMatch) {
            const hex = hexMatch[1];
            r = parseInt(hex.substr(0, 2), 16);
            g = parseInt(hex.substr(2, 2), 16);
            b = parseInt(hex.substr(4, 2), 16);
        } else if (rgbMatch) {
            r = parseInt(rgbMatch[1]);
            g = parseInt(rgbMatch[2]);
            b = parseInt(rgbMatch[3]);
        } else {
            output.textContent = 'Invalid format. Use #RRGGBB or rgb(R,G,B)';
            return;
        }

        const hex = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`.toUpperCase();
        const hsl = this._rgbToHSL(r, g, b);
        output.innerHTML = `
            <strong>HEX:</strong> ${hex} &nbsp;
            <strong>RGB:</strong> rgb(${r}, ${g}, ${b}) &nbsp;
            <strong>HSL:</strong> hsl(${Math.round(hsl.h)}, ${Math.round(hsl.s)}%, ${Math.round(hsl.l)}%)
        `;
    },

    _hexToHSL(hex) {
        const r = parseInt(hex.substr(1, 2), 16) / 255;
        const g = parseInt(hex.substr(3, 2), 16) / 255;
        const b = parseInt(hex.substr(5, 2), 16) / 255;
        return this._rgbToHSL(r * 255, g * 255, b * 255);
    },

    _rgbToHSL(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        let h, s, l = (max + min) / 2;
        if (max === min) { h = s = 0; }
        else {
            const d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            switch (max) {
                case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
                case g: h = ((b - r) / d + 2) / 6; break;
                case b: h = ((r - g) / d + 4) / 6; break;
            }
            h *= 360;
        }
        return { h, s: s * 100, l: l * 100 };
    },

    _hslToHex(h, s, l) {
        s /= 100; l /= 100;
        const a = s * Math.min(l, 1 - l);
        const f = n => {
            const k = (n + h / 30) % 12;
            const color = l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1);
            return Math.round(255 * color).toString(16).padStart(2, '0');
        };
        return `#${f(0)}${f(8)}${f(4)}`;
    },

    _isLight(hex) {
        const r = parseInt(hex.substr(1, 2), 16);
        const g = parseInt(hex.substr(3, 2), 16);
        const b = parseInt(hex.substr(5, 2), 16);
        return (r * 299 + g * 587 + b * 114) / 1000 > 128;
    }
};
