# Contact NIF changes

Update existing projected contacts by stable ID, scoped to their company. Keep the NIF/company upsert for events without an existing ID, preserving legacy behavior. Remove the previous NIF key from aggregate state when the same non-null ID changes NIF. Preserve event replay compatibility without changing stored events or projection checkpoints.
