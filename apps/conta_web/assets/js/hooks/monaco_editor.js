const MonacoEditor = {
  mounted() {
    const monaco = window.MonacoEditorLib;

    if (!monaco) {
      console.error("MonacoEditor hook: window.MonacoEditorLib is not available (monaco_bundle.js failed to load or hasn't loaded yet)");
      return;
    }

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

    // Sync to the hidden input only on blur, not on every keystroke. A
    // native "input" event bubbles into the surrounding <form>'s
    // phx-change="validate", which re-renders the page while the editor
    // still has focus. Even though the editor's own container is
    // phx-update="ignore", that re-render of its siblings was enough to
    // corrupt Monaco's internal selection/keyboard state on macOS Chrome:
    // selecting text and pressing Delete/Backspace would silently stop
    // working (sometimes for the rest of the page's lifetime). Clicking
    // Save/Run always blurs the editor first, so the hidden input is
    // never stale at submit time.
    this.editor.onDidBlurEditorWidget(() => {
      this.hiddenInput.value = this.editor.getValue();
      this.hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
    });
  },

  destroyed() {
    this.editor?.dispose();
  },
};

export default MonacoEditor;
