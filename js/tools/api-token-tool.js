/**
 * ToolBox Pro - API Token Manager Tool
 *
 * Visual interface for managing API tokens.
 * Inspired by openclaw-zero-token's credential management UI.
 */
ToolsRegistry.register({
    id: 'api-token-manager',
    name: 'API Token Manager',
    description: 'Create, validate, and manage self-signed API tokens for tool access',
    icon: '\uD83D\uDD11',
    category: 'security',
    tags: ['token', 'api', 'auth', 'jwt', 'key', 'security', 'credential', 'gateway'],
    render() {
        return `
            <div class="token-tool">
                <!-- Stats Bar -->
                <div class="token-stats" id="tokenStats"></div>

                <!-- Tab Navigation -->
                <div class="token-tabs">
                    <button class="token-tab active" onclick="ApiTokenTool.switchTab('create')">Create Token</button>
                    <button class="token-tab" onclick="ApiTokenTool.switchTab('list')">My Tokens</button>
                    <button class="token-tab" onclick="ApiTokenTool.switchTab('validate')">Validate</button>
                    <button class="token-tab" onclick="ApiTokenTool.switchTab('settings')">Settings</button>
                </div>

                <!-- Create Tab -->
                <div class="token-panel" id="panel-create">
                    <div class="tool-group">
                        <label class="tool-label">Token Name</label>
                        <input type="text" class="tool-input" id="tokenName" placeholder="e.g. My API Key, CI/CD Token..." style="min-height:auto;font-family:inherit;">
                    </div>
                    <div class="tool-group">
                        <label class="tool-label">Permissions (Scopes)</label>
                        <div class="token-scopes" id="tokenScopes"></div>
                    </div>
                    <div class="tool-group">
                        <label class="tool-label">Expiration</label>
                        <select class="tool-select" id="tokenExpiry" style="width:100%">
                            <option value="0">Never expires</option>
                            <option value="3600">1 hour</option>
                            <option value="86400">24 hours</option>
                            <option value="604800" selected>7 days</option>
                            <option value="2592000">30 days</option>
                            <option value="7776000">90 days</option>
                            <option value="31536000">1 year</option>
                        </select>
                    </div>
                    <div class="tool-group">
                        <label class="tool-label">Max Uses (0 = unlimited)</label>
                        <input type="number" class="tool-number" id="tokenMaxUses" value="0" min="0" style="width:100%;padding:10px 14px;border-radius:8px;border:1px solid var(--border);background:var(--bg-input);color:var(--text);font-size:0.9rem;">
                    </div>
                    <div class="tool-actions">
                        <button class="btn btn-primary btn-sm" onclick="ApiTokenTool.create()">Generate Token</button>
                    </div>
                    <div id="tokenCreateResult" style="margin-top:16px;"></div>
                </div>

                <!-- List Tab -->
                <div class="token-panel" id="panel-list" style="display:none;">
                    <div id="tokenList"></div>
                </div>

                <!-- Validate Tab -->
                <div class="token-panel" id="panel-validate" style="display:none;">
                    <div class="tool-group">
                        <label class="tool-label">Paste Token</label>
                        <textarea class="tool-input" id="tokenValidateInput" placeholder="Paste a token here to validate..."></textarea>
                    </div>
                    <div class="tool-actions">
                        <button class="btn btn-primary btn-sm" onclick="ApiTokenTool.validate()">Validate Token</button>
                    </div>
                    <div id="tokenValidateResult" style="margin-top:16px;"></div>
                </div>

                <!-- Settings Tab -->
                <div class="token-panel" id="panel-settings" style="display:none;">
                    <div class="tool-group">
                        <label class="tool-label">Export Tokens (Backup)</label>
                        <div class="tool-actions">
                            <button class="btn btn-outline btn-sm" onclick="ApiTokenTool.exportAll()">Export JSON</button>
                        </div>
                    </div>
                    <div class="tool-group">
                        <label class="tool-label">Import Tokens</label>
                        <textarea class="tool-input" id="tokenImportData" placeholder="Paste exported JSON here..."></textarea>
                        <div class="tool-actions" style="margin-top:8px;">
                            <button class="btn btn-outline btn-sm" onclick="ApiTokenTool.importAll()">Import</button>
                        </div>
                    </div>
                    <div class="tool-group" style="margin-top:24px;border-top:1px solid var(--border);padding-top:16px;">
                        <label class="tool-label" style="color:var(--secondary)">Danger Zone</label>
                        <p style="color:var(--text-muted);font-size:0.85rem;margin-bottom:12px;">Reset master key will invalidate ALL existing tokens. This cannot be undone.</p>
                        <button class="btn btn-sm" style="background:var(--secondary);color:white;" onclick="ApiTokenTool.resetKey()">Reset Master Key</button>
                    </div>
                </div>
            </div>
            <style>
                .token-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px;}
                .token-stat{background:var(--bg-card);border:1px solid var(--border);border-radius:8px;padding:12px;text-align:center;}
                .token-stat .val{font-size:1.5rem;font-weight:700;color:var(--primary);}
                .token-stat .lbl{font-size:0.75rem;color:var(--text-muted);margin-top:2px;}
                .token-tabs{display:flex;gap:4px;margin-bottom:20px;border-bottom:1px solid var(--border);padding-bottom:0;}
                .token-tab{background:none;border:none;color:var(--text-muted);padding:10px 16px;cursor:pointer;font-size:0.9rem;border-bottom:2px solid transparent;transition:all 0.2s;}
                .token-tab:hover{color:var(--text);}
                .token-tab.active{color:var(--primary);border-bottom-color:var(--primary);}
                .token-scopes{display:flex;flex-wrap:wrap;gap:8px;}
                .token-scope{display:flex;align-items:center;gap:6px;padding:6px 12px;background:var(--bg-input);border:1px solid var(--border);border-radius:20px;font-size:0.8rem;cursor:pointer;transition:all 0.2s;color:var(--text-muted);}
                .token-scope:hover{border-color:var(--primary);}
                .token-scope.selected{background:rgba(108,99,255,0.2);border-color:var(--primary);color:var(--primary);}
                .token-scope input{display:none;}
                .token-created{background:var(--bg-card);border:1px solid var(--success);border-radius:8px;padding:16px;}
                .token-created .token-value{font-family:'Fira Code',monospace;font-size:0.75rem;word-break:break-all;background:var(--bg-input);padding:12px;border-radius:6px;margin:12px 0;user-select:all;max-height:100px;overflow-y:auto;line-height:1.5;}
                .token-card{background:var(--bg-card);border:1px solid var(--border);border-radius:8px;padding:16px;margin-bottom:10px;}
                .token-card.revoked{opacity:0.5;}
                .token-card-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;}
                .token-card-name{font-weight:600;font-size:0.95rem;}
                .token-badge{padding:2px 8px;border-radius:10px;font-size:0.7rem;font-weight:600;}
                .token-badge.active{background:rgba(44,182,125,0.2);color:var(--success);}
                .token-badge.revoked{background:rgba(255,101,132,0.2);color:var(--secondary);}
                .token-badge.expired{background:rgba(255,137,6,0.2);color:var(--warning);}
                .token-card-meta{font-size:0.8rem;color:var(--text-muted);display:grid;grid-template-columns:1fr 1fr;gap:4px 16px;margin:8px 0;}
                .token-card-scopes{display:flex;flex-wrap:wrap;gap:4px;margin:8px 0;}
                .token-card-scopes span{background:rgba(108,99,255,0.15);color:var(--primary);padding:2px 8px;border-radius:10px;font-size:0.7rem;}
                .token-card-actions{display:flex;gap:8px;margin-top:8px;}
                @media(max-width:768px){.token-stats{grid-template-columns:repeat(2,1fr);}.token-card-meta{grid-template-columns:1fr;}}
            </style>
        `;
    }
});

