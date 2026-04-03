/**
 * ToolBox Pro - Tools Registry
 * Central registry for all tools. Each tool registers itself here.
 */
const ToolsRegistry = {
    tools: [],

    register(tool) {
        this.tools.push(tool);
    },

    getAll() {
        return this.tools;
    },

    getByCategory(category) {
        return this.tools.filter(t => t.category === category);
    },

    search(query) {
        const q = query.toLowerCase();
        return this.tools.filter(t =>
            t.name.toLowerCase().includes(q) ||
            t.description.toLowerCase().includes(q) ||
            t.tags.some(tag => tag.toLowerCase().includes(q))
        );
    },

    getById(id) {
        return this.tools.find(t => t.id === id);
    }
};
