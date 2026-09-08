import React, { useEffect, useMemo, useState } from 'react';

import axiosClient from '../../../api/axiosClient';
import { describeWriteError } from './session';
import { num, formatNumber } from './data';

/**
 * Two-step segment entry.
 *
 *   Step 1  where the segment runs and what it is made of: Province,
 *           Area, the CSCs it passes through with the kilometres inside
 *           each, Feeder, segment code, voltage, and conductor lengths.
 *
 *   Step 2  what sits on it: switchgear, substations, poles and the rest,
 *           counted.
 *
 * A segment can cross a CSC boundary, so the CSC is a repeatable row
 * rather than a single choice. Each row carries its own length, and the
 * route length is their sum rather than a field of its own: entering both
 * would let them disagree. Those portions are what the area roll-up adds
 * up, so a run from a CSC in one area into a CSC in another puts only its
 * own kilometres in each area.
 *
 * Province and Area steer the pickers but are not stored. Both follow
 * from the CSC through csc_depots, so storing them again would let them
 * drift apart.
 */

const MAX_CSC_ROWS = 6;

const EMPTY_FORM = {
  provinceId: '',
  areaId: '',
  feederId: '',
  segmentCode: '',
  voltageLevel: '33kV',
  remarks: '',
};

const blankCscRow = () => ({ uid: Math.random().toString(36).slice(2), cscId: '', lengthKm: '' });

