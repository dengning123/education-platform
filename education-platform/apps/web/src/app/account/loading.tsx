export default function AccountLoading() {
  return (
    <section className="status-card" aria-live="polite" aria-busy="true">
      <span className="spinner" aria-hidden="true" />
      <div>
        <p className="eyebrow">ACCOUNT STATE</p>
        <h1>Checking your session</h1>
        <p className="muted">The protected area remains closed until identity verification completes.</p>
      </div>
    </section>
  );
}
