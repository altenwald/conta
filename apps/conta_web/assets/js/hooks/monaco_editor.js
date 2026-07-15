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
    // native "input" event bubbling into the surrounding <form>'s
    // phx-change="validate" would re-render the page while the editor
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

    // Monaco's own keyboard-capture element is a real <textarea>, and every
    // keystroke inside it fires native "input"/"change" events that bubble
    // by default - straight past this ignored container into the form,
    // triggering phx-change="validate" on every keystroke regardless of the
    // blur-only sync above. That is the actual trigger for the corruption
    // described above: it was never fully fixed, just made less frequent.
    // Stop those native events at the container boundary; our own
    // synthetic dispatch above targets the hidden input, which lives
    // outside this container, so it is unaffected.
    this.el.addEventListener("input", (e) => e.stopPropagation());
    this.el.addEventListener("change", (e) => e.stopPropagation());
  },

  destroyed() {
    this.editor?.dispose();
  },
};

export default MonacoEditor;