const AddSegmentDialog = ({ open, options, optionsError, onRetryOptions, onClose, onSaved }) => {
  const [step, setStep] = useState(1);
  const [form, setForm] = useState(EMPTY_FORM);
  const [cscRows, setCscRows] = useState([blankCscRow()]);
  const [quantities, setQuantities] = useState({});
  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState('');

  // Reset every time the dialog is opened, so a previous entry never
  // bleeds into the next one.
  useEffect(() => {
    if (open) {
      setStep(1);
      setForm(EMPTY_FORM);
      setCscRows([blankCscRow()]);
      setQuantities({});
      setErrors({});
      setSaveError('');
    }
  }, [open]);

  // Close on Escape, the behaviour a dialog is expected to have.
  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  /* Derived in one memo so each list keeps a stable identity between
     renders. Writing `options?.areas || []` inline would build a fresh
     array every render and defeat every memo below it. */
  const {
    provinces,
    allAreas,
    allCscs,
    allFeeders,
    conductorTypes,
    countedTypes,
  } = useMemo(
    () => ({
      provinces: options?.provinces || [],
      allAreas: options?.areas || [],
      allCscs: options?.cscs || [],
      allFeeders: options?.feeders || [],
      conductorTypes: options?.conductorTypes || [],
      countedTypes: options?.countedTypes || [],
    }),
    [options]
  );

  const ready = Boolean(options) && allAreas.length > 0;

  const areas = useMemo(
    () =>
      form.provinceId
        ? allAreas.filter((a) => String(a.province_id) === String(form.provinceId))
        : allAreas,
    [allAreas, form.provinceId]
  );

  /* CSCs in the chosen area come first. A crossing segment often runs
     into a neighbouring area, so the rest stay selectable below. */
  const { areaCscs, otherCscs } = useMemo(() => {
    if (!form.areaId) return { areaCscs: [], otherCscs: allCscs };
    return {
      areaCscs: allCscs.filter((c) => String(c.area_id) === String(form.areaId)),
      otherCscs: allCscs.filter((c) => String(c.area_id) !== String(form.areaId)),
    };
  }, [allCscs, form.areaId]);

  const primaryCscId = cscRows[0]?.cscId || '';

  const { ownFeeders, otherFeeders } = useMemo(() => {
    if (!primaryCscId) return { ownFeeders: [], otherFeeders: allFeeders };
    return {
      ownFeeders: allFeeders.filter(
        (f) => String(f.origin_csc_id) === String(primaryCscId)
      ),
      otherFeeders: allFeeders.filter(
        (f) => String(f.origin_csc_id) !== String(primaryCscId)
      ),
    };
  }, [allFeeders, primaryCscId]);

  const routeLength = useMemo(
    () => cscRows.reduce((sum, r) => sum + num(r.lengthKm), 0),
    [cscRows]
  );

  const conductorTotal = useMemo(
    () => conductorTypes.reduce((sum, t) => sum + num(quantities[t.asset_type_id]), 0),
    [conductorTypes, quantities]
  );

  const countedTotal = useMemo(
    () => countedTypes.reduce((sum, t) => sum + num(quantities[t.asset_type_id]), 0),
    [countedTypes, quantities]
  );

  const lengthMismatch =
    routeLength > 0 &&
    conductorTotal > 0 &&
    Math.abs(conductorTotal - routeLength) > 0.005;

  /* Counted types grouped under their category headings. Twenty-five
     flat number boxes is a wall; grouped, it is a short list. */
  const countedGroups = useMemo(() => {
    const map = new Map();
    for (const t of countedTypes) {
      const name = t.category_name || 'Other';
      if (!map.has(name)) map.set(name, []);
      map.get(name).push(t);
    }
    return Array.from(map.entries());
  }, [countedTypes]);

  const cscLabel = (id) => {
    const c = allCscs.find((x) => String(x.csc_id) === String(id));
    return c ? c.csc_name : '';
  };

  const setField = (name, value) => {
    setForm((f) => {
      const next = { ...f, [name]: value };
      if (name === 'provinceId') {
        next.areaId = '';
        next.feederId = '';
      }
      if (name === 'areaId') {
        next.feederId = '';
      }
      return next;
    });
    if (name === 'provinceId' || name === 'areaId') setCscRows([blankCscRow()]);
    setErrors((e) => ({ ...e, [name]: '' }));
    setSaveError('');
  };

  const setCscRow = (uid, patch) => {
    setCscRows((rows) => rows.map((r) => (r.uid === uid ? { ...r, ...patch } : r)));
    setErrors((e) => ({ ...e, cscs: '' }));
    setSaveError('');
  };

  const addCscRow = () =>
    setCscRows((rows) =>
      rows.length >= MAX_CSC_ROWS ? rows : [...rows, blankCscRow()]
    );

  const removeCscRow = (uid) =>
    setCscRows((rows) => (rows.length === 1 ? rows : rows.filter((r) => r.uid !== uid)));

  const setQuantity = (typeId, value) => {
    setQuantities((q) => ({ ...q, [typeId]: value }));
    setSaveError('');
  };

  const validateStepOne = () => {
    const next = {};

    if (!ready) next.form = 'The reference data has not loaded yet.';
    if (!form.areaId) next.areaId = 'Choose an area.';

    const chosen = cscRows.filter((r) => r.cscId);
    if (chosen.length === 0) {
      next.cscs = 'Choose at least one CSC.';
    } else {
      const ids = chosen.map((r) => String(r.cscId));
      if (new Set(ids).size !== ids.length) {
        next.cscs = 'The same CSC is listed twice.';
      } else if (chosen.length > 1 && chosen.some((r) => num(r.lengthKm) <= 0)) {
        next.cscs =
          'A segment crossing more than one CSC needs a length for each part.';
      }
    }

    if (!form.segmentCode.trim()) next.segmentCode = 'Enter the segment ID.';
    else if (form.segmentCode.trim().length > 60)
      next.segmentCode = 'Segment ID is too long.';

    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const goNext = () => {
    if (validateStepOne()) setStep(2);
  };

  const submit = async () => {
    if (!validateStepOne()) {
      setStep(1);
      return;
    }

    const items = Object.entries(quantities)
      .map(([id, value]) => ({ asset_type_id: Number(id), quantity: num(value) }))
      .filter((i) => i.quantity > 0);

    const cscs = cscRows
      .filter((r) => r.cscId)
      .map((r) => ({ csc_id: Number(r.cscId), length_km: num(r.lengthKm) }));

    try {
      setSaving(true);
      setSaveError('');

      const { data } = await axiosClient.post('/network/segments', {
        cscs,
        feeder_id: form.feederId ? Number(form.feederId) : null,
        segment_code: form.segmentCode.trim(),
        voltage_level: form.voltageLevel,
        remarks: form.remarks.trim() || null,
        items,
      });

      onSaved(data?.message || 'Segment saved.');
    } catch (err) {
      const fieldErrors = err.response?.data?.errors;
      if (fieldErrors?.segment_code) {
        setErrors((e) => ({ ...e, segmentCode: fieldErrors.segment_code[0] }));
        setStep(1);
      }
      setSaveError(describeWriteError(err));
    } finally {
      setSaving(false);
    }
  };

  if (!open) return null;

  const chosenCscNames = cscRows
    .filter((r) => r.cscId)
    .map((r) => cscLabel(r.cscId))
    .filter(Boolean);

  return (
    <div
      className="dialog-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-segment-title"
      >
        <header className="dialog-head">
          <div>
            <h2 id="add-segment-title">Add a segment</h2>
            <p>
              {step === 1
                ? 'Where the segment runs, and the conductor it is built from.'
                : `What is installed along ${
                    chosenCscNames.join(' and ') || 'this segment'
                  }.`}
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

        <ol className="dialog-steps" aria-label="Progress">
          <li className={step === 1 ? 'is-current' : 'is-done'}>
            <span className="step-dot">1</span> Location and conductor
          </li>
          <li className={step === 2 ? 'is-current' : undefined}>
            <span className="step-dot">2</span> Feeders and other assets
          </li>
        </ol>

        <div className="dialog-body">
          {/* Without this the dropdowns are simply empty and Next refuses
              to advance with nothing on screen explaining why. */}
          {!options && !optionsError && (
            <div className="dialog-notice">Loading areas, CSCs and feeders...</div>
          )}

          {optionsError && (
            <div className="dialog-error">
              {optionsError}{' '}
              {onRetryOptions && (
                <button type="button" className="link-button" onClick={onRetryOptions}>
                  Try again
                </button>
              )}
            </div>
          )}

          {step === 1 ? (
            <>
              <div className="field-grid">
                <label className="field">
                  <span>Province</span>
                  <select
                    value={form.provinceId}
                    onChange={(e) => setField('provinceId', e.target.value)}
                    disabled={!ready}
                  >
                    <option value="">All provinces</option>
                    {provinces.map((p) => (
                      <option key={p.province_id} value={p.province_id}>
                        {p.province_name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>Area *</span>
                  <select
                    value={form.areaId}
                    onChange={(e) => setField('areaId', e.target.value)}
                    disabled={!ready}
                    className={errors.areaId ? 'invalid' : ''}
                  >
                    <option value="">Select an area</option>
                    {areas.map((a) => (
                      <option key={a.area_id} value={a.area_id}>
                        {a.area_name} ({a.area_code})
                      </option>
                    ))}
                  </select>
                  {errors.areaId && <em className="field-error">{errors.areaId}</em>}
                </label>

                <label className="field">
                  <span>Segment ID *</span>
                  <input
                    type="text"
                    value={form.segmentCode}
                    placeholder="e.g. BDSM010"
                    onChange={(e) => setField('segmentCode', e.target.value)}
                    className={errors.segmentCode ? 'invalid' : ''}
                  />
                  {errors.segmentCode && (
                    <em className="field-error">{errors.segmentCode}</em>
                  )}
                </label>

                <label className="field">
                  <span>Voltage</span>
                  <select
                    value={form.voltageLevel}
                    onChange={(e) => setField('voltageLevel', e.target.value)}
                  >
                    {(options?.voltageLevels || ['33kV', '11kV', '400V']).map((v) => (
                      <option key={v} value={v}>
                        {v}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>Feeder</span>
                  <select
                    value={form.feederId}
                    onChange={(e) => setField('feederId', e.target.value)}
                    disabled={!primaryCscId}
                  >
                    <option value="">Not recorded</option>
                    {ownFeeders.length > 0 && (
                      <optgroup label="Originating at this CSC">
                        {ownFeeders.map((f) => (
                          <option key={f.feeder_id} value={f.feeder_id}>
                            {f.feeder_code} — {f.feeder_name}
                          </option>
                        ))}
                      </optgroup>
                    )}
                    {otherFeeders.length > 0 && (
                      <optgroup label="Other feeders">
                        {otherFeeders.map((f) => (
                          <option key={f.feeder_id} value={f.feeder_id}>
                            {f.feeder_code} — {f.feeder_name}
                          </option>
                        ))}
                      </optgroup>
                    )}
                  </select>
                </label>
              </div>

              <div className="dialog-section">
                <div className="dialog-section-head">
                  <h3>CSCs this segment runs through</h3>
                  <span className="dialog-section-note">
                    Add a row per CSC, with the kilometres inside it. Only that
                    share counts towards the CSC and its area.
                  </span>
                </div>

                <div className="csc-rows">
                  {cscRows.map((row, index) => (
                    <div className="csc-row" key={row.uid}>
                      <label className="field">
                        <span>{index === 0 ? 'CSC *' : `CSC ${index + 1}`}</span>
                        <select
                          value={row.cscId}
                          onChange={(e) => setCscRow(row.uid, { cscId: e.target.value })}
                          disabled={!form.areaId}
                        >
                          <option value="">
                            {form.areaId ? 'Select a CSC' : 'Choose an area first'}
                          </option>
                          {areaCscs.length > 0 && (
                            <optgroup label="In the selected area">
                              {areaCscs.map((c) => (
                                <option key={c.csc_id} value={c.csc_id}>
                                  {c.csc_name} ({c.csc_code})
                                </option>
                              ))}
                            </optgroup>
                          )}
                          {otherCscs.length > 0 && (
                            <optgroup label="Other areas">
                              {otherCscs.map((c) => (
                                <option key={c.csc_id} value={c.csc_id}>
                                  {c.csc_name} ({c.csc_code})
                                </option>
                              ))}
                            </optgroup>
                          )}
                        </select>
                      </label>

                      <label className="field csc-row-length">
                        <span>Length in this CSC (km)</span>
                        <input
                          type="number"
                          min="0"
                          step="0.001"
                          placeholder="0.000"
                          value={row.lengthKm}
                          onChange={(e) =>
                            setCscRow(row.uid, { lengthKm: e.target.value })
                          }
                        />
                      </label>

                      <button
                        type="button"
                        className="csc-row-remove"
                        onClick={() => removeCscRow(row.uid)}
                        disabled={cscRows.length === 1}
                        aria-label={`Remove CSC ${index + 1}`}
                        title={
                          cscRows.length === 1
                            ? 'A segment needs at least one CSC'
                            : 'Remove this CSC'
                        }
                      >
                        &times;
                      </button>
                    </div>
                  ))}
                </div>

                {errors.cscs && <em className="field-error">{errors.cscs}</em>}

                <div className="csc-rows-foot">
                  <button
                    type="button"
                    className="btn-quiet btn-sm"
                    onClick={addCscRow}
                    disabled={cscRows.length >= MAX_CSC_ROWS || !form.areaId}
                  >
                    + Add another CSC
                  </button>

                  <span className="csc-rows-total">
                    Route length <strong>{formatNumber(routeLength, 3)} km</strong>
                    {cscRows.filter((r) => r.cscId).length > 1 &&
                      ` across ${cscRows.filter((r) => r.cscId).length} CSCs`}
                  </span>
                </div>
              </div>

              <div className="dialog-section">
                <div className="dialog-section-head">
                  <h3>MV conductor length</h3>
                  <span className="dialog-section-note">
                    Kilometres of each conductor along this segment
                  </span>
                </div>

                <div className="quantity-grid">
                  {conductorTypes.map((t) => (
                    <label className="quantity-field" key={t.asset_type_id}>
                      <span>{t.type_name.replace(' Conductor', '')}</span>
                      <input
                        type="number"
                        min="0"
                        step="0.001"
                        placeholder="0.000"
                        value={quantities[t.asset_type_id] ?? ''}
                        onChange={(e) => setQuantity(t.asset_type_id, e.target.value)}
                      />
                    </label>
                  ))}
                </div>

                <div className={`dialog-tally${lengthMismatch ? ' is-warning' : ''}`}>
                  <span>Conductor total</span>
                  <strong>{formatNumber(conductorTotal, 3)} km</strong>
                  {routeLength > 0 && conductorTotal > 0 && (
                    <span className="dialog-tally-note">
                      {lengthMismatch
                        ? `does not match the ${formatNumber(routeLength, 3)} km route length`
                        : 'matches the route length'}
                    </span>
                  )}
                </div>
              </div>
            </>
          ) : (
            <>
              <div className="dialog-recap">
                <span>
                  <strong>{form.segmentCode.trim()}</strong> at{' '}
                  {chosenCscNames.join(' and ')}
                </span>
                <span>
                  {formatNumber(routeLength, 3)} km &middot; {form.voltageLevel}
                </span>
                <span>{formatNumber(conductorTotal, 3)} km conductor</span>
              </div>

              <div className="dialog-section">
                <div className="dialog-section-head">
                  <h3>Assets on this segment</h3>
                  <span className="dialog-section-note">
                    Counted items. Leave blank where there are none.
                  </span>
                </div>

                {countedGroups.map(([category, types]) => (
                  <div className="quantity-group" key={category}>
                    <h4>{category}</h4>
                    <div className="quantity-grid">
                      {types.map((t) => (
                        <label className="quantity-field" key={t.asset_type_id}>
                          <span>{t.type_name}</span>
                          <input
                            type="number"
                            min="0"
                            step="1"
                            placeholder="0"
                            value={quantities[t.asset_type_id] ?? ''}
                            onChange={(e) => setQuantity(t.asset_type_id, e.target.value)}
                          />
                        </label>
                      ))}
                    </div>
                  </div>
                ))}

                <div className="dialog-tally">
                  <span>Items counted</span>
                  <strong>{formatNumber(countedTotal)}</strong>
                </div>
              </div>
            </>
          )}

          {saveError && <div className="dialog-error">{saveError}</div>}
        </div>

        <footer className="dialog-foot">
          <button type="button" className="btn-quiet" onClick={onClose}>
            Cancel
          </button>

          <div className="dialog-foot-right">
            {step === 2 && (
              <button
                type="button"
                className="btn-quiet"
                onClick={() => setStep(1)}
                disabled={saving}
              >
                &larr; Back
              </button>
            )}

            {step === 1 ? (
              <button
                type="button"
                className="btn-primary"
                onClick={goNext}
                disabled={!ready}
                title={!ready ? 'Waiting for the reference data to load' : undefined}
              >
                Next &rarr;
              </button>
            ) : (
              <button
                type="button"
                className="btn-primary"
                onClick={submit}
                disabled={saving}
              >
                {saving ? 'Saving...' : 'Save segment'}
              </button>
            )}
          </div>
        </footer>
      </div>
    </div>
  );
};

export default AddSegmentDialog;
