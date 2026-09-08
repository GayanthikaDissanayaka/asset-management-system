/* ---------------------------------------------------------------------
   Shared presentation components.
   Plain React — copy these straight into src/components/ when you move
   to a Vite or Create React App build.
   --------------------------------------------------------------------- */

const { useState, useEffect, useMemo, useCallback } = React;

const fmt = n => Number(n || 0).toLocaleString("en-LK");

const fmtKva = n => {
  const v = Number(n) || 0;
  return v >= 1000 ? (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + " MVA" : v + " kVA";
};

/* --- headline figures ----------------------------------------------- */

function Figures({ items }) {
  return (
    <dl className="figures">
      {items.map(it => (
        <div key={it.label}>
          <dt>{it.label}</dt>
          <dd>{it.value}{it.unit && <small>{it.unit}</small>}</dd>
        </div>
      ))}
    </dl>
  );
}

/* --- the busbar ------------------------------------------------------

   Drawn the way the depots' own single-line diagram book draws it: one
   33 kV bus across the top, a drop per area, and a column per CSC whose
   depth is the installed capacity sitting behind it.
   -------------------------------------------------------------------- */

function Busbar({ depots }) {
  const W = 900, BUS_Y = 46, GROUP_Y = 74, TOP_Y = 94, MAX_H = 118, LABEL_Y = 240;

  // Keep the depots in network order (area by area) rather than by size,
  // so the diagram reads like the book rather than like a ranking.
  const ordered = useMemo(() => {
    const byArea = new Map(AREA_ORDER.map(a => [a, []]));
    depots.forEach(d => {
      const area = d.area_name || AREA_OF_DEPOT[d.depot_name];
      if (byArea.has(area)) byArea.get(area).push(d);
    });
    return AREA_ORDER.map(area => ({
      area,
      depots: byArea.get(area).sort((a, b) => a.depot_name.localeCompare(b.depot_name)),
    })).filter(g => g.depots.length);
  }, [depots]);

  const flat = ordered.flatMap(g => g.depots);
  if (!flat.length) return null;

  const peak = Math.max(...flat.map(d => Number(d.total_kva) || 0), 1);
  const slot = (W - 80) / flat.length;
  const xAt = i => 40 + slot * i + slot / 2;

  let cursor = 0;
  const groups = ordered.map(g => {
    const start = cursor;
    cursor += g.depots.length;
    return { ...g, start, end: cursor - 1 };
  });

  return (
    <div className="busbar">
      <svg viewBox={`0 0 ${W} 300`} role="img"
           aria-label="Installed transformer capacity at each customer service centre, grouped by area">

        {/* the 33 kV bus */}
        <line className="bus-line" x1="40" y1={BUS_Y} x2={W - 40} y2={BUS_Y} />

        {groups.map(g => {
          const x1 = xAt(g.start), x2 = xAt(g.end), mid = (x1 + x2) / 2;
          const areaKva = g.depots.reduce((s, d) => s + (Number(d.total_kva) || 0), 0);
          return (
            <g key={g.area}>
              {/* area name and load sit above the bus, clear of the drop lines */}
              <text className="bus-area" x={mid} y="18" textAnchor="middle">{g.area}</text>
              <text className="bus-cap" x={mid} y="31" textAnchor="middle">{fmtKva(areaKva)}</text>
              <line className="bus-drop" x1={mid} y1={BUS_Y} x2={mid} y2={GROUP_Y} />
              <line className="bus-drop" x1={x1} y1={GROUP_Y} x2={x2} y2={GROUP_Y} />
            </g>
          );
        })}

        {flat.map((d, i) => {
          const x = xAt(i);
          const kva = Number(d.total_kva) || 0;
          const h = kva ? Math.max((kva / peak) * MAX_H, 3) : 0;
          const w = Math.min(slot * 0.46, 22);
          const isPeak = kva === peak;

          return (
            <g key={d.depot_name}>
              <title>{`${d.depot_name}: ${fmt(d.depot_total)} units, ${fmtKva(kva)}`}</title>
              <line className="bus-drop" x1={x} y1={GROUP_Y} x2={x} y2={TOP_Y} />
              {h > 0 ? (
                <rect className={`bus-col${isPeak ? " hi" : ""}`}
                      x={x - w / 2} y={TOP_Y} width={w} height={h} />
              ) : (
                <line className="bus-tick" x1={x - w / 2} y1={TOP_Y} x2={x + w / 2} y2={TOP_Y} />
              )}
              <text className="bus-val" x={x} y={TOP_Y + h + 12} textAnchor="middle">
                {kva ? fmt(d.depot_total) : "—"}
              </text>
              <text className="bus-name" x={x} y={LABEL_Y}
                    textAnchor="end" transform={`rotate(-45 ${x} ${LABEL_Y})`}
                    opacity={kva ? 1 : 0.45}>
                {d.depot_name}
              </text>
            </g>
          );
        })}
      </svg>

      <p className="legend">
        <span>Bar across the top is the 33 kV supply</span>
        <span><i style={{ background: "var(--rail-lt)" }} />Column depth is installed capacity</span>
        <span><i style={{ background: "var(--live)" }} />Largest depot</span>
        <span>Number under each column is the unit count. A flat line means no records yet.</span>
      </p>
    </div>
  );
}

/* --- small pieces ---------------------------------------------------- */

function Pill({ status }) {
  return <span className={`pill ${status}`}>{String(status).replace("_", " ")}</span>;
}

function Sheet({ children }) {
  return <div className="sheet">{children}</div>;
}

function Empty({ children }) {
  return <div className="empty">{children}</div>;
}

/** A table cell that shows a number and a proportional rule beneath it. */
function BarCell({ value, peak, format = fmt }) {
  const pct = peak ? Math.max((Number(value) / peak) * 100, value ? 2 : 0) : 0;
  return (
    <td className="num">
      {format(value)}
      <span className="bar" style={{ width: `${pct}%` }} />
    </td>
  );
}

function Pager({ meta, onPage }) {
  if (!meta || meta.last_page <= 1) {
    return <p className="pager">{fmt(meta?.total)} records</p>;
  }
  return (
    <div className="pager">
      <button className="quiet" disabled={meta.page <= 1} onClick={() => onPage(meta.page - 1)}>
        Previous
      </button>
      <span>
        Page {fmt(meta.page)} of {fmt(meta.last_page)} · {fmt(meta.total)} records
      </span>
      <button className="quiet" disabled={meta.page >= meta.last_page} onClick={() => onPage(meta.page + 1)}>
        Next
      </button>
    </div>
  );
}

/** Slide-over panel used for asset detail. */
function Drawer({ onClose, children }) {
  useEffect(() => {
    const esc = e => e.key === "Escape" && onClose();
    window.addEventListener("keydown", esc);
    return () => window.removeEventListener("keydown", esc);
  }, [onClose]);

  return (
    <div className="scrim" onClick={onClose}>
      <aside className="drawer" onClick={e => e.stopPropagation()}>
        <button className="quiet drawer-close" onClick={onClose}>Close</button>
        {children}
      </aside>
    </div>
  );
}

Object.assign(window, { fmt, fmtKva, Figures, Busbar, Pill, Sheet, Empty, BarCell, Pager, Drawer });
