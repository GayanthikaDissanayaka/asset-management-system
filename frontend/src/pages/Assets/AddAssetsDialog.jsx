import React, { useEffect, useMemo, useState } from 'react';

import axiosClient from '../../api/axiosClient';
import { describeWriteError } from '../Dashboard/Components/session';
import { num, formatNumber } from '../Dashboard/Components/data';

const MAX_ROWS = 12;

const blankRow = () => ({
  uid: Math.random().toString(36).slice(2),
  categoryId: '',
  assetTypeId: '',
  quantity: '',
  condition: '',
  // Transformer lines only.
  serialNo: '',
  sinNo: '',
  substation: '',
  capacity: '',
  manufacturer: '',
});

/* A transformer is recorded one unit at a time, with its own serial
   number, into the transformer register -- not as a count. */
const isTransformer = (type) => type?.category_name === 'Transformer';

const decimalsFor = (unit) => (unit === 'km' ? 3 : 0);

const AddAssetsDialog = ({ open, options, optionsError, onClose, onSaved }) => {
  const [areaId, setAreaId] = useState('');
  const [cscId, setCscId] = useState('');
  const [rows, setRows] = useState([blankRow()]);
  const [remarks, setRemarks] = useState('');
  const [installDate, setInstallDate] = useState('');

  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState('');
  const [result, setResult] = useState(null);

  // A fresh dialog every time it opens, so a previous entry never bleeds
  // into the next one.
  useEffect(() => {
    if (!open) return;
    setAreaId('');
    setCscId('');
    setRows([blankRow()]);
    setRemarks('');
    setInstallDate('');
    setErrors({});
    setSaveError('');
    setResult(null);
  }, [open]);

  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  const { areas, cscs, categories, types, conditions } = useMemo(
    () => ({
      areas: options?.areas || [],
      cscs: options?.cscs || [],
      categories: options?.categories || [],
      types: options?.types || [],
      conditions: options?.conditions || [],
    }),
    [options]
  );

  const ready = Boolean(options) && areas.length > 0;

  /* Only CSCs in the chosen area. An asset belongs to exactly one place,
     so unlike a segment there is no reason to offer the others. */
  const cscChoices = useMemo(
    () => cscs.filter((c) => !areaId || String(c.area_id) === String(areaId)),
    [cscs, areaId]
  );

  const typeById = useMemo(() => {
    const map = new Map();
    for (const t of types) map.set(String(t.asset_type_id), t);
    return map;
  }, [types]);

  const chosenCsc = cscs.find((c) => String(c.csc_id) === String(cscId));

  const setRow = (uid, patch) =>
    setRows((list) =>
      list.map((r) => (r.uid === uid ? { ...r, ...patch } : r))
    );

  /* What this entry adds, per unit, updated as it is typed — so the
     total is visible before the save rather than only after it. */
  const pending = useMemo(() => {
    const byUnit = new Map();

    for (const row of rows) {
      const type = typeById.get(String(row.assetTypeId));
      const qty = isTransformer(type) ? 1 : num(row.quantity);
      if (!type || qty <= 0) continue;

      byUnit.set(
        type.unit_of_measure,
        (byUnit.get(type.unit_of_measure) || 0) + qty
      );
    }

    return Array.from(byUnit, ([unit, quantity]) => ({ unit, quantity }));
  }, [rows, typeById]);

  const validate = () => {
    const found = {};

    if (!cscId) found.cscId = 'Choose the CSC this belongs to.';

    const filled = rows.filter((r) => r.assetTypeId || r.quantity);
    if (filled.length === 0) found.rows = 'Add at least one asset.';

    for (const row of filled) {
      if (!row.assetTypeId) {
        found[`type-${row.uid}`] = 'Choose an asset type.';
        continue;
      }

      const rowType = typeById.get(String(row.assetTypeId));
      if (isTransformer(rowType)) {
        if (!row.serialNo.trim()) found[`serial-${row.uid}`] = 'Enter the serial number.';
        if (!row.substation.trim()) found[`sub-${row.uid}`] = 'Enter the substation it serves.';
        continue;
      }

      const qty = num(row.quantity);
      if (qty <= 0) {
        found[`qty-${row.uid}`] = 'Enter how many.';
        continue;
      }

      /* Whole numbers where the type is counted rather than measured.
         The database enforces this too; catching it here saves a round
         trip and points at the row that is wrong. */
      const type = typeById.get(String(row.assetTypeId));
      if (type && !type.allow_decimal && qty % 1 !== 0) {
        found[`qty-${row.uid}`] = `${type.type_name} is counted in whole ${type.unit_of_measure}.`;
      }
    }

    const serials = rows
      .filter((r) => isTransformer(typeById.get(String(r.assetTypeId))))
      .map((r) => r.serialNo.trim().toUpperCase().replace(/[^A-Z0-9]/g, ''))
      .filter(Boolean);
    if (new Set(serials).size !== serials.length) {
      found.rows = 'The same serial number is entered twice.';
    }

    setErrors(found);
    return Object.keys(found).length === 0;
  };

  const save = async () => {
    if (!validate()) return;

    setSaving(true);
    setSaveError('');

    const txRows = rows.filter((r) => isTransformer(typeById.get(String(r.assetTypeId))));
    const countRows = rows.filter(
      (r) => r.assetTypeId && !isTransformer(typeById.get(String(r.assetTypeId))) && num(r.quantity) > 0
    );

    const common = {
      csc_id: Number(cscId),
      install_date: installDate || null,
      remarks: remarks.trim() || null,
    };

    const added = [];
    const messages = [];
    let last = null;
    let txSaved = false;

    try {
      /* Transformers first: they are the lines most likely to be refused
         (a serial number already recorded), and refusing them before the
         counted lines are written keeps a failed save from half-saving. */
      if (txRows.length > 0) {
        const { data } = await axiosClient.post('/network/transformers', {
          ...common,
          transformers: txRows.map((r) => ({
            asset_type_id: Number(r.assetTypeId),
            serial_no: r.serialNo.trim(),
            old_sin_no: r.sinNo.trim() || null,
            substation_name: r.substation.trim(),
            capacity_kva: r.capacity === '' ? null : num(r.capacity),
            manufacturer: r.manufacturer.trim() || null,
            condition_status: r.condition || null,
          })),
        });
        last = data;
        added.push(...data.added);
        messages.push(data.message);
        txSaved = true;
        // Saved: take them off the form so a retry cannot enter them twice.
        setRows((list) => list.filter((r) => !isTransformer(typeById.get(String(r.assetTypeId)))));
      }

      if (countRows.length > 0) {
        const { data } = await axiosClient.post('/network/assets/records', {
          ...common,
          items: countRows.map((r) => ({
            asset_type_id: Number(r.assetTypeId),
            quantity: num(r.quantity),
            condition_status: r.condition || null,
          })),
        });
        last = data;
        added.push(...data.added);
        messages.push(data.message);
      }

      const combined = { ...last, added, message: messages.join(' ') };
      setResult(combined);
      // The page behind reloads now, so its totals already include this
      // entry by the time the dialog is closed.
      onSaved?.(combined);
    } catch (err) {
      const why = describeWriteError(err);
      setSaveError(txSaved ? `The transformers were saved. The other lines were not: ${why}` : why);
      if (txSaved && last) onSaved?.(last);
    } finally {
      setSaving(false);
    }
  };

  /* Back to the form, keeping the place. Entries arrive in batches for
     one CSC, and re-picking the area and CSC each time is the friction
     that makes people save one big wrong row instead. */
  const addMoreHere = () => {
    setRows([blankRow()]);
    setRemarks('');
    setErrors({});
    setSaveError('');
    setResult(null);
  };

  if (!open) return null;

  return (
    <div className="dialog-backdrop" role="presentation" onClick={onClose}>
      <div
        className="dialog ax-add-dialog"
        role="dialog"
        aria-modal="true"
        aria-label="Add assets"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="dialog-head">
          <div>
            <h2>{result ? 'Saved' : 'Add assets to a place'}</h2>
            <p>
              {result
                ? `${result.place.csc_name} CSC · ${result.place.area_name} area`
                : chosenCsc
                ? `Recording against ${chosenCsc.csc_name} CSC.`
                : 'Choose where these assets are, then what they are.'}
            </p>
          </div>

          <button
            type="button"
            className="dialog-close"
            onClick={onClose}
            aria-label="Close"
          >
            &times;
          </button>
        </header>

        <div className="dialog-body">
          {!options && !optionsError && (
            <div className="dialog-notice">Loading areas, CSCs and asset types...</div>
          )}

          {optionsError && <div className="dialog-error">{optionsError}</div>}

          {/* ---------------- after saving: the summary ---------------- */}
          {result ? (
            <>
              <div className="ax-saved-banner">{result.message}</div>

              <section className="ax-detail-block">
                <h3>What this entry added</h3>
                <ul className="ax-holdings">
                  {result.added.map((a) => (
                    <li key={a.asset_id ?? `tx-${a.transformer_id}`}>
                      <span className="ax-holding-name">
                        {a.type_name}
                        <em className="ax-holding-cat">
                          {a.serial_no
                            ? `Serial ${a.serial_no} · ${a.substation_name}`
                            : a.category_name}
                        </em>
                      </span>
                      <span className="ax-holding-value">
                        {formatNumber(a.quantity, decimalsFor(a.unit_of_measure))}{' '}
                        <em>{a.unit_of_measure}</em>
                      </span>
                      <span className="ax-holding-recs">saved</span>
                    </li>
                  ))}
                </ul>
              </section>

              <section className="ax-detail-block">
                <h3>What {result.place.csc_name} CSC holds now</h3>
                <p className="ax-block-hint">
                  Including this entry. Check it before adding anything else —
                  this is the figure that catches a batch entered twice.
                </p>

                <div className="ax-saved-totals">
                  {result.place_totals.map((t) => (
                    <div key={t.unit_of_measure} className="ax-saved-total">
                      <span className="summary-value">
                        {formatNumber(t.quantity, decimalsFor(t.unit_of_measure))}{' '}
                        <em>{t.unit_of_measure}</em>
                      </span>
                      <span className="summary-hint">
                        across {formatNumber(t.records)} records
                      </span>
                    </div>
                  ))}
                </div>

                <ul className="ax-holdings">
                  {result.place_categories.map((c) => (
                    <li key={`${c.category_id}-${c.unit_of_measure}`}>
                      <span className="ax-holding-name">{c.category_name}</span>
                      <span className="ax-holding-value">
                        {formatNumber(c.quantity, decimalsFor(c.unit_of_measure))}{' '}
                        <em>{c.unit_of_measure}</em>
                      </span>
                      <span className="ax-holding-recs">
                        {formatNumber(c.records)} records
                      </span>
                    </li>
                  ))}
                </ul>
              </section>

              <p className="ax-block-hint">
                These are in the register now. They appear in the totals on this
                page, in the CSC breakdown, and in the exported report.
              </p>
            </>
          ) : (
            /* ------------------ before saving: the form ------------------ */
            <>
              <div className="field-grid">
                <label className="field">
                  <span>Area *</span>
                  <select
                    value={areaId}
                    onChange={(e) => {
                      setAreaId(e.target.value);
                      setCscId('');
                    }}
                    disabled={!ready}
                  >
                    <option value="">Select an area</option>
                    {areas.map((a) => (
                      <option key={a.area_id} value={a.area_id}>
                        {a.area_name} ({a.area_code})
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>CSC *</span>
                  <select
                    value={cscId}
                    onChange={(e) => setCscId(e.target.value)}
                    disabled={!ready}
                    className={errors.cscId ? 'invalid' : ''}
                  >
                    <option value="">
                      {areaId ? 'Select a CSC' : 'All CSCs'}
                    </option>
                    {cscChoices.map((c) => (
                      <option key={c.csc_id} value={c.csc_id}>
                        {c.csc_name} ({c.csc_code})
                      </option>
                    ))}
                  </select>
                  {errors.cscId && <em className="field-error">{errors.cscId}</em>}
                </label>

                <label className="field">
                  <span>Installed on</span>
                  <input
                    type="date"
                    value={installDate}
                    onChange={(e) => setInstallDate(e.target.value)}
                  />
                </label>

                <label className="field">
                  <span>Remarks</span>
                  <input
                    type="text"
                    value={remarks}
                    maxLength={500}
                    placeholder="Optional note kept with the entry"
                    onChange={(e) => setRemarks(e.target.value)}
                  />
                </label>
              </div>

              <section className="ax-detail-block">
                <h3>What is being added</h3>
                {errors.rows && <div className="dialog-error">{errors.rows}</div>}

                <ul className="ax-add-rows">
                  {rows.map((row, index) => {
                    const type = typeById.get(String(row.assetTypeId));
                    const typeChoices = row.categoryId
                      ? types.filter(
                          (t) => String(t.category_id) === String(row.categoryId)
                        )
                      : types;

                    return (
                      <li key={row.uid} className="ax-add-row">
                        <label className="field">
                          <span>{index === 0 ? 'Main asset' : ''}</span>
                          <select
                            value={row.categoryId}
                            onChange={(e) =>
                              setRow(row.uid, {
                                categoryId: e.target.value,
                                assetTypeId: '',
                              })
                            }
                            disabled={!ready}
                          >
                            <option value="">All categories</option>
                            {categories.map((c) => (
                              <option key={c.category_id} value={c.category_id}>
                                {c.category_name}
                              </option>
                            ))}
                          </select>
                        </label>

                        <label className="field">
                          <span>{index === 0 ? 'Asset type *' : ''}</span>
                          <select
                            value={row.assetTypeId}
                            onChange={(e) =>
                              setRow(row.uid, { assetTypeId: e.target.value })
                            }
                            disabled={!ready}
                            className={errors[`type-${row.uid}`] ? 'invalid' : ''}
                          >
                            <option value="">Select a type</option>
                            {typeChoices.map((t) => (
                              <option key={t.asset_type_id} value={t.asset_type_id}>
                                {t.type_name}
                              </option>
                            ))}
                          </select>
                          {errors[`type-${row.uid}`] && (
                            <em className="field-error">
                              {errors[`type-${row.uid}`]}
                            </em>
                          )}
                        </label>

                        {isTransformer(type) ? (
                          <div className="field ax-qty">
                            <span>{index === 0 ? 'Quantity *' : ''}</span>
                            <div
                              className="ax-qty-input"
                              title="Each transformer is one unit with its own serial number"
                            >
                              <input type="text" value="1" disabled aria-label="One transformer" />
                              <em>nos</em>
                            </div>
                          </div>
                        ) : (
                        <label className="field ax-qty">
                          <span>
                            {index === 0 ? 'Quantity *' : ''}
                          </span>
                          <div className="ax-qty-input">
                            <input
                              type="number"
                              min="0"
                              step={type?.allow_decimal ? '0.001' : '1'}
                              value={row.quantity}
                              placeholder="0"
                              onChange={(e) =>
                                setRow(row.uid, { quantity: e.target.value })
                              }
                              className={errors[`qty-${row.uid}`] ? 'invalid' : ''}
                            />
                            {/* The unit follows the type and is never
                                typed; the database overwrites it anyway. */}
                            <em>{type?.unit_of_measure || '—'}</em>
                          </div>
                          {errors[`qty-${row.uid}`] && (
                            <em className="field-error">
                              {errors[`qty-${row.uid}`]}
                            </em>
                          )}
                        </label>
                        )}

                        <label className="field">
                          <span>{index === 0 ? 'Condition' : ''}</span>
                          <select
                            value={row.condition}
                            onChange={(e) =>
                              setRow(row.uid, { condition: e.target.value })
                            }
                          >
                            <option value="">Not recorded</option>
                            {conditions
                              .filter((c) => c !== 'UNKNOWN')
                              .map((c) => (
                                <option key={c} value={c}>
                                  {c}
                                </option>
                              ))}
                          </select>
                        </label>

                        <button
                          type="button"
                          className="ax-row-remove"
                          onClick={() =>
                            setRows((list) =>
                              list.length === 1
                                ? [blankRow()]
                                : list.filter((r) => r.uid !== row.uid)
                            )
                          }
                          aria-label="Remove this line"
                          title="Remove this line"
                        >
                          &times;
                        </button>

                        {isTransformer(type) && (
                          <div className="ax-tx-fields">
                            <p className="ax-tx-note">
                              Recorded as one transformer in the register, with its own serial number.
                            </p>

                            <label className="field">
                              <span>Serial no. *</span>
                              <input
                                type="text"
                                value={row.serialNo}
                                maxLength={60}
                                placeholder="e.g. T12U025030051"
                                onChange={(e) => setRow(row.uid, { serialNo: e.target.value })}
                                className={errors[`serial-${row.uid}`] ? 'invalid' : ''}
                              />
                              {errors[`serial-${row.uid}`] && (
                                <em className="field-error">{errors[`serial-${row.uid}`]}</em>
                              )}
                            </label>

                            <label className="field">
                              <span>Substation *</span>
                              <input
                                type="text"
                                value={row.substation}
                                maxLength={255}
                                placeholder="e.g. Lower King Street"
                                onChange={(e) => setRow(row.uid, { substation: e.target.value })}
                                className={errors[`sub-${row.uid}`] ? 'invalid' : ''}
                              />
                              {errors[`sub-${row.uid}`] && (
                                <em className="field-error">{errors[`sub-${row.uid}`]}</em>
                              )}
                            </label>

                            <label className="field">
                              <span>SIN no.</span>
                              <input
                                type="text"
                                value={row.sinNo}
                                maxLength={40}
                                placeholder="e.g. UBB 055"
                                onChange={(e) => setRow(row.uid, { sinNo: e.target.value })}
                              />
                            </label>

                            <label className="field">
                              <span>Capacity (kVA)</span>
                              <input
                                type="number"
                                min="0"
                                value={row.capacity}
                                placeholder="e.g. 250"
                                onChange={(e) => setRow(row.uid, { capacity: e.target.value })}
                              />
                            </label>

                            <label className="field">
                              <span>Manufacturer</span>
                              <input
                                type="text"
                                value={row.manufacturer}
                                maxLength={80}
                                placeholder="e.g. LTL"
                                onChange={(e) => setRow(row.uid, { manufacturer: e.target.value })}
                              />
                            </label>
                          </div>
                        )}
                      </li>
                    );
                  })}
                </ul>

                <button
                  type="button"
                  className="dash-btn-quiet dash-btn-sm"
                  onClick={() => setRows((list) => [...list, blankRow()])}
                  disabled={rows.length >= MAX_ROWS}
                >
                  + Another asset
                </button>

                {rows.length >= MAX_ROWS && (
                  <p className="ax-block-hint">
                    {MAX_ROWS} lines at a time. Save these, then add more.
                  </p>
                )}
              </section>

              {pending.length > 0 && (
                <div className="ax-pending">
                  This entry adds{' '}
                  {pending
                    .map(
                      (p) =>
                        `${formatNumber(p.quantity, decimalsFor(p.unit))} ${p.unit}`
                    )
                    .join(' and ')}
                  {chosenCsc ? ` to ${chosenCsc.csc_name} CSC.` : '.'}
                </div>
              )}

              {saveError && <div className="dialog-error">{saveError}</div>}
            </>
          )}
        </div>

        <footer className="dialog-foot">
          <span />

          <div className="dialog-foot-right">
            {result ? (
              <>
                <button
                  type="button"
                  className="dash-btn-quiet"
                  onClick={addMoreHere}
                >
                  Add more here
                </button>
                <button
                  type="button"
                  className="dash-btn-primary"
                  onClick={onClose}
                >
                  Done
                </button>
              </>
            ) : (
              <>
                <button type="button" className="dash-btn-quiet" onClick={onClose}>
                  Cancel
                </button>
                <button
                  type="button"
                  className="dash-btn-primary"
                  onClick={save}
                  disabled={saving || !ready}
                >
                  {saving ? 'Saving...' : 'Save assets'}
                </button>
              </>
            )}
          </div>
        </footer>
      </div>
    </div>
  );
};

export default AddAssetsDialog;
