import * as monaco from "monaco-editor";

const MonacoEditor = {
  mounted() {
    const targetId = this.el.dataset.target;
    this.hiddenInput = document.getElementById(targetId);

    if (!this.hiddenInput) {
      console.error("MonacoEditor hook: could not find target input", targetId);
      return;
    }

    const initialValue = this.el.dataset.value || "";
    // The app only ships two daisyUI themes ("light"/"dark", see assets/css/app.css),
    // toggled explicitly by the user and reflected on <html data-theme="...">
    // (see root.html.heex). Prefer that explicit choice over the OS setting, which
    // only applies when the user hasn't picked a theme (no data-theme attribute).
    const dataTheme = document.documentElement.getAttribute("data-theme");
    const isDark = dataTheme
      ? dataTheme === "dark"
      : window.matchMedia("(prefers-color-scheme: dark)").matches;

    this.editor = monaco.editor.create(this.el, {
      value: initialValue,
      language: "lua",
      theme: isDark ? "vs-dark" : "vs",
      automaticLayout: true,
      minimap: { enabled: false },
    });

    this.debounceTimer = null;

    // Debounce sync to the hidden input so we don't flood the DOM/LiveView on
    // every keystroke; dispatching a native "input" event (rather than
    // pushEvent) keeps the value in sync with the surrounding <form>'s normal
    // submit/validate flow without adding a LiveView round-trip.
    this.editor.onDidChangeModelContent(() => {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.hiddenInput.value = this.editor.getValue();
        this.hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
      }, 300);
    });

    // Flush immediately on blur so a fast click on Save/Run (which blurs the
    // editor before the click handler runs) never submits a stale value.
    this.editor.onDidBlurEditorWidget(() => {
      clearTimeout(this.debounceTimer);
      this.hiddenInput.value = this.editor.getValue();
      this.hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
    });
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
    this.editor?.dispose();
  },
};

export default MonacoEditor;
