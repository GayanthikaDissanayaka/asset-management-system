import React, { useState, useMemo } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { LayoutDashboard, Boxes, Network, Activity, Plus, X, Search, ChevronRight } from 'lucide-react';

const AREAS = [
  { area_id: 1, area_name: 'Mahiyanganaya' },
  { area_id: 2, area_name: 'Badulla' },
  { area_id: 3, area_name: 'Diyathalawa' },
  { area_id: 4, area_name: 'Monaragala' },
  { area_id: 5, area_name: 'Wellawaya' },
];

const DEPOTS = [
  { depot_id: 1, area_id: 1, csc_name: 'Mahiyanganaya', abbr: 'MAH', page_no: '01' },
  { depot_id: 2, area_id: 1, csc_name: 'Rideemaliyadda', abbr: 'RID', page_no: '02' },
  { depot_id: 3, area_id: 1, csc_name: 'Kandaketiya', abbr: 'KAN', page_no: '03' },
  { depot_id: 4, area_id: 2, csc_name: 'Badulla', abbr: 'BAD', page_no: '04' },
  { depot_id: 5, area_id: 2, csc_name: 'Haliela', abbr: 'HAL', page_no: '05' },
  { depot_id: 6, area_id: 2, csc_name: 'Passara', abbr: 'PAS', page_no: '06' },
  { depot_id: 7, area_id: 3, csc_name: 'Diyathalawa', abbr: 'DIY', page_no: '07' },
  { depot_id: 8, area_id: 3, csc_name: 'Bandarawela', abbr: 'BAN', page_no: '08' },
  { depot_id: 9, area_id: 3, csc_name: 'Welimada', abbr: 'WEL', page_no: '09' },
  { depot_id: 10, area_id: 3, csc_name: 'Uva-paranagama', abbr: 'UVP', page_no: '10' },
  { depot_id: 11, area_id: 3, csc_name: 'Ella', abbr: 'ELL', page_no: '11' },
  { depot_id: 12, area_id: 4, csc_name: 'Monaragala', abbr: 'MON', page_no: '12' },
  { depot_id: 13, area_id: 4, csc_name: 'Dambagalla', abbr: 'DAM', page_no: '13' },
  { depot_id: 14, area_id: 4, csc_name: 'Bibila', abbr: 'BIB', page_no: '14' },
  { depot_id: 15, area_id: 5, csc_name: 'Wellawaya', abbr: 'WLW', page_no: '15' },
  { depot_id: 16, area_id: 5, csc_name: 'Buttala', abbr: 'BUT', page_no: '16' },
  { depot_id: 17, area_id: 5, csc_name: 'Thanamalwila', abbr: 'THA', page_no: '17' },
];

const CATEGORIES = [
  { category_id: 1, category_name: 'Transformer' },
  { category_id: 2, category_name: 'Substation' },
  { category_id: 3, category_name: 'Switchgear' },
  { category_id: 4, category_name: 'Cable' },
  { category_id: 5, category_name: 'Conductor' },
  { category_id: 6, category_name: 'Pole' },
  { category_id: 7, category_name: 'Power Line' },
];

