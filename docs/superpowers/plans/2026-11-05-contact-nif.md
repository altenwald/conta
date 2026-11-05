# Contact NIF fix

- [x] Reproduce projection crash and stale aggregate key with failing tests.
- [x] Update projection by stable ID and replace the aggregate NIF key.
- [x] Run focused tests, mix test and mix check.

Validation: 31 focused tests and 673 full-suite tests pass. Format, Credo, Doctor, Sobelow and audit pass. Compiler and Dialyzer report existing warnings in unchanged files; no diagnostics target the changed code.
