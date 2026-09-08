/* ---------------------------------------------------------------------
   Data layer.

   Every screen talks to this file and nothing else. It tries the PHP API
   first; if MySQL or Apache is not running it falls back to the offline
   snapshot in demo-data.js so you can still click through the UI.

   When you port this to a real React build, this is the only file that
   changes — replace the fetch calls with axios if you prefer.
   --------------------------------------------------------------------- */

// Point this at wherever you dropped the api/ folder in htdocs.
const API_BASE = "../api/index.php";

/* --- reference data -------------------------------------------------
   The 5 areas and 17 CSCs seeded by 01_schema.sql. Kept here so demo
   mode shows the same hierarchy the database does.
   ------------------------------------------------------------------- */

const AREA_OF_DEPOT = {
  "Mahiyanganaya": "Mahiyanganaya", "Rideemaliyadda": "Mahiyanganaya", "Kandaketiya": "Mahiyanganaya",
  "Badulla": "Badulla", "Haliela": "Badulla", "Passara": "Badulla",
  "Diyathalawa": "Diyathalawa", "Bandarawela": "Diyathalawa", "Welimada": "Diyathalawa",
  "Uva-paranagama": "Diyathalawa", "Ella": "Diyathalawa",
  "Monaragala": "Monaragala", "Dambagalla": "Monaragala", "Bibila": "Monaragala",
  "Wellawaya": "Wellawaya", "Buttala": "Wellawaya", "Thanamalwila": "Wellawaya",
};

const AREA_ORDER = ["Mahiyanganaya", "Badulla", "Diyathalawa", "Monaragala", "Wellawaya"];

// The dump spells CSC names differently from the schema. Same translation
// table as database/03_import_transformers.sql — keep the two in step.
const DUMP_TO_DEPOT = {
  "Hali Ela": "Haliela",
  "Mahiyanagana": "Mahiyanganaya",
  "Kandeketiya": "Kandaketiya",
  "Uvaparanagama": "Uva-paranagama",
  "Tanamalvilla": "Thanamalwila",
  "Diyatalawa": "Diyathalawa",
};

/* --- transport ------------------------------------------------------ */

let liveApi = null; // null = not probed yet, true/false once known

async function call(route, options = {}) {
  const url = `${API_BASE}?r=${route}`;
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const payload = await res.json();
  if (!res.ok) throw new Error(payload.error || `Request failed (${res.status})`);
  return payload;
}

async function isLive() {
  if (liveApi !== null) return liveApi;
  try {
    const res = await fetch(`${API_BASE}?r=ping`, { signal: AbortSignal.timeout(2500) });
    const body = await res.json();
    liveApi = res.ok && body.ok === true;
  } catch {
    liveApi = false;
  }
  return liveApi;
}

/* --- demo mode -----------------------------------------------------
   Recomputes the same numbers the SQL views produce, in the browser.
   ------------------------------------------------------------------- */

const demoRows = (window.DEMO_TRANSFORMERS || []).map((r, i) => {
  const depot = DUMP_TO_DEPOT[r.csc] || r.csc;
  return {
    asset_id: r.id,
    segment_no: r.sin || `TX${String(r.id).padStart(5, "0")}`,
    quantity: 1,
    capacity_kva: r.kva,
    status: "active",
    type_name: /MHP/.test(r.type) ? "Mini Hydro Plant"
             : /^Bulk/.test(r.type) ? "Bulk Supply Point"
             : "Distribution Transformer",
    category_name: "Transformer",
    unit_of_measure: "nos",
    depot_name: depot,
    depot_id: Object.keys(AREA_OF_DEPOT).indexOf(depot) + 1,
    area_name: AREA_OF_DEPOT[depot] || "—",
    remarks: r.name + (r.tno ? ` | serial ${r.tno}` : ""),
  };
});

function groupSum(rows, keyFn) {
  const out = new Map();
  for (const r of rows) {
    const k = keyFn(r);
    const cur = out.get(k) || { units: 0, kva: 0 };
    cur.units += 1;
    cur.kva += Number(r.capacity_kva) || 0;
    out.set(k, cur);
  }
  return out;
}

