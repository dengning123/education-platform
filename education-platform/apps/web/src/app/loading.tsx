export default function Loading() {
  return (
    <section className="status-card" aria-live="polite" aria-busy="true">
      <span className="spinner" aria-hidden="true" />
      <div>
        <p className="eyebrow">AUTHENTICATING</p>
        <h1>Restoring your secure session</h1>
        <p className="muted">Confirming identity with Supabase Auth.</p>
      </div>
    </section>
  );
}
