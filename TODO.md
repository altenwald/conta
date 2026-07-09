# TODO

## Monaco: web worker en segundo plano

Actualmente Monaco cae a ejecutar sus servicios (bracket matching, cálculo de
diffs, etc.) en el hilo principal porque no hay `MonacoEnvironment.getWorkerUrl`
/ `getWorker` configurado. Se ve en consola:

```
Could not create web worker(s). Falling back to loading web worker code in
main thread, which might cause UI freezes.
You must define a function MonacoEnvironment.getWorkerUrl or MonacoEnvironment.getWorker
```

No es grave para el uso actual (editor fijado a `language: "lua"`, scripts
pequeños), pero si el rendimiento se nota en documentos grandes, se puede
arreglar:

1. Añadir un entry point de worker (`editor.worker.js`) al bundle de esbuild
   (`config/config.exs`, perfil `bundle_monaco`).
2. Configurar `self.MonacoEnvironment = { getWorkerUrl: () => "/assets/editor.worker.js" }`
   antes de crear el editor en `apps/conta_web/assets/js/monaco_bundle.js`.
3. Añadir `worker-src 'self'` (o `blob:` si hace falta) a la CSP en
   `apps/conta_web/lib/conta_web/router.ex`.
