/* ---------------------------------------------------------------------
   Screens and navigation.

   Three screens: the province overview, the searchable asset register,
   and the form for registering a new asset. The left rail doubles as the
   network hierarchy — clicking a CSC opens the register filtered to it.
   --------------------------------------------------------------------- */

/* --- overview -------------------------------------------------------- */

function Overview({ go }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    API.dashboard().then(setData).catch(e => setError(e.message));
  }, []);

  if (error) return <div className="note bad">{error}</div>;
  if (!data) return <p>Reading the asset register…</p>;

  const totalKva = data.depots.reduce((s, d) => s + (Number(d.total_kva) || 0), 0);
  const withData = data.depots.filter(d => d.depot_total > 0).length;
  const peakArea = Math.max(...data.areas.map(a => Number(a.area_total)), 1);
  const peakRating = Math.max(...(data.by_rating || []).map(r => Number(r.units)), 1);

  return (
    <>
      <div className="page-head">
        <h2>Uva Province network</h2>
        <p>
          Every asset recorded against a customer service centre, rolled up through
          its area to the province. The totals below are calculated by the database
          views, not by this page.
        </p>
      </div>

      <Busbar depots={data.depots} />

      <Figures items={[
        { label: "Assets on record", value: fmt(data.province.province_total) },
        { label: "Installed capacity", value: fmt(Math.round(totalKva / 1000)), unit: "MVA" },
        { label: "Areas", value: data.areas.length },
        { label: "Service centres reporting", value: `${withData} of ${data.depots.length}` },
      ]} />

      <h3>Areas</h3>
      <Sheet>
        <table>
          <thead>
            <tr><th>Area</th><th>Service centres</th><th className="num">Assets</th></tr>
          </thead>
          <tbody>
            {data.areas.map(a => (
              <tr key={a.area_name} className="click" onClick={() => go({ page: "register", area: a.area_name })}>
                <td>{a.area_name}</td>
                <td>{data.depots.filter(d => d.area_name === a.area_name).map(d => d.depot_name).join(", ")}</td>
                <BarCell value={a.area_total} peak={peakArea} />
              </tr>
            ))}
          </tbody>
        </table>
      </Sheet>

      <h3>Service centres</h3>
      <Sheet>
        <table>
          <thead>
            <tr>
              <th>Service centre</th><th>Area</th>
              <th className="num">Assets</th><th className="num">Installed kVA</th>
              <th className="num">Average kVA</th>
            </tr>
          </thead>
          <tbody>
            {data.depots.map(d => (
              <tr key={d.depot_name} className="click" onClick={() => go({ page: "register", depot: d.depot_name })}>
                <td>{d.depot_name}</td>
                <td>{d.area_name}</td>
                <td className="num">{fmt(d.depot_total)}</td>
                <td className="num">{fmt(Math.round(d.total_kva))}</td>
                <td className="num">
                  {d.depot_total ? fmt(Math.round(d.total_kva / d.depot_total)) : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Sheet>

      <h3>Ratings in service</h3>
      <p style={{ margin: "-.4rem 0 .85rem", color: "var(--ink-mid)", fontSize: ".875rem", maxWidth: "62ch" }}>
        Which transformer sizes the province actually runs. Useful when deciding
        what to hold in stores.
      </p>
      <Sheet>
        <table>
          <thead>
            <tr><th>Rating</th><th className="num">Units</th><th className="num">Share</th></tr>
          </thead>
          <tbody>
            {(data.by_rating || []).map(r => (
              <tr key={r.capacity_kva}>
                <td className="code">{fmt(r.capacity_kva)} kVA</td>
                <BarCell value={r.units} peak={peakRating} />
                <td className="num">
                  {((r.units / data.province.province_total) * 100).toFixed(1)}%
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Sheet>
    </>
  );
}

/* --- asset register -------------------------------------------------- */

function Register({ filter, reference, go }) {
  const [rows, setRows] = useState([]);
  const [meta, setMeta] = useState(null);
  const [search, setSearch] = useState("");
  const [depot, setDepot] = useState(filter.depot || "");
  const [area, setArea] = useState(filter.area || "");
  const [page, setPage] = useState(1);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(null);
  const [open, setOpen] = useState(null);

  // Follow rail clicks that arrive while this screen is already mounted.
  useEffect(() => {
    setDepot(filter.depot || "");
    setArea(filter.area || "");
    setPage(1);
  }, [filter.depot, filter.area]);

  const depotId = reference.depots.find(d => d.csc_name === depot)?.depot_id;
  const areaId = reference.areas.find(a => a.area_name === area)?.area_id;

  useEffect(() => {
    let cancelled = false;
    setBusy(true);
    API.assets({
      search, page, per_page: 40,
      depot: depotId, depot_name: depot,
      area: areaId, area_name: area,
    })
      .then(res => {
        if (cancelled) return;
        setRows(res.data);
        setMeta(res.meta);
        setError(null);
      })
      .catch(e => !cancelled && setError(e.message))
      .finally(() => !cancelled && setBusy(false));
    return () => { cancelled = true; };
  }, [search, page, depot, area, depotId, areaId]);

  const scope = depot || area || "Uva Province";

  return (
    <>
      <div className="page-head">
        <h2>Asset register</h2>
        <p>Showing assets for {scope}. Search by asset code or substation name.</p>
      </div>

      <div className="controls">
        <label className="field">
          Search
          <input className="search" value={search} placeholder="UBB 055, Lower King Street…"
                 onChange={e => { setSearch(e.target.value); setPage(1); }} />
        </label>

        <label className="field">
          Area
          <select value={area} onChange={e => { setArea(e.target.value); setDepot(""); setPage(1); }}>
            <option value="">All areas</option>
            {reference.areas.map(a => <option key={a.area_id}>{a.area_name}</option>)}
          </select>
        </label>

        <label className="field">
          Service centre
          <select value={depot} onChange={e => { setDepot(e.target.value); setPage(1); }}>
            <option value="">All service centres</option>
            {reference.depots
              .filter(d => !area || d.area_name === area)
              .map(d => <option key={d.depot_id}>{d.csc_name}</option>)}
          </select>
        </label>

        {(search || depot || area) && (
          <button className="quiet" onClick={() => { setSearch(""); setDepot(""); setArea(""); setPage(1); }}>
            Clear filters
          </button>
        )}
      </div>

      {error && <div className="note bad">{error}</div>}

      <Sheet>
        <table>
          <thead>
            <tr>
              <th>Code</th><th>Substation</th><th>Type</th>
              <th className="num">kVA</th><th>Service centre</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(r => (
              <tr key={r.asset_id} className="click" onClick={() => setOpen(r)}>
                <td className="code">{r.segment_no}</td>
                <td>{(r.remarks || "").replace(/^Imported from transformer dump \| /, "").split(" | ")[0]}</td>
                <td>{r.type_name}</td>
                <td className="num">{r.capacity_kva ? fmt(r.capacity_kva) : "—"}</td>
                <td>{r.depot_name}</td>
                <td><Pill status={r.status} /></td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.length && !busy && (
          <Empty>
            No assets match these filters. Clear them, or register the asset if it is missing.
          </Empty>
        )}
        {busy && !rows.length && <Empty>Loading…</Empty>}
      </Sheet>

      <Pager meta={meta} onPage={setPage} />

      {open && <AssetDetail asset={open} onClose={() => setOpen(null)} />}
    </>
  );
}

/* --- asset detail ---------------------------------------------------- */

function AssetDetail({ asset, onClose }) {
  const [logs, setLogs] = useState([]);
  const [action, setAction] = useState("inspected");
  const [remarks, setRemarks] = useState("");
  const [saved, setSaved] = useState(null);

  useEffect(() => { API.logs(asset.asset_id).then(setLogs).catch(() => setLogs([])); }, [asset.asset_id]);

  const clean = (asset.remarks || "").replace(/^Imported from transformer dump \| /, "");
  const [name, serial] = clean.split(" | ");

  const record = async () => {
    try {
      await API.addLog({ asset_id: asset.asset_id, action_type: action, remarks });
      setLogs(await API.logs(asset.asset_id));
      setRemarks("");
      setSaved({ ok: true, msg: `Recorded as ${action}.` });
    } catch (e) {
      setSaved({ ok: false, msg: e.message });
    }
  };

  return (
    <Drawer onClose={onClose}>
      <h4>{name || asset.segment_no}</h4>
      <p className="code" style={{ color: "var(--ink-dim)", margin: 0 }}>{asset.segment_no}</p>

      <dl>
        <dt>Type</dt><dd>{asset.type_name}</dd>
        <dt>Rating</dt><dd>{asset.capacity_kva ? `${fmt(asset.capacity_kva)} kVA` : "Not recorded"}</dd>
        <dt>Service centre</dt><dd>{asset.depot_name}</dd>
        <dt>Area</dt><dd>{asset.area_name}</dd>
        <dt>Status</dt><dd><Pill status={asset.status} /></dd>
        {serial && (<><dt>Serial</dt><dd className="code">{serial.replace("serial ", "")}</dd></>)}
      </dl>

      <h3>Work history</h3>
      {logs.length ? (
        <Sheet>
          <table>
            <thead><tr><th>Action</th><th>By</th><th>When</th></tr></thead>
            <tbody>
              {logs.map(l => (
                <tr key={l.log_id}>
                  <td>{l.action_type}</td>
                  <td>{l.performed_by}</td>
                  <td>{new Date(l.performed_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Sheet>
      ) : (
        <p style={{ color: "var(--ink-dim)", fontSize: ".875rem" }}>
          Nothing recorded against this asset yet. The first entry below becomes
          the handover note for whoever inherits it.
        </p>
      )}

      <h3>Record work</h3>
      <div className="controls">
        <label className="field">
          Action
          <select value={action} onChange={e => setAction(e.target.value)}>
            <option value="inspected">Inspected</option>
            <option value="repaired">Repaired</option>
            <option value="replaced">Replaced</option>
            <option value="installed">Installed</option>
            <option value="decommissioned">Decommissioned</option>
          </select>
        </label>
        <label className="field" style={{ flex: 1 }}>
          Notes
          <input value={remarks} onChange={e => setRemarks(e.target.value)}
                 placeholder="Oil level topped up" />
        </label>
        <button onClick={record}>Save entry</button>
      </div>
      {saved && <div className={`note${saved.ok ? "" : " bad"}`}>{saved.msg}</div>}
    </Drawer>
  );
}

/* --- new asset ------------------------------------------------------- */

function NewAsset({ reference, go }) {
  const blank = {
    segment_no: "", asset_type_id: reference.asset_types[0]?.type_id || "",
    depot_id: reference.depots[0]?.depot_id || "", capacity_kva: "",
    status: "active", installed_date: "", remarks: "",
  };
  const [form, setForm] = useState(blank);
  const [result, setResult] = useState(null);

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }));

  const submit = async () => {
    try {
      await API.createAsset(form);
      setResult({ ok: true, msg: `${form.segment_no} added to the register.` });
      setForm(blank);
    } catch (e) {
      setResult({ ok: false, msg: e.message });
    }
  };

  return (
    <>
      <div className="page-head">
        <h2>Register an asset</h2>
        <p>
          The asset code has to be unique within its service centre. Use the SIN
          number from the as-built diagram where one exists.
        </p>
      </div>

      {result && <div className={`note${result.ok ? "" : " bad"}`}>{result.msg}</div>}

      <div className="sheet" style={{ padding: "1.25rem" }}>
        <div className="controls">
          <label className="field">
            Asset code
            <input value={form.segment_no} placeholder="UBB 212"
                   onChange={e => set("segment_no", e.target.value)} />
          </label>

          <label className="field">
            Service centre
            <select value={form.depot_id} onChange={e => set("depot_id", e.target.value)}>
              {reference.depots.map(d => (
                <option key={d.depot_id} value={d.depot_id}>{d.csc_name}</option>
              ))}
            </select>
          </label>

          <label className="field">
            Asset type
            <select value={form.asset_type_id} onChange={e => set("asset_type_id", e.target.value)}>
              {reference.asset_types.map(t => (
                <option key={t.type_id} value={t.type_id}>{t.type_name}</option>
              ))}
            </select>
          </label>

          <label className="field">
            Rating in kVA
            <input type="number" value={form.capacity_kva} placeholder="160"
                   onChange={e => set("capacity_kva", e.target.value)} />
          </label>

          <label className="field">
            Commissioned
            <input type="date" value={form.installed_date}
                   onChange={e => set("installed_date", e.target.value)} />
          </label>

          <label className="field" style={{ flex: 1, minWidth: "18rem" }}>
            Substation name and notes
            <input value={form.remarks} placeholder="Lower King Street"
                   onChange={e => set("remarks", e.target.value)} />
          </label>
        </div>

        <button onClick={submit} disabled={!form.segment_no}>Add to register</button>
      </div>
    </>
  );
}

/* --- shell ----------------------------------------------------------- */

function App() {
  const [view, setView] = useState({ page: "overview" });
  const [reference, setReference] = useState(null);
  const [mode, setMode] = useState(null);

  useEffect(() => {
    API.mode().then(setMode);
    API.reference().then(setReference).catch(() => setReference(null));
  }, []);

  const go = useCallback(next => {
    setView(next);
    window.scrollTo(0, 0);
  }, []);

  if (!reference) return <div className="boot">Loading the asset register…</div>;

  const grouped = reference.areas.map(a => ({
    ...a,
    depots: reference.depots.filter(d => d.area_name === a.area_name),
  }));

  return (
    <div className="shell">
      <nav className="rail">
        <div className="rail-head">
          <h1>Uva network assets</h1>
          <p>Ceylon Electricity Board</p>
        </div>

        <div className="rail-group">
          <a className={view.page === "overview" ? "on" : ""}
             tabIndex="0" onClick={() => go({ page: "overview" })}>Overview</a>
          <a className={view.page === "register" && !view.depot && !view.area ? "on" : ""}
             tabIndex="0" onClick={() => go({ page: "register" })}>Asset register</a>
          <a className={view.page === "new" ? "on" : ""}
             tabIndex="0" onClick={() => go({ page: "new" })}>Register an asset</a>
        </div>

        {grouped.map(a => (
          <div className="rail-group" key={a.area_id}>
            <span>{a.area_name} area</span>
            {a.depots.map(d => (
              <a key={d.depot_id} className={`depot${view.depot === d.csc_name ? " on" : ""}`}
                 tabIndex="0" onClick={() => go({ page: "register", depot: d.csc_name })}>
                {d.csc_name}
              </a>
            ))}
          </div>
        ))}
      </nav>

      <main className="main">
        {mode === "demo" && (
          <div className="note">
            Running on the offline snapshot: 1,715 transformer records read from
            <span className="code"> transformer_asset_management.sql</span>. Start Apache and
            MySQL in XAMPP and reload to switch to the live database, where saving works.
          </div>
        )}

        {view.page === "overview" && <Overview go={go} />}
        {view.page === "register" && <Register filter={view} reference={reference} go={go} />}
        {view.page === "new" && <NewAsset reference={reference} go={go} />}
      </main>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
