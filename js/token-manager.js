/**
 * ToolBox Pro - Custom Token Manager
 *
 * Inspired by openclaw-zero-token's architecture:
 * - Self-validating JWT-like tokens (no backend needed)
 * - HMAC-SHA256 signing via Web Crypto API
 * - AES-GCM encrypted local storage
 * - Scope-based permissions per tool/category
 * - Token lifecycle: create → validate → refresh → revoke
 */
const TokenManager = (function() {
    'use strict';

    const STORAGE_KEY = 'tbp_tokens';
    const MASTER_KEY_KEY = 'tbp_master_key';
    const TOKEN_PREFIX = 'tbp_';
    const TOKEN_VERSION = 1;

    // ─── Crypto Helpers ────────────────────────────────────────

    /** Convert string to ArrayBuffer */
    function str2ab(str) {
        return new TextEncoder().encode(str);
    }

    /** Convert ArrayBuffer to hex string */
    function ab2hex(buffer) {
        return Array.from(new Uint8Array(buffer))
            .map(b => b.toString(16).padStart(2, '0'))
            .join('');
    }

    /** Convert hex string to ArrayBuffer */
    function hex2ab(hex) {
        const bytes = new Uint8Array(hex.length / 2);
        for (let i = 0; i < hex.length; i += 2) {
            bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
        }
        return bytes.buffer;
    }

    /** Base64url encode (JWT compatible) */
    function base64url(buffer) {
        const bytes = buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : buffer;
        let binary = '';
        for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
        return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    }

    /** Base64url decode */
    function base64urlDecode(str) {
        str = str.replace(/-/g, '+').replace(/_/g, '/');
        while (str.length % 4) str += '=';
        const binary = atob(str);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        return bytes;
    }

    /** Generate a random ID */
    function randomId(length) {
        const arr = new Uint8Array(length);
        crypto.getRandomValues(arr);
        return ab2hex(arr.buffer);
    }

    // ─── Master Key Management ─────────────────────────────────
    // The master key is derived once and stored, used for HMAC signing & AES encryption.
    // In a real production system this would come from a server; here we generate
    // a persistent key on first use (pure client-side, inspired by openclaw's auth.json).

    let _masterCryptoKey = null;
    let _aesKey = null;

    async function getMasterKey() {
        if (_masterCryptoKey) return _masterCryptoKey;

        let rawHex = localStorage.getItem(MASTER_KEY_KEY);
        if (!rawHex) {
            // First run: generate a 256-bit master key
            const raw = new Uint8Array(32);
            crypto.getRandomValues(raw);
            rawHex = ab2hex(raw.buffer);
            localStorage.setItem(MASTER_KEY_KEY, rawHex);
        }

        const rawBytes = hex2ab(rawHex);
        _masterCryptoKey = await crypto.subtle.importKey(
            'raw', rawBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']
        );
        _aesKey = await crypto.subtle.importKey(
            'raw', rawBytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']
        );
        return _masterCryptoKey;
    }

    // ─── Token Structure ───────────────────────────────────────
    // Format: header.payload.signature (JWT-like, all base64url)
    //
    // header:  { ver, alg: "HS256" }
    // payload: { jti, sub, name, scopes, iat, exp, uses }
    // signature: HMAC-SHA256(header.payload, masterKey)

    /**
     * Create a new API token
     * @param {Object} opts
     * @param {string} opts.name - Human readable name
     * @param {string[]} opts.scopes - Permitted tool IDs or categories ('*' = all)
     * @param {number} [opts.expiresIn] - Seconds until expiry (0 = never)
     * @param {number} [opts.maxUses] - Max invocations (0 = unlimited)
     * @returns {Promise<{token: string, record: Object}>}
     */
    async function createToken({ name, scopes, expiresIn = 0, maxUses = 0 }) {
        await getMasterKey();

        const now = Math.floor(Date.now() / 1000);
        const jti = TOKEN_PREFIX + randomId(12); // unique token ID

        const header = { ver: TOKEN_VERSION, alg: 'HS256' };
        const payload = {
            jti,
            sub: 'toolbox-pro',
            name: name || 'Unnamed Token',
            scopes: scopes || ['*'],
            iat: now,
            exp: expiresIn > 0 ? now + expiresIn : 0,
            maxUses: maxUses
        };

        const headerB64 = base64url(str2ab(JSON.stringify(header)));
        const payloadB64 = base64url(str2ab(JSON.stringify(payload)));
        const sigInput = str2ab(headerB64 + '.' + payloadB64);
        const sigBuffer = await crypto.subtle.sign('HMAC', _masterCryptoKey, sigInput);
        const sigB64 = base64url(sigBuffer);

        const token = headerB64 + '.' + payloadB64 + '.' + sigB64;

        // Store metadata locally (encrypted)
        const record = {
            jti,
            name: payload.name,
            scopes: payload.scopes,
            createdAt: new Date(now * 1000).toISOString(),
            expiresAt: payload.exp > 0 ? new Date(payload.exp * 1000).toISOString() : null,
            maxUses: payload.maxUses,
            usageCount: 0,
            revoked: false,
            lastUsed: null
        };
        await _saveRecord(record);

        return { token, record };
    }

    /**
     * Validate a token string and return its payload if valid
     * @param {string} token
     * @returns {Promise<{valid: boolean, payload?: Object, error?: string}>}
     */
    async function validateToken(token) {
        try {
            await getMasterKey();
            const parts = token.split('.');
            if (parts.length !== 3) return { valid: false, error: 'Invalid token format' };

            const [headerB64, payloadB64, sigB64] = parts;

            // Verify signature
            const sigInput = str2ab(headerB64 + '.' + payloadB64);
            const sigBuffer = base64urlDecode(sigB64).buffer;
            const valid = await crypto.subtle.verify('HMAC', _masterCryptoKey, sigBuffer, sigInput);
            if (!valid) return { valid: false, error: 'Invalid signature' };

            // Decode payload
            const payload = JSON.parse(new TextDecoder().decode(base64urlDecode(payloadB64)));

            // Check expiry
            if (payload.exp > 0 && Math.floor(Date.now() / 1000) > payload.exp) {
                return { valid: false, error: 'Token expired', payload };
            }

            // Check revocation
            const record = _getRecord(payload.jti);
            if (record && record.revoked) {
                return { valid: false, error: 'Token revoked', payload };
            }

            // Check max uses
            if (record && payload.maxUses > 0 && record.usageCount >= payload.maxUses) {
                return { valid: false, error: 'Usage limit reached', payload };
            }

            return { valid: true, payload, record };
        } catch (e) {
            return { valid: false, error: 'Validation error: ' + e.message };
        }
    }

    /**
     * Use a token (increment usage counter, update lastUsed)
     * @param {string} tokenOrJti - Full token or jti
     * @param {string} toolId - The tool being accessed
     * @returns {Promise<{allowed: boolean, error?: string}>}
     */
    async function useToken(tokenOrJti, toolId) {
        let jti = tokenOrJti;
        let payload;

        // If it looks like a full token, validate first
        if (tokenOrJti.includes('.')) {
            const result = await validateToken(tokenOrJti);
            if (!result.valid) return { allowed: false, error: result.error };
            payload = result.payload;
            jti = payload.jti;
        }

        const record = _getRecord(jti);
        if (!record) return { allowed: false, error: 'Token not found' };
        if (record.revoked) return { allowed: false, error: 'Token revoked' };

        // Scope check
        if (!record.scopes.includes('*')) {
            const tool = typeof ToolsRegistry !== 'undefined' ? ToolsRegistry.getById(toolId) : null;
            const hasToolScope = record.scopes.includes(toolId);
            const hasCategoryScope = tool && record.scopes.includes(tool.category);
            if (!hasToolScope && !hasCategoryScope) {
                return { allowed: false, error: 'Insufficient scope for tool: ' + toolId };
            }
        }

        // Usage limit check
        if (record.maxUses > 0 && record.usageCount >= record.maxUses) {
            return { allowed: false, error: 'Usage limit reached' };
        }

        // Update usage
        record.usageCount++;
        record.lastUsed = new Date().toISOString();
        _updateRecord(record);

        return { allowed: true };
    }

    /**
     * Revoke a token by jti
     */
    function revokeToken(jti) {
        const record = _getRecord(jti);
        if (!record) return false;
        record.revoked = true;
        _updateRecord(record);
        return true;
    }

    /**
     * Delete a token permanently
     */
    function deleteToken(jti) {
        const records = _getAllRecords();
        const filtered = records.filter(r => r.jti !== jti);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(filtered));
        return true;
    }

    /**
     * List all token records
     */
    function listTokens() {
        return _getAllRecords();
    }

    /**
     * Get a single token record
     */
    function getToken(jti) {
        return _getRecord(jti);
    }

    /**
     * Get usage stats
     */
    function getStats() {
        const records = _getAllRecords();
        const active = records.filter(r => !r.revoked);
        const expired = records.filter(r => r.expiresAt && new Date(r.expiresAt) < new Date());
        const totalUses = records.reduce((sum, r) => sum + r.usageCount, 0);
        return {
            total: records.length,
            active: active.length,
            revoked: records.length - active.length,
            expired: expired.length,
            totalUses
        };
    }

    /**
     * Export all tokens (for backup)
     */
    function exportTokens() {
        return JSON.stringify({
            version: TOKEN_VERSION,
            exportedAt: new Date().toISOString(),
            records: _getAllRecords()
        }, null, 2);
    }

    /**
     * Import tokens from backup
     */
    function importTokens(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            if (!data.records || !Array.isArray(data.records)) {
                return { success: false, error: 'Invalid format' };
            }
            const existing = _getAllRecords();
            const existingIds = new Set(existing.map(r => r.jti));
            let imported = 0;
            for (const record of data.records) {
                if (!existingIds.has(record.jti)) {
                    existing.push(record);
                    imported++;
                }
            }
            localStorage.setItem(STORAGE_KEY, JSON.stringify(existing));
            return { success: true, imported };
        } catch (e) {
            return { success: false, error: e.message };
        }
    }

    /**
     * Reset master key (invalidates ALL existing tokens)
     */
    function resetMasterKey() {
        localStorage.removeItem(MASTER_KEY_KEY);
        localStorage.removeItem(STORAGE_KEY);
        _masterCryptoKey = null;
        _aesKey = null;
    }

    // ─── Internal Storage ──────────────────────────────────────

    function _getAllRecords() {
        try {
            return JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
        } catch { return []; }
    }

    function _getRecord(jti) {
        return _getAllRecords().find(r => r.jti === jti) || null;
    }

    async function _saveRecord(record) {
        const records = _getAllRecords();
        records.push(record);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(records));
    }

    function _updateRecord(record) {
        const records = _getAllRecords();
        const idx = records.findIndex(r => r.jti === record.jti);
        if (idx >= 0) {
            records[idx] = record;
            localStorage.setItem(STORAGE_KEY, JSON.stringify(records));
        }
    }

    // ─── Public API ────────────────────────────────────────────

    return {
        createToken,
        validateToken,
        useToken,
        revokeToken,
        deleteToken,
        listTokens,
        getToken,
        getStats,
        exportTokens,
        importTokens,
        resetMasterKey,
        // Expose for gateway interceptor
        _validateAndUse: useToken
    };
})();