const ApiTokenTool = {
    _currentTab: 'create',

    switchTab(tab) {
        this._currentTab = tab;
        document.querySelectorAll('.token-tab').forEach((t, i) => {
            t.classList.toggle('active', ['create', 'list', 'validate', 'settings'][i] === tab);
        });
        document.querySelectorAll('.token-panel').forEach(p => p.style.display = 'none');
        const panel = document.getElementById('panel-' + tab);
        if (panel) panel.style.display = '';

        if (tab === 'create') this._renderScopes();
        if (tab === 'list') this._renderList();
        this._renderStats();
    },

    _renderStats() {
        const stats = TokenManager.getStats();
        const el = document.getElementById('tokenStats');
        if (!el) return;
        el.innerHTML = `
            <div class="token-stat"><div class="val">${stats.total}</div><div class="lbl">Total</div></div>
            <div class="token-stat"><div class="val" style="color:var(--success)">${stats.active}</div><div class="lbl">Active</div></div>
            <div class="token-stat"><div class="val" style="color:var(--secondary)">${stats.revoked}</div><div class="lbl">Revoked</div></div>
            <div class="token-stat"><div class="val" style="color:var(--warning)">${stats.totalUses}</div><div class="lbl">Total Uses</div></div>
        `;
    },

    _renderScopes() {
        const el = document.getElementById('tokenScopes');
        if (!el) return;
        const tools = typeof ToolsRegistry !== 'undefined' ? ToolsRegistry.getAll() : [];
        const categories = [...new Set(tools.map(t => t.category))];

        el.innerHTML = `
            <div class="token-scope selected" onclick="ApiTokenTool._toggleScope(this)" data-scope="*">
                All Tools
            </div>
            ${categories.map(cat => `
                <div class="token-scope" onclick="ApiTokenTool._toggleScope(this)" data-scope="${cat}">
                    ${cat.charAt(0).toUpperCase() + cat.slice(1)}
                </div>
            `).join('')}
            ${tools.filter(t => t.id !== 'api-token-manager').map(t => `
                <div class="token-scope" onclick="ApiTokenTool._toggleScope(this)" data-scope="${t.id}">
                    ${t.icon} ${t.name}
                </div>
            `).join('')}
        `;
    },

    _toggleScope(el) {
        const scope = el.dataset.scope;
        if (scope === '*') {
            // Selecting 'all' deselects everything else
            document.querySelectorAll('.token-scope').forEach(s => s.classList.remove('selected'));
            el.classList.add('selected');
        } else {
            // Deselect 'all' when selecting specific scopes
            document.querySelector('.token-scope[data-scope="*"]')?.classList.remove('selected');
            el.classList.toggle('selected');
            // If nothing selected, re-select 'all'
            if (!document.querySelector('.token-scope.selected')) {
                document.querySelector('.token-scope[data-scope="*"]').classList.add('selected');
            }
        }
    },

    _getSelectedScopes() {
        const selected = document.querySelectorAll('.token-scope.selected');
        return Array.from(selected).map(s => s.dataset.scope);
    },

    async create() {
        const name = document.getElementById('tokenName').value.trim();
        const expiresIn = parseInt(document.getElementById('tokenExpiry').value);
        const maxUses = parseInt(document.getElementById('tokenMaxUses').value) || 0;
        const scopes = this._getSelectedScopes();

        if (!name) {
            this._showResult('tokenCreateResult', 'Please enter a token name.', 'error');
            return;
        }

        try {
            const { token, record } = await TokenManager.createToken({ name, scopes, expiresIn, maxUses });

            document.getElementById('tokenCreateResult').innerHTML = `
                <div class="token-created">
                    <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
                        <span style="color:var(--success);font-size:1.2rem;">\u2713</span>
                        <strong>Token Created Successfully</strong>
                    </div>
                    <p style="color:var(--warning);font-size:0.8rem;margin-bottom:8px;">
                        Copy this token now. You won't be able to see it again!
                    </p>
                    <div class="token-value" id="createdTokenValue">${token}</div>
                    <div style="display:flex;gap:8px;">
                        <button class="btn btn-primary btn-sm" onclick="ApiTokenTool._copyCreated()">Copy Token</button>
                        <span class="copy-feedback" id="tokenCopyFb">Copied!</span>
                    </div>
                    <div style="margin-top:12px;font-size:0.8rem;color:var(--text-muted);">
                        <div>ID: <code>${record.jti}</code></div>
                        <div>Scopes: ${record.scopes.join(', ')}</div>
                        <div>Expires: ${record.expiresAt || 'Never'}</div>
                        <div>Max Uses: ${record.maxUses || 'Unlimited'}</div>
                    </div>
                </div>
            `;
            this._renderStats();
            document.getElementById('tokenName').value = '';
        } catch (e) {
            this._showResult('tokenCreateResult', 'Error: ' + e.message, 'error');
        }
    },

    _copyCreated() {
        const val = document.getElementById('createdTokenValue')?.textContent;
        if (val) {
            navigator.clipboard.writeText(val);
            const fb = document.getElementById('tokenCopyFb');
            fb.classList.add('show');
            setTimeout(() => fb.classList.remove('show'), 1500);
        }
    },

    _renderList() {
        const el = document.getElementById('tokenList');
        if (!el) return;
        const tokens = TokenManager.listTokens();

        if (tokens.length === 0) {
            el.innerHTML = '<p style="color:var(--text-muted);text-align:center;padding:40px 0;">No tokens created yet. Go to "Create Token" to get started.</p>';
            return;
        }

        el.innerHTML = tokens.map(t => {
            const now = new Date();
            const expired = t.expiresAt && new Date(t.expiresAt) < now;
            const status = t.revoked ? 'revoked' : expired ? 'expired' : 'active';
            const statusLabel = t.revoked ? 'Revoked' : expired ? 'Expired' : 'Active';

            return `
                <div class="token-card ${t.revoked ? 'revoked' : ''}">
                    <div class="token-card-header">
                        <span class="token-card-name">${this._esc(t.name)}</span>
                        <span class="token-badge ${status}">${statusLabel}</span>
                    </div>
                    <div class="token-card-meta">
                        <div>ID: <code style="font-size:0.75rem">${t.jti}</code></div>
                        <div>Uses: ${t.usageCount}${t.maxUses ? '/' + t.maxUses : ''}</div>
                        <div>Created: ${this._fmtDate(t.createdAt)}</div>
                        <div>Expires: ${t.expiresAt ? this._fmtDate(t.expiresAt) : 'Never'}</div>
                        ${t.lastUsed ? '<div>Last Used: ' + this._fmtDate(t.lastUsed) + '</div>' : ''}
                    </div>
                    <div class="token-card-scopes">
                        ${t.scopes.map(s => '<span>' + this._esc(s) + '</span>').join('')}
                    </div>
                    <div class="token-card-actions">
                        ${!t.revoked ? `<button class="btn btn-outline btn-sm" style="padding:4px 12px;font-size:0.75rem;" onclick="ApiTokenTool.revoke('${t.jti}')">Revoke</button>` : ''}
                        <button class="btn btn-sm" style="padding:4px 12px;font-size:0.75rem;background:var(--secondary);color:white;" onclick="ApiTokenTool.remove('${t.jti}')">Delete</button>
                    </div>
                </div>
            `;
        }).join('');
    },

    async validate() {
        const token = document.getElementById('tokenValidateInput').value.trim();
        if (!token) {
            this._showResult('tokenValidateResult', 'Please paste a token.', 'error');
            return;
        }

        const result = await TokenManager.validateToken(token);
        const el = document.getElementById('tokenValidateResult');

        if (result.valid) {
            el.innerHTML = `
                <div style="background:var(--bg-card);border:1px solid var(--success);border-radius:8px;padding:16px;">
                    <div style="color:var(--success);font-weight:600;margin-bottom:8px;">\u2713 Valid Token</div>
                    <div style="font-size:0.85rem;color:var(--text-muted);">
                        <div>Name: ${this._esc(result.payload.name)}</div>
                        <div>ID: <code>${result.payload.jti}</code></div>
                        <div>Scopes: ${result.payload.scopes.join(', ')}</div>
                        <div>Issued: ${this._fmtDate(new Date(result.payload.iat * 1000).toISOString())}</div>
                        <div>Expires: ${result.payload.exp > 0 ? this._fmtDate(new Date(result.payload.exp * 1000).toISOString()) : 'Never'}</div>
                        <div>Uses: ${result.record ? result.record.usageCount : 'N/A'}${result.payload.maxUses ? '/' + result.payload.maxUses : ''}</div>
                    </div>
                </div>
            `;
        } else {
            el.innerHTML = `
                <div style="background:var(--bg-card);border:1px solid var(--secondary);border-radius:8px;padding:16px;">
                    <div style="color:var(--secondary);font-weight:600;margin-bottom:8px;">\u2717 Invalid Token</div>
                    <div style="font-size:0.85rem;color:var(--text-muted);">${this._esc(result.error)}</div>
                    ${result.payload ? `<div style="font-size:0.8rem;color:var(--text-muted);margin-top:8px;">Token ID: ${result.payload.jti}</div>` : ''}
                </div>
            `;
        }
    },

    revoke(jti) {
        if (confirm('Revoke this token? It will no longer be accepted.')) {
            TokenManager.revokeToken(jti);
            this._renderList();
            this._renderStats();
        }
    },

    remove(jti) {
        if (confirm('Delete this token permanently? This cannot be undone.')) {
            TokenManager.deleteToken(jti);
            this._renderList();
            this._renderStats();
        }
    },

    exportAll() {
        const data = TokenManager.exportTokens();
        const blob = new Blob([data], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'toolbox-pro-tokens-' + new Date().toISOString().slice(0, 10) + '.json';
        a.click();
        URL.revokeObjectURL(url);
    },

    importAll() {
        const data = document.getElementById('tokenImportData').value.trim();
        if (!data) return;
        const result = TokenManager.importTokens(data);
        if (result.success) {
            this._showResult('tokenImportData', `Imported ${result.imported} token(s).`, 'success');
            document.getElementById('tokenImportData').value = '';
            this._renderStats();
        } else {
            alert('Import failed: ' + result.error);
        }
    },

    resetKey() {
        if (confirm('WARNING: This will invalidate ALL existing tokens. Are you sure?')) {
            if (confirm('This CANNOT be undone. All tokens will stop working. Continue?')) {
                TokenManager.resetMasterKey();
                this._renderStats();
                this._renderList();
                alert('Master key reset. All previous tokens are now invalid.');
            }
        }
    },

    _showResult(containerId, msg, type) {
        const el = document.getElementById(containerId);
        if (!el) return;
        const color = type === 'error' ? 'var(--secondary)' : 'var(--success)';
        el.innerHTML = `<p style="color:${color};font-size:0.85rem;">${this._esc(msg)}</p>`;
    },

    _esc(str) {
        const d = document.createElement('div');
        d.textContent = str;
        return d.innerHTML;
    },

    _fmtDate(iso) {
        try {
            const d = new Date(iso);
            return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } catch { return iso; }
    }
};

// Auto-render stats and scopes when tool opens
(function() {
    const _origOpen = window.__openTool;
    if (_origOpen) {
        window.__openTool = function(id) {
            _origOpen(id);
            if (id === 'api-token-manager') {
                setTimeout(() => {
                    ApiTokenTool._renderStats();
                    ApiTokenTool._renderScopes();
                }, 50);
            }
        };
    }
})();
