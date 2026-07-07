import * as monaco from "monaco-editor";

const MonacoEditor = {
  mounted() {
    const targetId = this.el.dataset.target;
    this.hiddenInput = document.getElementById(targetId);
    const initialValue = this.el.dataset.value || "";
    const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;

    this.editor = monaco.editor.create(this.el, {
      value: initialValue,
      language: "lua",
      theme: isDark ? "vs-dark" : "vs",
      automaticLayout: true,
      minimap: { enabled: false },
    });

    this.debounceTimer = null;

    this.editor.onDidChangeModelContent(() => {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.hiddenInput.value = this.editor.getValue();
        this.hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
      }, 300);
    });
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
    this.editor?.dispose();
  },
};

export default MonacoEditor;
