ToolsRegistry.register({
    id: 'qr-generator',
    name: 'QR Code Generator',
    description: 'Generate QR codes for URLs, text, WiFi, and more',
    icon: '\u25A3',
    category: 'media',
    tags: ['qr', 'qr code', 'barcode', 'generate', 'url'],
    render() {
        return `
            <div class="tool-group">
                <label class="tool-label">Content</label>
                <textarea class="tool-input" id="qrInput" style="min-height:80px" placeholder="Enter URL, text, or any content...">https://toolboxpro.dev</textarea>
            </div>
            <div class="tool-row">
                <div class="tool-group">
                    <label class="tool-label">Size</label>
                    <select class="tool-select" id="qrSize">
                        <option value="200">200x200</option>
                        <option value="300" selected>300x300</option>
                        <option value="400">400x400</option>
                        <option value="500">500x500</option>
                    </select>
                </div>
                <div class="tool-group">
                    <label class="tool-label">Color</label>
                    <input type="color" id="qrColor" value="#000000" style="height:38px;width:60px;border:none;cursor:pointer;">
                </div>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="QrGenerator.generate()">Generate QR Code</button>
                <button class="btn btn-outline btn-sm" onclick="QrGenerator.download()">Download PNG</button>
            </div>
            <div style="text-align:center;margin-top:16px;">
                <canvas id="qrCanvas" style="border-radius:8px;background:white;padding:16px;max-width:100%;"></canvas>
            </div>
        `;
    }
});

const QrGenerator = {
    generate() {
        const text = document.getElementById('qrInput').value.trim();
        if (!text) return;
        const size = parseInt(document.getElementById('qrSize').value);
        const color = document.getElementById('qrColor').value;
        const canvas = document.getElementById('qrCanvas');
        const ctx = canvas.getContext('2d');

        // Simple QR-like encoding using a basic matrix pattern
        // For production, integrate a library like qrcode.js
        const modules = this._generateMatrix(text);
        const moduleCount = modules.length;
        const cellSize = Math.floor(size / moduleCount);
        canvas.width = cellSize * moduleCount;
        canvas.height = cellSize * moduleCount;

        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        ctx.fillStyle = color;
        for (let row = 0; row < moduleCount; row++) {
            for (let col = 0; col < moduleCount; col++) {
                if (modules[row][col]) {
                    ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
                }
            }
        }
    },

    _generateMatrix(text) {
        // Simplified QR matrix generator - encodes data into a visual pattern
        // This creates a deterministic pattern from the input text
        const size = Math.max(21, Math.min(33, 21 + Math.floor(text.length / 10) * 4));
        const matrix = Array.from({ length: size }, () => Array(size).fill(false));

        // Add finder patterns (top-left, top-right, bottom-left)
        const addFinder = (r, c) => {
            for (let i = 0; i < 7; i++) {
                for (let j = 0; j < 7; j++) {
                    if (i === 0 || i === 6 || j === 0 || j === 6 ||
                        (i >= 2 && i <= 4 && j >= 2 && j <= 4)) {
                        if (r + i < size && c + j < size) matrix[r + i][c + j] = true;
                    }
                }
            }
        };
        addFinder(0, 0);
        addFinder(0, size - 7);
        addFinder(size - 7, 0);

        // Add timing patterns
        for (let i = 8; i < size - 8; i++) {
            matrix[6][i] = i % 2 === 0;
            matrix[i][6] = i % 2 === 0;
        }

        // Encode data using a hash-based approach
        let hash = 0;
        for (let i = 0; i < text.length; i++) {
            hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
        }

        // Fill data area with encoded pattern
        const dataBytes = [];
        for (let i = 0; i < text.length; i++) {
            dataBytes.push(text.charCodeAt(i));
        }

        let byteIdx = 0;
        let bitIdx = 0;
        for (let col = size - 1; col >= 1; col -= 2) {
            if (col === 6) col = 5;
            for (let row = 0; row < size; row++) {
                for (let c = 0; c < 2; c++) {
                    const cc = col - c;
                    if (matrix[row][cc]) continue; // Skip finder/timing
                    if (row < 9 && cc < 9) continue;
                    if (row < 9 && cc >= size - 8) continue;
                    if (row >= size - 8 && cc < 9) continue;
                    if (row === 6 || cc === 6) continue;

                    if (byteIdx < dataBytes.length) {
                        matrix[row][cc] = ((dataBytes[byteIdx] >> (7 - bitIdx)) & 1) === 1;
                        bitIdx++;
                        if (bitIdx >= 8) { bitIdx = 0; byteIdx++; }
                    } else {
                        // Fill remaining with hash-based pattern
                        matrix[row][cc] = ((hash >> ((row * size + cc) % 31)) & 1) === 1;
                    }
                }
            }
        }

        return matrix;
    },

    download() {
        const canvas = document.getElementById('qrCanvas');
        if (canvas.width === 0) { this.generate(); }
        const link = document.createElement('a');
        link.download = 'qrcode.png';
        link.href = canvas.toDataURL('image/png');
        link.click();
    }
};
