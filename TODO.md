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

## Projector: `:consistency` no se propaga a `Commanded.Event.Handler`

`Conta.Projector` (`apps/conta/lib/conta/projector.ex:25`) hace
`Keyword.drop(@opts, [:repo, :timeout, :consistency])` antes de pasar las
opciones a `use Commanded.Event.Handler`. Esto descarta la opción
`:consistency` en **todos** los projectors de la app (no solo uno concreto):
da igual que un módulo declare `consistency: Application.compile_env(:conta,
:consistency, :eventual)` o que el config tenga `consistency: :strong` — el
handler siempre queda registrado como `:eventual`.

Consecuencia práctica: pedir `dispatch(command, consistency: :strong)` en
cualquier punto de la app es un no-op silencioso — no falla, pero tampoco
espera a que el projector correspondiente termine de escribir en Postgres,
porque Commanded solo espera a los handlers que estén realmente registrados
como `:strong`. Se detectó al implementar `Conta.Reconciliation.confirm_movement/1`
(conciliación bancaria): un `update_movement/2` seguido inmediatamente de una
lectura del read-model puede ver datos aún no proyectados. Se evitó en los
tests con un polling acotado (`eventually/1,2` en
`apps/conta/test/conta/reconciliation_context_test.exs`), pero el mismo hueco
existe en producción para cualquier llamador que encadene un dispatch con una
lectura inmediata del read-model.

Arreglo: que `Conta.Projector` deje pasar `:consistency` a
`Commanded.Event.Handler` (quitarla de la lista de `Keyword.drop/2`), y
revisar qué projectors deberían pasar a `:strong` de verdad.

## `Reconciliation.get_set_match_rule/1` no fija `:id` en las condiciones existentes

`get_set_match_rule/1` (`apps/conta/lib/conta/reconciliation.ex`) construye el
`SetMatchRule` de edición a partir del read-model sin asignar `:id` a cada
`SetMatchRule.Condition`. Como el embed usa la primary key por defecto de Ecto
(`:id`), cualquier sesión de edición real con 2+ condiciones que pulse "Add
condition" dispara un warning de Ecto:

```
found duplicate primary keys for association/embed :conditions in
Conta.Command.SetMatchRule ... only the last entry with the same ID will be
kept
```

Detectado durante la revisión de calidad de la Task 28 (pantalla de
Concordancias) al añadir un test de regresión que abre el formulario de
edición con condiciones ya existentes. El test sigue pasando (el warning no
afecta al HTML renderizado en este camino), pero es una señal de un problema
latente en el diseño del schema del embed — antes de que se le den ids reales
usados para identificar filas individualmente (p. ej. al implementar borrado
de una condición concreta en vez de por índice), revisar si el embed necesita
`primary_key: false` o si `get_set_match_rule/1` debe asignar `:id` explícito
por condición.
