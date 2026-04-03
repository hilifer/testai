ToolsRegistry.register({
    id: 'markdown-preview',
    name: 'Markdown Preview',
    description: 'Write Markdown and see live preview with syntax support',
    icon: '\u{1F4DD}',
    category: 'text',
    tags: ['markdown', 'preview', 'editor', 'md', 'text', 'write'],
    render() {
        return `
            <div class="tool-row">
                <div class="tool-group">
                    <label class="tool-label">Markdown Input</label>
                    <textarea class="tool-input" id="mdInput" style="min-height:300px" oninput="MarkdownPreview.render()" placeholder="# Hello World\n\nWrite your **markdown** here..."># Welcome to Markdown Preview\n\nThis is a **bold** text and this is *italic*.\n\n## Features\n- Live preview\n- Syntax support\n- Export to HTML\n\n### Code\n\`\`\`\nconst hello = "world";\n\`\`\`\n\n> This is a blockquote\n\n| Column 1 | Column 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |</textarea>
                </div>
                <div class="tool-group">
                    <label class="tool-label">Preview</label>
                    <div class="markdown-preview" id="mdPreview" style="min-height:300px;"></div>
                </div>
            </div>
            <div class="tool-actions">
                <button class="btn btn-outline btn-sm" onclick="MarkdownPreview.copyHTML()">Copy HTML</button>
                <button class="btn btn-outline btn-sm" onclick="MarkdownPreview.downloadMD()">Download .md</button>
                <span class="copy-feedback" id="mdCopyFeedback">Copied!</span>
            </div>
        `;
    }
});

const MarkdownPreview = {
    render() {
        const input = document.getElementById('mdInput').value;
        document.getElementById('mdPreview').innerHTML = this._parse(input);
    },

    _parse(md) {
        let html = md
            // Escape HTML
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            // Code blocks
            .replace(/```(\w*)\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>')
            // Inline code
            .replace(/`([^`]+)`/g, '<code>$1</code>')
            // Headers
            .replace(/^### (.+)$/gm, '<h3>$1</h3>')
            .replace(/^## (.+)$/gm, '<h2>$1</h2>')
            .replace(/^# (.+)$/gm, '<h1>$1</h1>')
            // Bold and italic
            .replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>')
            .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.+?)\*/g, '<em>$1</em>')
            // Strikethrough
            .replace(/~~(.+?)~~/g, '<del>$1</del>')
            // Blockquote
            .replace(/^&gt; (.+)$/gm, '<blockquote>$1</blockquote>')
            // Horizontal rule
            .replace(/^---$/gm, '<hr>')
            // Unordered list
            .replace(/^- (.+)$/gm, '<li>$1</li>')
            // Links
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
            // Images
            .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:100%">')
            // Line breaks
            .replace(/\n\n/g, '</p><p>')
            .replace(/\n/g, '<br>');

        // Wrap list items
        html = html.replace(/((?:<li>.*<\/li>\s*)+)/g, '<ul>$1</ul>');
        // Wrap in paragraphs
        html = '<p>' + html + '</p>';
        // Clean up empty paragraphs
        html = html.replace(/<p>\s*<\/p>/g, '');
        html = html.replace(/<p>\s*(<h[1-6]>)/g, '$1');
        html = html.replace(/(<\/h[1-6]>)\s*<\/p>/g, '$1');
        html = html.replace(/<p>\s*(<ul>)/g, '$1');
        html = html.replace(/(<\/ul>)\s*<\/p>/g, '$1');
        html = html.replace(/<p>\s*(<pre>)/g, '$1');
        html = html.replace(/(<\/pre>)\s*<\/p>/g, '$1');
        html = html.replace(/<p>\s*(<blockquote>)/g, '$1');
        html = html.replace(/(<\/blockquote>)\s*<\/p>/g, '$1');
        html = html.replace(/<p>\s*(<hr>)\s*<\/p>/g, '$1');

        return html;
    },

    copyHTML() {
        const html = document.getElementById('mdPreview').innerHTML;
        navigator.clipboard.writeText(html);
        const fb = document.getElementById('mdCopyFeedback');
        fb.classList.add('show');
        setTimeout(() => fb.classList.remove('show'), 1500);
    },

    downloadMD() {
        const md = document.getElementById('mdInput').value;
        const blob = new Blob([md], { type: 'text/markdown' });
        const link = document.createElement('a');
        link.download = 'document.md';
        link.href = URL.createObjectURL(blob);
        link.click();
        URL.revokeObjectURL(link.href);
    }
};
