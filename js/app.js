/**
 * ToolBox Pro - Main Application Controller
 */
(function() {
    'use strict';

    // DOM Elements
    const toolsGrid = document.getElementById('toolsGrid');
    const searchInput = document.getElementById('searchInput');
    const modalOverlay = document.getElementById('modalOverlay');
    const modalTitle = document.getElementById('modalTitle');
    const modalBody = document.getElementById('modalBody');
    const modalClose = document.getElementById('modalClose');
    const menuToggle = document.getElementById('menuToggle');
    const navLinks = document.querySelector('.nav-links');
    const toolCount = document.getElementById('toolCount');
    const premiumBtn = document.getElementById('premiumBtn');

    // State
    let isPremium = localStorage.getItem('tbp_premium') === 'true';

    // Initialize
    function init() {
        renderTools(ToolsRegistry.getAll());
        toolCount.textContent = ToolsRegistry.getAll().length;
        bindEvents();
        checkPremium();
        handlePWAInstall();

        // Auto-open tool if URL has hash
        if (window.location.hash) {
            const toolId = window.location.hash.slice(1);
            const tool = ToolsRegistry.getById(toolId);
            if (tool) openTool(tool);
        }
    }

    // Render tool cards
    function renderTools(tools) {
        toolsGrid.innerHTML = tools.map(tool => `
            <div class="tool-card" data-id="${tool.id}" data-category="${tool.category}" onclick="window.__openTool('${tool.id}')">
                <span class="tool-icon">${tool.icon}</span>
                <h3>${tool.name}</h3>
                <p>${tool.description}</p>
                <span class="tool-tag">${tool.category}</span>
            </div>
        `).join('');
    }

    // Open tool in modal
    function openTool(tool) {
        modalTitle.textContent = tool.name;
        modalBody.innerHTML = tool.render();
        modalOverlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        window.location.hash = tool.id;

        // Auto-initialize tools that need it
        if (tool.id === 'color-palette') {
            setTimeout(() => ColorPalette.generate(), 50);
        }
        if (tool.id === 'markdown-preview') {
            setTimeout(() => MarkdownPreview.render(), 50);
        }
        if (tool.id === 'api-token-manager') {
            setTimeout(() => {
                ApiTokenTool._renderStats();
                ApiTokenTool._renderScopes();
            }, 50);
        }

        // Track usage for free tier limits
        trackUsage(tool.id);
    }

    window.__openTool = function(id) {
        const tool = ToolsRegistry.getById(id);
        if (tool) openTool(tool);
    };

    // Close modal
    function closeModal() {
        modalOverlay.classList.remove('active');
        document.body.style.overflow = '';
        history.replaceState(null, '', window.location.pathname);
    }

    // Search
    function handleSearch(e) {
        const query = e.target.value.trim();
        if (!query) {
            renderTools(ToolsRegistry.getAll());
            return;
        }
        const results = ToolsRegistry.search(query);
        renderTools(results);
    }

    // Category filter
    function handleCategoryClick(e) {
        const card = e.target.closest('.category-card');
        if (!card) return;
        const category = card.dataset.category;
        const tools = ToolsRegistry.getByCategory(category);
        renderTools(tools);
        document.getElementById('tools').scrollIntoView({ behavior: 'smooth' });
        searchInput.value = category;
    }

    // Premium check
    function checkPremium() {
        if (isPremium) {
            document.body.classList.add('premium');
            premiumBtn.textContent = 'PRO \u2713';
            premiumBtn.style.opacity = '0.7';
        }
    }

    // Usage tracking (for freemium limits)
    function trackUsage(toolId) {
        if (isPremium) return;
        const today = new Date().toISOString().slice(0, 10);
        const key = `tbp_usage_${today}`;
        const usage = JSON.parse(localStorage.getItem(key) || '{}');
        usage[toolId] = (usage[toolId] || 0) + 1;
        localStorage.setItem(key, JSON.stringify(usage));
    }

    // PWA Install
    let deferredPrompt;
    function handlePWAInstall() {
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            document.getElementById('installPrompt').style.display = 'flex';
        });

        document.getElementById('installBtn').addEventListener('click', async () => {
            if (deferredPrompt) {
                deferredPrompt.prompt();
                await deferredPrompt.userChoice;
                deferredPrompt = null;
                document.getElementById('installPrompt').style.display = 'none';
            }
        });

        document.getElementById('dismissInstall').addEventListener('click', () => {
            document.getElementById('installPrompt').style.display = 'none';
        });
    }

    // Bind events
    function bindEvents() {
        searchInput.addEventListener('input', handleSearch);
        modalClose.addEventListener('click', closeModal);
        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) closeModal();
        });
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') closeModal();
        });
        menuToggle.addEventListener('click', () => {
            navLinks.classList.toggle('open');
        });

        // Category clicks
        document.querySelectorAll('.category-card').forEach(card => {
            card.addEventListener('click', handleCategoryClick);
        });

        premiumBtn.addEventListener('click', () => {
            document.getElementById('premium').scrollIntoView({ behavior: 'smooth' });
        });
    }

    // Upgrade handler (placeholder for payment integration)
    window.handleUpgrade = function(plan) {
        alert(`Premium ${plan} plan - Payment integration coming soon!\n\nFor now, all tools are free to use.`);
    };

    // Init on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