const TYPES = [
  { type_id: 1, category_id: 1, type_name: 'Distribution Transformer', unit: 'nos', line: false },
  { type_id: 2, category_id: 2, type_name: 'Distribution Substation', unit: 'nos', line: false },
  { type_id: 3, category_id: 2, type_name: 'Grid Substation', unit: 'nos', line: false },
  { type_id: 4, category_id: 3, type_name: 'LBS (Load Break Switch)', unit: 'nos', line: false },
  { type_id: 5, category_id: 3, type_name: 'RMU (Ring Main Unit)', unit: 'nos', line: false },
  { type_id: 6, category_id: 3, type_name: 'Isolator', unit: 'nos', line: false },
  { type_id: 7, category_id: 4, type_name: 'Underground Cable', unit: 'km', line: true },
  { type_id: 8, category_id: 5, type_name: 'Copper Conductor', unit: 'km', line: true },
  { type_id: 9, category_id: 5, type_name: 'Weasel Conductor', unit: 'km', line: true },
  { type_id: 10, category_id: 5, type_name: 'Raccoon Conductor', unit: 'km', line: true },
  { type_id: 11, category_id: 5, type_name: 'Lynx Conductor', unit: 'km', line: true },
  { type_id: 12, category_id: 5, type_name: 'Fly Conductor', unit: 'km', line: true },
  { type_id: 13, category_id: 5, type_name: 'Zebra Conductor', unit: 'km', line: true },
  { type_id: 14, category_id: 5, type_name: 'ABC (Aerial Bundled Cable)', unit: 'km', line: true },
  { type_id: 15, category_id: 6, type_name: 'Concrete Pole', unit: 'nos', line: false },
  { type_id: 16, category_id: 6, type_name: 'Wooden Pole', unit: 'nos', line: false },
  { type_id: 17, category_id: 7, type_name: 'LV Line', unit: 'km', line: true },
  { type_id: 18, category_id: 7, type_name: 'MV Line', unit: 'km', line: true },
  { type_id: 19, category_id: 7, type_name: 'HV Line', unit: 'km', line: true },
];

const USERS = [
  { user_id: 1, name: 'S. Perera', role: 'admin' },
  { user_id: 2, name: 'N. Bandara', role: 'area_engineer' },
  { user_id: 3, name: 'K. Rathnayake', role: 'depot_engineer' },
  { user_id: 4, name: 'M. Wickramasinghe', role: 'field_technician' },
  { user_id: 5, name: 'T. Senanayake', role: 'field_technician' },
];

const STATUSES = ['active', 'active', 'active', 'active', 'faulty', 'under_repair', 'decommissioned'];
const ACTIONS = ['installed', 'inspected', 'repaired', 'replaced', 'decommissioned'];

// deterministic PRNG so the demo looks the same on every load
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(42);
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const randInt = (min, max) => Math.floor(rnd() * (max - min + 1)) + min;
const randDate = (startYear, endYear) => {
  const start = new Date(startYear, 0, 1).getTime();
  const end = new Date(endYear, 11, 31).getTime();
  return new Date(start + rnd() * (end - start)).toISOString().slice(0, 10);
};

function buildAssets() {
  const rows = [];
  let id = 1;
  DEPOTS.forEach((depot) => {
    const isCapital = ['Badulla', 'Bandarawela', 'Monaragala', 'Wellawaya', 'Mahiyanganaya'].includes(depot.csc_name);
    const plan = [
      { type_id: 1, qty: randInt(9, 34) }, // Distribution Transformer
      { type_id: 15, qty: randInt(90, 320) }, // Concrete Pole
      { type_id: 16, qty: randInt(8, 55) }, // Wooden Pole
      { type_id: pick([9, 10, 11, 13]), qty: randInt(6, 42) }, // a conductor type
      { type_id: 17, qty: randInt(12, 48) }, // LV Line
      { type_id: 18, qty: randInt(8, 30) }, // MV Line
    ];
    if (isCapital) {
      plan.push({ type_id: 3, qty: randInt(1, 2) }); // Grid Substation
      plan.push({ type_id: 19, qty: randInt(4, 14) }); // HV Line
    } else {
      plan.push({ type_id: 2, qty: randInt(1, 3) }); // Distribution Substation
    }
    if (rnd() > 0.4) plan.push({ type_id: 4, qty: randInt(2, 9) }); // LBS
    if (rnd() > 0.6) plan.push({ type_id: 5, qty: randInt(1, 5) }); // RMU
    if (rnd() > 0.5) plan.push({ type_id: 6, qty: randInt(2, 10) }); // Isolator

    plan.forEach((p, i) => {
      const type = TYPES.find((t) => t.type_id === p.type_id);
      const qty = type.unit === 'km' ? Math.round(p.qty * 10) / 10 : p.qty;
      rows.push({
        asset_id: id,
        segment_no: `${depot.abbr}-${String(i + 1).padStart(3, '0')}`,
        asset_type_id: type.type_id,
        depot_id: depot.depot_id,
        quantity: qty,
        capacity_kva: type.type_id === 1 ? pick([100, 160, 250, 315, 400, 500]) : null,
        material: type.type_id === 15 ? 'Concrete' : type.type_id === 16 ? 'Wooden' : type.category_id === 5 ? 'ACSR' : null,
        status: pick(STATUSES),
        installed_date: randDate(2004, 2023),
        remarks: null,
      });
      id += 1;
    });
  });
  return rows;
}