function demoDashboard() {
  const byDepot = groupSum(demoRows, r => r.depot_name);
  const byArea = groupSum(demoRows, r => r.area_name);
  const byType = groupSum(demoRows, r => r.type_name);
  const byRating = groupSum(demoRows.filter(r => r.capacity_kva), r => r.capacity_kva);

  // Every seeded depot appears, including the four with no transformers yet.
  const depots = Object.keys(AREA_OF_DEPOT).map((name, i) => ({
    depot_id: i + 1,
    depot_name: name,
    area_name: AREA_OF_DEPOT[name],
    depot_total: byDepot.get(name)?.units || 0,
    total_kva: byDepot.get(name)?.kva || 0,
    units: byDepot.get(name)?.units || 0,
  }));

  return {
    province: { province_total: demoRows.length },
    areas: AREA_ORDER.map((name, i) => ({
      area_id: i + 1,
      area_name: name,
      area_total: byArea.get(name)?.units || 0,
    })).sort((a, b) => b.area_total - a.area_total),
    depots: [...depots].sort((a, b) => b.depot_total - a.depot_total),
    capacity_by_depot: [...depots].sort((a, b) => b.total_kva - a.total_kva),
    by_type: [...byType].map(([type_name, v]) => ({
      type_name, category_name: "Transformer", units: v.units, total_kva: v.kva,
    })).sort((a, b) => b.units - a.units),
    by_rating: [...byRating].map(([capacity_kva, v]) => ({
      capacity_kva: Number(capacity_kva), units: v.units,
    })).sort((a, b) => b.units - a.units).slice(0, 12),
  };
}

function demoAssets(params) {
  let rows = demoRows;

  if (params.search) {
    const q = params.search.toLowerCase();
    rows = rows.filter(r =>
      r.segment_no.toLowerCase().includes(q) || r.remarks.toLowerCase().includes(q));
  }
  if (params.depot_name) rows = rows.filter(r => r.depot_name === params.depot_name);
  if (params.area_name)  rows = rows.filter(r => r.area_name === params.area_name);
  if (params.type_name)  rows = rows.filter(r => r.type_name === params.type_name);

  rows = [...rows].sort((a, b) => a.segment_no.localeCompare(b.segment_no));

  const perPage = params.per_page || 50;
  const page = params.page || 1;

  return {
    data: rows.slice((page - 1) * perPage, page * perPage),
    meta: {
      total: rows.length,
      page,
      per_page: perPage,
      last_page: Math.max(Math.ceil(rows.length / perPage), 1),
    },
  };
}

/* --- public interface ----------------------------------------------- */

window.API = {
  /** true once we know whether the PHP API answered. */
  live: () => liveApi,

  async mode() {
    return (await isLive()) ? "live" : "demo";
  },

  async dashboard() {
    if (await isLive()) {
      const d = await call("dashboard");
      // Merge the two roll-ups so the diagram has counts and kVA together.
      const kva = new Map(d.capacity_by_depot.map(r => [String(r.depot_id), r]));
      d.depots = d.depots.map(r => ({
        ...r,
        total_kva: Number(kva.get(String(r.depot_id))?.total_kva) || 0,
      }));
      return d;
    }
    return demoDashboard();
  },

  async assets(params = {}) {
    if (await isLive()) {
      const qs = Object.entries(params)
        .filter(([, v]) => v !== "" && v != null)
        .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
        .join("&");
      return call(`assets&${qs}`);
    }
    return demoAssets(params);
  },

  async reference() {
    if (await isLive()) return call("reference");
    return {
      areas: AREA_ORDER.map((area_name, i) => ({ area_id: i + 1, area_no: i + 1, area_name })),
      depots: Object.keys(AREA_OF_DEPOT).map((csc_name, i) => ({
        depot_id: i + 1, csc_name, area_name: AREA_OF_DEPOT[csc_name],
      })),
      asset_types: [
        { type_id: 1, type_name: "Distribution Transformer", category_name: "Transformer", unit_of_measure: "nos" },
        { type_id: 2, type_name: "Bulk Supply Point", category_name: "Bulk Supply", unit_of_measure: "nos" },
        { type_id: 3, type_name: "Mini Hydro Plant", category_name: "Mini Hydro", unit_of_measure: "nos" },
      ],
    };
  },

  async createAsset(payload) {
    if (!(await isLive())) {
      throw new Error("Saving needs the PHP API. Start Apache and MySQL in XAMPP, then reload.");
    }
    return call("assets", { method: "POST", body: JSON.stringify(payload) });
  },

  async logs(assetId) {
    if (!(await isLive())) return [];
    return call(`logs&asset_id=${assetId}`);
  },

  async addLog(payload) {
    if (!(await isLive())) {
      throw new Error("Logging work needs the PHP API. Start Apache and MySQL in XAMPP, then reload.");
    }
    return call("logs", { method: "POST", body: JSON.stringify(payload) });
  },
};

window.AREA_ORDER = AREA_ORDER;
window.AREA_OF_DEPOT = AREA_OF_DEPOT;
