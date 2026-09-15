import React, { useEffect, useState } from 'react';

import axiosClient from '../../api/axiosClient';
import { num, formatNumber } from '../Dashboard/Components/data';

/*
 * One transformer, in full.
 *
 * Three things, in the order somebody asks them: what it is, where it
 * is, and what else is there. The last one is why the CSC holdings are
 * included — "where is it" answered with a CSC name alone is a label,
 * not a location.
 */

const Row = ({ label, children }) => (
  <div className="ax-detail-row">
    <span>{label}</span>
    <strong>{children ?? <em className="ax-blank">not recorded</em>}</strong>
  </div>
);

const km = (v) =>
  v === null || v === undefined || v === '' ? null : `${formatNumber(v, 3)} km`;

const TransformerDialog = ({ transformerId, onClose }) => {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!transformerId) return undefined;

    let cancelled = false;
    setLoading(true);
    setError('');
    setData(null);

    axiosClient
      .get(`/network/transformers/${transformerId}`)
      .then(({ data: body }) => {
        if (!cancelled) setData(body);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(
          err.response?.status === 404
            ? 'That transformer is no longer in the register.'
            : err.response
            ? `The server returned ${err.response.status}.`
            : 'Could not reach the API.'
        );
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [transformerId]);

  useEffect(() => {
    if (!transformerId) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [transformerId, onClose]);

  if (!transformerId) return null;

  const tx = data?.transformer;
  const segments = data?.segments || [];
  const holdings = data?.csc_holdings || [];

  return (
    <div className="dialog-backdrop" role="presentation" onClick={onClose}>
      <div
        className="dialog ax-detail-dialog"
        role="dialog"
        aria-modal="true"
        aria-label="Transformer details"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="dialog-head">
          <div>
            <h2>{tx?.substation_name || 'Transformer'}</h2>
            <p>
              {tx
                ? `${tx.type_name} · ${tx.csc_name} CSC · ${tx.area_name} area`
                : 'Loading the record...'}
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
          {loading && <div className="dialog-notice">Loading transformer...</div>}
          {error && <div className="dialog-error">{error}</div>}

          {tx && (
            <>
              {/* A retired unit found by a search must say so here, or
                  the reader takes the record for a live asset. */}
              {tx.status !== 'ACTIVE' && (
                <div className="dialog-notice ax-status-warn">
                  This transformer is marked <strong>{tx.status}</strong>. It is
                  not counted in the province totals.
                </div>
              )}

              <div className="ax-detail-grid">
                <section>
                  <h3>Identity</h3>
                  <Row label="Record id">{tx.transformer_id}</Row>
                  <Row label="Old SIN no.">{tx.old_sin_no}</Row>
                  <Row label="New SIN no.">{tx.new_sin_no}</Row>
                  <Row label="Serial no.">{tx.transformer_no}</Row>
                  <Row label="Manufacturer">{tx.manufacturer}</Row>
                  <Row label="Substation">{tx.substation_name}</Row>
                </section>

                <section>
                  <h3>Rating and condition</h3>
                  <Row label="Asset type">{tx.type_name}</Row>
                  <Row label="Register type">{tx.transformer_type}</Row>
                  <Row label="Capacity">
                    {tx.capacity_kva
                      ? `${formatNumber(tx.capacity_kva, 2)} kVA`
                      : null}
                  </Row>
                  <Row label="Units">{formatNumber(tx.quantity)}</Row>
                  <Row label="Condition">
                    {tx.condition_status === 'UNKNOWN' ? null : tx.condition_status}
                  </Row>
                  <Row label="Status">{tx.status}</Row>
                </section>

                <section>
                  <h3>Location</h3>
                  <Row label="Province">{tx.province_name}</Row>
                  <Row label="Area">
                    {tx.area_name} ({tx.area_code})
                  </Row>
                  <Row label="CSC">
                    {tx.csc_name} ({tx.csc_code})
                  </Row>
                  <Row label="Coordinates">
                    {tx.latitude && tx.longitude
                      ? `${tx.latitude}, ${tx.longitude}`
                      : null}
                  </Row>
                  <Row label="Installed">{tx.install_date}</Row>
                </section>

                <section>
                  <h3>Line and wayleave</h3>
                  <Row label="Fly length">{km(tx.fly_length_km)}</Row>
                  <Row label="Combined fly length">{km(tx.combined_fly_length_km)}</Row>
                  <Row label="Free wayleave">{km(tx.free_wayleave_km)}</Row>
                  <Row label="To wayleave">{km(tx.wayleave_distance_km)}</Row>
                  <Row label="Total distance">{km(tx.total_distance_km)}</Row>
                </section>

                <section>
                  <h3>Record</h3>
                  <Row label="Source">{tx.source_file}</Row>
                  <Row label="Added">{tx.created_at}</Row>
                  <Row label="Last changed">{tx.updated_at}</Row>
                  <Row label="Remarks">{tx.remarks}</Row>
                </section>
              </div>

              <section className="ax-detail-block">
                <h3>
                  On {segments.length}{' '}
                  {segments.length === 1 ? 'segment' : 'segments'}
                </h3>

                {segments.length === 0 ? (
                  <p className="ax-blank-block">
                    No register segment names this transformer. That is a gap in
                    the linkage, not necessarily in the network.
                  </p>
                ) : (
                  <div className="depot-table-wrapper ax-mini-table">
                    <table className="depot-table">
                      <thead>
                        <tr>
                          <th>Segment</th>
                          <th>Feeder</th>
                          <th>Voltage</th>
                          <th className="numeric">Length km</th>
                          <th>Named as</th>
                        </tr>
                      </thead>
                      <tbody>
                        {segments.map((s) => (
                          <tr key={s.register_id}>
                            <td>
                              <span className="depot-name">{s.segment_code}</span>
                            </td>
                            <td>{s.feeder_code || '—'}</td>
                            <td>{s.voltage_level || '—'}</td>
                            <td className="numeric">
                              {formatNumber(s.length_km, 3)}
                            </td>
                            <td>{s.transformer_ref}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>

              <section className="ax-detail-block">
                <h3>What {tx.csc_name} CSC holds</h3>
                <p className="ax-block-hint">
                  Everything recorded at the same CSC, so the transformer sits in
                  a place rather than on its own.
                </p>

                <ul className="ax-holdings">
                  {holdings.map((h) => (
                    <li key={`${h.category_name}-${h.unit_of_measure}`}>
                      <span className="ax-holding-name">{h.category_name}</span>
                      <span className="ax-holding-value">
                        {formatNumber(h.quantity, h.unit_of_measure === 'km' ? 3 : 0)}{' '}
                        <em>{h.unit_of_measure}</em>
                      </span>
                      <span className="ax-holding-recs">
                        {formatNumber(h.records)}{' '}
                        {num(h.records) === 1 ? 'record' : 'records'}
                      </span>
                    </li>
                  ))}
                </ul>
              </section>
            </>
          )}
        </div>

        <footer className="dialog-foot">
          <span />
          <div className="dialog-foot-right">
            <button type="button" className="dash-btn-primary" onClick={onClose}>
              Close
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
};

export default TransformerDialog;