function buildLogs(assets) {
  const logs = [];
  let logId = 1;
  assets.forEach((asset) => {
    const entries = randInt(1, 3);
    for (let i = 0; i < entries; i++) {
      logs.push({
        log_id: logId++,
        asset_id: asset.asset_id,
        action_type: i === 0 ? 'installed' : pick(ACTIONS),
        performed_by: pick(USERS).name,
        performed_at: randDate(2018, 2026),
        remarks: null,
      });
    }
  });
  return logs.sort((a, b) => (a.performed_at < b.performed_at ? 1 : -1));
}

const SEED_ASSETS = buildAssets();
const SEED_LOGS = buildLogs(SEED_ASSETS);

const typeById = (id) => TYPES.find((t) => t.type_id === Number(id));
const categoryById = (id) => CATEGORIES.find((c) => c.category_id === Number(id));
const depotById = (id) => DEPOTS.find((d) => d.depot_id === Number(id));
const areaById = (id) => AREAS.find((a) => a.area_id === Number(id));
const areaForDepot = (depotId) => areaById(depotById(depotId)?.area_id);

const STATUS_STYLE = {
  active: 'bg-emerald-900 text-emerald-300 border-emerald-700',
  faulty: 'bg-rose-900 text-rose-300 border-rose-700',
  under_repair: 'bg-amber-900 text-amber-300 border-amber-700',
  decommissioned: 'bg-slate-700 text-slate-300 border-slate-600',
};

function StatusBadge({ status }) {
  return (
    <span className={`inline-block rounded border px-2 py-0.5 text-xs ${STATUS_STYLE[status] || STATUS_STYLE.decommissioned}`}>
      {status.replace('_', ' ')}
    </span>
  );
}

function Panel({ title, action, children, className = '' }) {
  return (
    <div className={`border border-slate-800 bg-slate-900 ${className}`}>
      {title && (
        <div className="flex items-center justify-between border-b border-slate-800 px-4 py-3">
          <h3 className="text-sm text-slate-300">{title}</h3>
          {action}
        </div>
      )}
      <div className="p-4">{children}</div>
    </div>
  );
}

function BarRow({ label, value, max, suffix = '', onClick, active }) {
  const pct = max ? Math.max(4, Math.round((value / max) * 100)) : 0;
  return (
    <button
      onClick={onClick}
      className={`block w-full text-left ${onClick ? 'cursor-pointer' : 'cursor-default'}`}
    >
      <div className="mb-1 flex items-center justify-between text-sm">
        <span className={active ? 'text-amber-300' : 'text-slate-300'}>{label}</span>
        <span className="tabular-nums text-slate-400">{value.toLocaleString()}{suffix}</span>
      </div>
      <div className="h-1.5 w-full bg-slate-800">
        <div
          className={`h-1.5 ${active ? 'bg-amber-400' : 'bg-slate-500'}`}
          style={{ width: `${pct}%` }}
        />
      </div>
    </button>
  );
}

// ---------------------------------------------------------------------------

