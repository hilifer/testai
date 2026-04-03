ToolsRegistry.register({
    id: 'text-diff',
    name: 'Text Diff Checker',
    description: 'Compare two texts and highlight the differences line by line',
    icon: '\u{1F504}',
    category: 'text',
    tags: ['diff', 'compare', 'text', 'difference', 'merge'],
    render() {
        return `
            <div class="tool-row">
                <div class="tool-group">
                    <label class="tool-label">Original Text</label>
                    <textarea class="tool-input" id="diffLeft" style="min-height:200px" placeholder="Paste original text here..."></textarea>
                </div>
                <div class="tool-group">
                    <label class="tool-label">Modified Text</label>
                    <textarea class="tool-input" id="diffRight" style="min-height:200px" placeholder="Paste modified text here..."></textarea>
                </div>
            </div>
            <div class="tool-actions">
                <button class="btn btn-primary btn-sm" onclick="TextDiff.compare()">Compare</button>
                <button class="btn btn-outline btn-sm" onclick="TextDiff.swap()">Swap</button>
                <button class="btn btn-outline btn-sm" onclick="TextDiff.clear()">Clear</button>
            </div>
            <div id="diffStats" style="font-size:0.85rem;color:var(--text-muted);margin-bottom:8px;"></div>
            <div class="diff-container" id="diffOutput" style="background:var(--bg-card);border:1px solid var(--border);border-radius:8px;padding:12px;max-height:400px;overflow:auto;"></div>
        `;
    }
});

const TextDiff = {
    compare() {
        const left = document.getElementById('diffLeft').value;
        const right = document.getElementById('diffRight').value;
        const leftLines = left.split('\n');
        const rightLines = right.split('\n');
        const maxLen = Math.max(leftLines.length, rightLines.length);

        let added = 0, removed = 0, unchanged = 0;
        const result = [];

        // Simple line-by-line diff using LCS approach
        const lcs = this._lcs(leftLines, rightLines);
        let li = 0, ri = 0, ci = 0;

        while (li < leftLines.length || ri < rightLines.length) {
            if (ci < lcs.length && li < leftLines.length && leftLines[li] === lcs[ci] &&
                ri < rightLines.length && rightLines[ri] === lcs[ci]) {
                result.push({ type: 'same', text: leftLines[li] });
                unchanged++;
                li++; ri++; ci++;
            } else if (ci < lcs.length && ri < rightLines.length && rightLines[ri] === lcs[ci]) {
                // Left line was removed
                result.push({ type: 'remove', text: leftLines[li] || '' });
                removed++;
                li++;
            } else if (ci < lcs.length && li < leftLines.length && leftLines[li] === lcs[ci]) {
                // Right line was added
                result.push({ type: 'add', text: rightLines[ri] || '' });
                added++;
                ri++;
            } else {
                // Neither matches LCS
                if (li < leftLines.length) {
                    result.push({ type: 'remove', text: leftLines[li] });
                    removed++;
                    li++;
                }
                if (ri < rightLines.length) {
                    result.push({ type: 'add', text: rightLines[ri] });
                    added++;
                    ri++;
                }
            }
        }

        const output = document.getElementById('diffOutput');
        output.innerHTML = result.map(r => {
            const prefix = r.type === 'add' ? '+' : r.type === 'remove' ? '-' : ' ';
            const cls = r.type === 'add' ? 'diff-add' : r.type === 'remove' ? 'diff-remove' : 'diff-same';
            const escaped = r.text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
            return `<div class="diff-line ${cls}">${prefix} ${escaped}</div>`;
        }).join('');

        document.getElementById('diffStats').textContent =
            `${added} added, ${removed} removed, ${unchanged} unchanged`;
    },

    _lcs(a, b) {
        const m = a.length, n = b.length;
        const dp = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));

        for (let i = 1; i <= m; i++) {
            for (let j = 1; j <= n; j++) {
                dp[i][j] = a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
            }
        }

        const result = [];
        let i = m, j = n;
        while (i > 0 && j > 0) {
            if (a[i - 1] === b[j - 1]) { result.unshift(a[i - 1]); i--; j--; }
            else if (dp[i - 1][j] > dp[i][j - 1]) { i--; }
            else { j--; }
        }
        return result;
    },

    swap() {
        const left = document.getElementById('diffLeft').value;
        const right = document.getElementById('diffRight').value;
        document.getElementById('diffLeft').value = right;
        document.getElementById('diffRight').value = left;
    },

    clear() {
        document.getElementById('diffLeft').value = '';
        document.getElementById('diffRight').value = '';
        document.getElementById('diffOutput').innerHTML = '';
        document.getElementById('diffStats').textContent = '';
    }
};