function Dashboard({ assets }) {
  const [focusAreaId, setFocusAreaId] = useState(null);

  const depotTotals = useMemo(() => {
    return DEPOTS.map((d) => ({
      ...d,
      total: assets.filter((a) => a.depot_id === d.depot_id).reduce((s, a) => s + a.quantity, 0),
    }));
  }, [assets]);

  const areaTotals = useMemo(() => {
    return AREAS.map((a) => ({
      ...a,
      total: depotTotals.filter((d) => d.area_id === a.area_id).reduce((s, d) => s + d.total, 0),
    }));
  }, [depotTotals]);

  const provinceTotal = areaTotals.reduce((s, a) => s + a.total, 0);
  const maxArea = Math.max(...areaTotals.map((a) => a.total));

  const categoryTotals = useMemo(() => {
    return CATEGORIES.map((c) => {
      const typeIds = TYPES.filter((t) => t.category_id === c.category_id).map((t) => t.type_id);
      const total = assets.filter((a) => typeIds.includes(a.asset_type_id)).reduce((s, a) => s + a.quantity, 0);
      return { name: c.category_name, total: Math.round(total) };
    }).sort((a, b) => b.total - a.total);
  }, [assets]);

  const shownDepots = focusAreaId
    ? depotTotals.filter((d) => d.area_id === focusAreaId)
    : depotTotals;
  const maxDepot = Math.max(...shownDepots.map((d) => d.total), 1);

  const lineLength = useMemo(() => {
    const lineTypeIds = TYPES.filter((t) => t.line).map((t) => t.type_id);
    return Math.round(assets.filter((a) => lineTypeIds.includes(a.asset_type_id)).reduce((s, a) => s + a.quantity, 0));
  }, [assets]);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
        <Panel className="md:col-span-1">
          <div className="p-2">
            <p className="text-sm text-slate-400">Total network assets, Uva province</p>
            <p className="mt-2 text-5xl font-semibold tabular-nums text-amber-400">
              {provinceTotal.toLocaleString()}
            </p>
            <p className="mt-3 text-sm text-slate-500">5 areas &middot; 17 depots &middot; {assets.length} register rows</p>
            <div className="mt-4 border-t border-slate-800 pt-3 text-sm text-slate-400">
              Conductor &amp; line length, all types combined
              <p className="text-2xl text-slate-200">{lineLength.toLocaleString()} km</p>
            </div>
          </div>
        </Panel>

        <Panel title="Assets by category, province-wide" className="md:col-span-2">
          <div style={{ width: '100%', height: 220 }}>
            <ResponsiveContainer>
              <BarChart data={categoryTotals} layout="vertical" margin={{ left: 10, right: 20 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1e293b" horizontal={false} />
                <XAxis type="number" stroke="#64748b" fontSize={12} />
                <YAxis type="category" dataKey="name" stroke="#94a3b8" fontSize={12} width={110} />
                <Tooltip contentStyle={{ background: '#0f172a', border: '1px solid #334155', color: '#e2e8f0' }} />
                <Bar dataKey="total" fill="#e0a458" radius={[0, 2, 2, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Panel>
      </div>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
        <Panel title="By area (click to drill into depots)">
          <div className="space-y-3">
            {areaTotals.map((a) => (
              <BarRow
                key={a.area_id}
                label={a.area_name}
                value={a.total}
                max={maxArea}
                active={focusAreaId === a.area_id}
                onClick={() => setFocusAreaId(focusAreaId === a.area_id ? null : a.area_id)}
              />
            ))}
          </div>
        </Panel>

        <Panel title={focusAreaId ? `Depots in ${areaById(focusAreaId).area_name}` : 'By depot (all areas)'}>
          <div className="space-y-3">
            {shownDepots.map((d) => (
              <BarRow key={d.depot_id} label={d.csc_name} value={d.total} max={maxDepot} />
            ))}
          </div>
        </Panel>
      </div>
    </div>
  );
}

function AssetForm({ onCancel, onSave }) {
  const [form, setForm] = useState({
    segment_no: '', category_id: '', asset_type_id: '', depot_id: '',
    quantity: '', material: '', status: 'active', installed_date: '',
  });
  const [error, setError] = useState('');

  const typesForCategory = TYPES.filter((t) => t.category_id === Number(form.category_id));

  const submit = () => {
    if (!form.segment_no || !form.asset_type_id || !form.depot_id || !form.quantity) {
      setError('Segment no, type, depot and quantity are required.');
      return;
    }
    onSave({
      asset_id: Date.now(),
      segment_no: form.segment_no,
      asset_type_id: Number(form.asset_type_id),
      depot_id: Number(form.depot_id),
      quantity: Number(form.quantity),
      capacity_kva: null,
      material: form.material || null,
      status: form.status,
      installed_date: form.installed_date || new Date().toISOString().slice(0, 10),
      remarks: null,
    });
  };

  const field = 'w-full border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-200 focus:border-amber-500 focus:outline-none';

  return (
    <div className="fixed inset-0 z-20 flex items-center justify-center bg-slate-950/70 p-4">
      <div className="w-full max-w-md border border-slate-700 bg-slate-900">
        <div className="flex items-center justify-between border-b border-slate-800 px-4 py-3">
          <h3 className="text-sm text-slate-200">New asset register entry</h3>
          <button onClick={onCancel} className="text-slate-500 hover:text-slate-300"><X size={18} /></button>
        </div>
        <div className="space-y-3 p-4">
          {error && <p className="border border-rose-800 bg-rose-950 px-3 py-2 text-sm text-rose-300">{error}</p>}
          <div>
            <label className="mb-1 block text-xs text-slate-400">Segment / field code</label>
            <input className={field} placeholder="e.g. MAH-014" value={form.segment_no}
              onChange={(e) => setForm({ ...form, segment_no: e.target.value })} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1 block text-xs text-slate-400">Category</label>
              <select className={field} value={form.category_id}
                onChange={(e) => setForm({ ...form, category_id: e.target.value, asset_type_id: '' })}>
                <option value="">Select</option>
                {CATEGORIES.map((c) => <option key={c.category_id} value={c.category_id}>{c.category_name}</option>)}
              </select>
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-400">Asset type</label>
              <select className={field} value={form.asset_type_id} disabled={!form.category_id}
                onChange={(e) => setForm({ ...form, asset_type_id: e.target.value })}>
                <option value="">Select</option>
                {typesForCategory.map((t) => <option key={t.type_id} value={t.type_id}>{t.type_name}</option>)}
              </select>
            </div>
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-400">Depot</label>
            <select className={field} value={form.depot_id} onChange={(e) => setForm({ ...form, depot_id: e.target.value })}>
              <option value="">Select</option>
              {AREAS.map((a) => (
                <optgroup key={a.area_id} label={a.area_name}>
                  {DEPOTS.filter((d) => d.area_id === a.area_id).map((d) => (
                    <option key={d.depot_id} value={d.depot_id}>{d.csc_name}</option>
                  ))}
                </optgroup>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1 block text-xs text-slate-400">Quantity</label>
              <input type="number" className={field} value={form.quantity}
                onChange={(e) => setForm({ ...form, quantity: e.target.value })} />
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-400">Status</label>
              <select className={field} value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}>
                <option value="active">active</option>
                <option value="faulty">faulty</option>
                <option value="under_repair">under_repair</option>
                <option value="decommissioned">decommissioned</option>
              </select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1 block text-xs text-slate-400">Material (optional)</label>
              <input className={field} value={form.material} onChange={(e) => setForm({ ...form, material: e.target.value })} />
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-400">Installed date</label>
              <input type="date" className={field} value={form.installed_date}
                onChange={(e) => setForm({ ...form, installed_date: e.target.value })} />
            </div>
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t border-slate-800 px-4 py-3">
          <button onClick={onCancel} className="px-3 py-1.5 text-sm text-slate-400 hover:text-slate-200">Cancel</button>
          <button onClick={submit} className="bg-amber-500 px-3 py-1.5 text-sm font-medium text-slate-950 hover:bg-amber-400">
            Save entry
          </button>
        </div>
      </div>
    </div>
  );
}

function AssetDetail({ asset, logs, onClose }) {
  const type = typeById(asset.asset_type_id);
  const depot = depotById(asset.depot_id);
  const area = areaForDepot(asset.depot_id);
  const assetLogs = logs.filter((l) => l.asset_id === asset.asset_id);

  return (
    <Panel
      title={asset.segment_no}
      action={<button onClick={onClose} className="text-slate-500 hover:text-slate-300"><X size={16} /></button>}
    >
      <dl className="space-y-2 text-sm">
        <div className="flex justify-between"><dt className="text-slate-500">Type</dt><dd className="text-slate-200">{type.type_name}</dd></div>
        <div className="flex justify-between"><dt className="text-slate-500">Depot</dt><dd className="text-slate-200">{depot.csc_name}</dd></div>
        <div className="flex justify-between"><dt className="text-slate-500">Area</dt><dd className="text-slate-200">{area.area_name}</dd></div>
        <div className="flex justify-between"><dt className="text-slate-500">Quantity</dt><dd className="tabular-nums text-slate-200">{asset.quantity} {type.unit}</dd></div>
        {asset.capacity_kva && <div className="flex justify-between"><dt className="text-slate-500">Capacity</dt><dd className="text-slate-200">{asset.capacity_kva} kVA</dd></div>}
        {asset.material && <div className="flex justify-between"><dt className="text-slate-500">Material</dt><dd className="text-slate-200">{asset.material}</dd></div>}
        <div className="flex justify-between"><dt className="text-slate-500">Installed</dt><dd className="text-slate-200">{asset.installed_date}</dd></div>
        <div className="flex justify-between"><dt className="text-slate-500">Status</dt><dd><StatusBadge status={asset.status} /></dd></div>
      </dl>
      <div className="mt-4 border-t border-slate-800 pt-3">
        <p className="mb-2 text-xs text-slate-500">Maintenance history</p>
        {assetLogs.length === 0 && <p className="text-sm text-slate-500">No logged activity yet.</p>}
        <ul className="space-y-2">
          {assetLogs.map((l) => (
            <li key={l.log_id} className="text-sm">
              <span className="text-slate-300">{l.action_type}</span>
              <span className="text-slate-600"> &middot; </span>
              <span className="text-slate-500">{l.performed_by}, {l.performed_at}</span>
            </li>
          ))}
        </ul>
      </div>
    </Panel>
  );
}

function AssetsView({ assets, setAssets, logs }) {
  const [q, setQ] = useState('');
  const [areaFilter, setAreaFilter] = useState('');
  const [depotFilter, setDepotFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [selectedId, setSelectedId] = useState(null);
  const [showForm, setShowForm] = useState(false);

  const filtered = assets.filter((a) => {
    const type = typeById(a.asset_type_id);
    const depot = depotById(a.depot_id);
    const area = areaForDepot(a.depot_id);
    if (q && !a.segment_no.toLowerCase().includes(q.toLowerCase()) && !type.type_name.toLowerCase().includes(q.toLowerCase())) return false;
    if (areaFilter && area.area_id !== Number(areaFilter)) return false;
    if (depotFilter && depot.depot_id !== Number(depotFilter)) return false;
    if (statusFilter && a.status !== statusFilter) return false;
    return true;
  });

  const depotOptions = areaFilter ? DEPOTS.filter((d) => d.area_id === Number(areaFilter)) : DEPOTS;
  const selected = assets.find((a) => a.asset_id === selectedId);

  const selectClass = 'border border-slate-700 bg-slate-950 px-2 py-1.5 text-sm text-slate-200 focus:border-amber-500 focus:outline-none';

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center gap-2 border border-slate-700 bg-slate-950 px-2 py-1.5">
          <Search size={14} className="text-slate-500" />
          <input
            placeholder="Search segment no or type"
            className="bg-transparent text-sm text-slate-200 placeholder-slate-600 focus:outline-none"
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
        </div>
        <select className={selectClass} value={areaFilter} onChange={(e) => { setAreaFilter(e.target.value); setDepotFilter(''); }}>
          <option value="">All areas</option>
          {AREAS.map((a) => <option key={a.area_id} value={a.area_id}>{a.area_name}</option>)}
        </select>
        <select className={selectClass} value={depotFilter} onChange={(e) => setDepotFilter(e.target.value)}>
          <option value="">All depots</option>
          {depotOptions.map((d) => <option key={d.depot_id} value={d.depot_id}>{d.csc_name}</option>)}
        </select>
        <select className={selectClass} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="active">active</option>
          <option value="faulty">faulty</option>
          <option value="under_repair">under_repair</option>
          <option value="decommissioned">decommissioned</option>
        </select>
        <button
          onClick={() => setShowForm(true)}
          className="ml-auto flex items-center gap-1 bg-amber-500 px-3 py-1.5 text-sm font-medium text-slate-950 hover:bg-amber-400"
        >
          <Plus size={15} /> New asset
        </button>
      </div>

      <p className="text-xs text-slate-500">{filtered.length} of {assets.length} register rows</p>

      <div className={`grid grid-cols-1 gap-4 ${selected ? 'lg:grid-cols-3' : ''}`}>
        <div className={selected ? 'lg:col-span-2' : ''}>
          <div className="max-h-130 overflow-auto border border-slate-800">
            <table className="w-full text-left text-sm">
              <thead className="sticky top-0 bg-slate-900 text-xs text-slate-500">
                <tr>
                  <th className="px-3 py-2 font-normal">Segment no</th>
                  <th className="px-3 py-2 font-normal">Type</th>
                  <th className="px-3 py-2 font-normal">Depot</th>
                  <th className="px-3 py-2 font-normal text-right">Qty</th>
                  <th className="px-3 py-2 font-normal">Status</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((a) => {
                  const type = typeById(a.asset_type_id);
                  const depot = depotById(a.depot_id);
                  return (
                    <tr
                      key={a.asset_id}
                      onClick={() => setSelectedId(a.asset_id)}
                      className={`cursor-pointer border-t border-slate-800 hover:bg-slate-800/60 ${selectedId === a.asset_id ? 'bg-slate-800/60' : ''}`}
                    >
                      <td className="px-3 py-2 font-mono text-xs text-slate-300">{a.segment_no}</td>
                      <td className="px-3 py-2 text-slate-300">{type.type_name}</td>
                      <td className="px-3 py-2 text-slate-400">{depot.csc_name}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-slate-300">{a.quantity} {type.unit}</td>
                      <td className="px-3 py-2"><StatusBadge status={a.status} /></td>
                    </tr>
                  );
                })}
                {filtered.length === 0 && (
                  <tr><td colSpan={5} className="px-3 py-6 text-center text-slate-500">No assets match these filters.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
        {selected && (
          <AssetDetail asset={selected} logs={logs} onClose={() => setSelectedId(null)} />
        )}
      </div>

      {showForm && (
        <AssetForm
          onCancel={() => setShowForm(false)}
          onSave={(a) => { setAssets((prev) => [a, ...prev]); setShowForm(false); }}
        />
      )}
    </div>
  );
}

function HierarchyView({ assets, onOpenDepot }) {
  const [openArea, setOpenArea] = useState(AREAS[0].area_id);
  return (
    <div className="space-y-3">
      {AREAS.map((area) => {
        const depots = DEPOTS.filter((d) => d.area_id === area.area_id);
        const isOpen = openArea === area.area_id;
        return (
          <div key={area.area_id} className="border border-slate-800">
            <button
              onClick={() => setOpenArea(isOpen ? null : area.area_id)}
              className="flex w-full items-center justify-between bg-slate-900 px-4 py-3 text-left"
            >
              <span className="text-sm text-slate-200">{area.area_name}</span>
              <span className="flex items-center gap-2 text-xs text-slate-500">
                {depots.length} depots
                <ChevronRight size={14} className={`transition-transform ${isOpen ? 'rotate-90' : ''}`} />
              </span>
            </button>
            {isOpen && (
              <div className="divide-y divide-slate-800 border-t border-slate-800">
                {depots.map((d) => {
                  const total = assets.filter((a) => a.depot_id === d.depot_id).reduce((s, a) => s + a.quantity, 0);
                  return (
                    <button
                      key={d.depot_id}
                      onClick={() => onOpenDepot(d.depot_id, area.area_id)}
                      className="flex w-full items-center justify-between px-4 py-2.5 text-left hover:bg-slate-800/60"
                    >
                      <span className="text-sm text-slate-300">{d.csc_name}</span>
                      <span className="flex items-center gap-4 text-xs text-slate-500">
                        <span className="font-mono">page {d.page_no}</span>
                        <span className="tabular-nums text-slate-400">{Math.round(total)} assets</span>
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function MaintenanceView({ logs, assets }) {
  const rows = logs.slice(0, 60).map((l) => {
    const asset = assets.find((a) => a.asset_id === l.asset_id);
    if (!asset) return null;
    const depot = depotById(asset.depot_id);
    const type = typeById(asset.asset_type_id);
    return { ...l, segment_no: asset.segment_no, depot_name: depot.csc_name, type_name: type.type_name };
  }).filter(Boolean);

  return (
    <Panel title="Most recent activity, all depots (mirrors vw_asset_last_activity)">
      <div className="max-h-140 overflow-auto">
        <table className="w-full text-left text-sm">
          <thead className="sticky top-0 bg-slate-900 text-xs text-slate-500">
            <tr>
              <th className="px-3 py-2 font-normal">Segment no</th>
              <th className="px-3 py-2 font-normal">Depot</th>
              <th className="px-3 py-2 font-normal">Type</th>
              <th className="px-3 py-2 font-normal">Action</th>
              <th className="px-3 py-2 font-normal">Performed by</th>
              <th className="px-3 py-2 font-normal">Date</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.log_id} className="border-t border-slate-800">
                <td className="px-3 py-2 font-mono text-xs text-slate-300">{r.segment_no}</td>
                <td className="px-3 py-2 text-slate-400">{r.depot_name}</td>
                <td className="px-3 py-2 text-slate-400">{r.type_name}</td>
                <td className="px-3 py-2 text-slate-300">{r.action_type}</td>
                <td className="px-3 py-2 text-slate-400">{r.performed_by}</td>
                <td className="px-3 py-2 text-slate-500">{r.performed_at}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}

export default function App() {
  const [view, setView] = useState('dashboard');
  const [assets, setAssets] = useState(SEED_ASSETS);
  const [assetFilterHint, setAssetFilterHint] = useState(null);

  const nav = [
    { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { id: 'assets', label: 'Asset register', icon: Boxes },
    { id: 'hierarchy', label: 'Areas & depots', icon: Network },
    { id: 'maintenance', label: 'Maintenance log', icon: Activity },
  ];

  const titleFor = { dashboard: 'Province overview', assets: 'Asset register', hierarchy: 'Areas & depots', maintenance: 'Maintenance log' };

  return (
    <div className="flex h-full min-h-screen w-full bg-slate-950 text-slate-200" style={{ fontFamily: 'ui-sans-serif, system-ui, sans-serif' }}>
      <aside className="hidden w-56 shrink-0 border-r border-slate-800 bg-slate-900 sm:block">
        <div className="border-b border-slate-800 px-4 py-4">
          <p className="text-sm font-semibold text-slate-100">Uva NAMS</p>
          <p className="text-xs text-slate-500">Network Asset Management</p>
        </div>
        <nav className="p-2">
          {nav.map((n) => {
            const Icon = n.icon;
            const active = view === n.id;
            return (
              <button
                key={n.id}
                onClick={() => setView(n.id)}
                className={`mb-1 flex w-full items-center gap-2 px-3 py-2 text-left text-sm ${active ? 'bg-slate-800 text-amber-300' : 'text-slate-400 hover:bg-slate-800/60 hover:text-slate-200'}`}
              >
                <Icon size={16} />
                {n.label}
              </button>
            );
          })}
        </nav>
        <div className="absolute bottom-0 w-56 border-t border-slate-800 p-3 text-xs text-slate-600">
          5 areas &middot; 17 depots &middot; 19 asset types
        </div>
      </aside>

      <main className="min-w-0 flex-1">
        <header className="flex items-center justify-between border-b border-slate-800 px-6 py-4">
          <h1 className="text-base text-slate-100">{titleFor[view]}</h1>
          <span className="border border-amber-800 bg-amber-950 px-2 py-1 text-xs text-amber-300">
            Demo data, not connected to Laravel API
          </span>
        </header>
        <div className="p-6">
          {view === 'dashboard' && <Dashboard assets={assets} />}
          {view === 'assets' && <AssetsView assets={assets} setAssets={setAssets} logs={SEED_LOGS} />}
          {view === 'hierarchy' && (
            <HierarchyView
              assets={assets}
              onOpenDepot={() => setView('assets')}
            />
          )}
          {view === 'maintenance' && <MaintenanceView logs={SEED_LOGS} assets={assets} />}
        </div>
      </main>
    </div>
  );
}
