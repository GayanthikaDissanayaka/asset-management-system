import React, { useMemo } from 'react';

/*
 * Province -> Area -> CSC, as three linked pickers.
 *
 * Linked in both directions. Choosing a province narrows the areas;
 * choosing an area narrows the CSCs. Choosing a CSC first fills in its
 * area and province, so the three never describe places that contradict
 * each other -- "Badulla CSC" in "Monaragala area" cannot be selected.
 *
 * Used on the dashboard, where one choice filters the tiles, the charts
 * and every register tab together. A page where the tile said one place
 * and the table another would be worse than no filter.
 */

export const EMPTY_PLACE = { provinceId: '', areaId: '', cscId: '' };

export const isPlaceSet = (place) =>
  Boolean(place && (place.provinceId || place.areaId || place.cscId));

/** The place as the API expects it. Blank levels are left out. */
export const placeParams = (place) => ({
  province_id: place?.provinceId || undefined,
  area_id: place?.areaId || undefined,
  csc_id: place?.cscId || undefined,
});

/** "Badulla CSC · Badulla area", "Badulla area", "Uva Province". */
export function describePlace(place, options) {
  const areas = options?.areas || [];
  const cscs = options?.cscs || [];
  const provinces = options?.provinces || [];

  if (place?.cscId) {
    const csc = cscs.find((c) => String(c.csc_id) === String(place.cscId));
    const area = csc && areas.find((a) => String(a.area_id) === String(csc.area_id));
    if (csc) return `${csc.csc_name} CSC${area ? ` · ${area.area_name} area` : ''}`;
  }

  if (place?.areaId) {
    const area = areas.find((a) => String(a.area_id) === String(place.areaId));
    if (area) return `${area.area_name} area`;
  }

  if (place?.provinceId) {
    const province = provinces.find((p) => String(p.province_id) === String(place.provinceId));
    if (province) return `${province.province_name} Province`;
  }

  return 'Whole province';
}

/**
 * Fills in the levels above whatever was chosen.
 *
 * A link or a search result may name only a CSC (`?csc_id=4`). Without
 * this the pickers read "Badulla" under CSC but "All areas" under Area,
 * which looks like two different filters and neither is true.
 */
export function completePlace(place, options) {
  if (!place || !options) return place || EMPTY_PLACE;

  let { provinceId, areaId } = place;

  if (place.cscId && !areaId) {
    const csc = (options.cscs || []).find((c) => String(c.csc_id) === String(place.cscId));
    if (csc) areaId = String(csc.area_id);
  }

  if (areaId && !provinceId) {
    const area = (options.areas || []).find((a) => String(a.area_id) === String(areaId));
    if (area) provinceId = String(area.province_id);
  }

  if (areaId === place.areaId && provinceId === place.provinceId) return place;
  return { ...place, areaId, provinceId };
}

const PlaceFilter = ({ options, value = EMPTY_PLACE, onChange, disabled }) => {
  const provinces = options?.provinces || [];

  const areas = useMemo(
    () =>
      (options?.areas || []).filter(
        (a) => !value.provinceId || String(a.province_id) === String(value.provinceId)
      ),
    [options, value.provinceId]
  );

  const cscs = useMemo(() => {
    const allowedAreas = new Set(areas.map((a) => String(a.area_id)));
    return (options?.cscs || []).filter((c) =>
      value.areaId
        ? String(c.area_id) === String(value.areaId)
        : allowedAreas.has(String(c.area_id))
    );
  }, [options, areas, value.areaId]);

  const areaOf = (areaId) =>
    (options?.areas || []).find((a) => String(a.area_id) === String(areaId));

  const pickProvince = (provinceId) =>
    onChange({ provinceId, areaId: '', cscId: '' });

  const pickArea = (areaId) => {
    const area = areaOf(areaId);
    onChange({
      provinceId: area ? String(area.province_id) : value.provinceId,
      areaId,
      cscId: '',
    });
  };

  const pickCsc = (cscId) => {
    const csc = (options?.cscs || []).find((c) => String(c.csc_id) === String(cscId));
    const area = csc && areaOf(csc.area_id);
    onChange({
      provinceId: area ? String(area.province_id) : value.provinceId,
      areaId: csc ? String(csc.area_id) : value.areaId,
      cscId,
    });
  };

  const ready = Boolean(options) && !disabled;

  return (
    <div className="pf" role="group" aria-label="Filter by place">
      <label className="pf-field">
        <span>Province</span>
        <select
          value={value.provinceId}
          onChange={(e) => pickProvince(e.target.value)}
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

      <label className="pf-field">
        <span>Area</span>
        <select
          value={value.areaId}
          onChange={(e) => pickArea(e.target.value)}
          disabled={!ready}
        >
          <option value="">All areas</option>
          {areas.map((a) => (
            <option key={a.area_id} value={a.area_id}>
              {a.area_name}
            </option>
          ))}
        </select>
      </label>

      <label className="pf-field">
        <span>CSC</span>
        <select
          value={value.cscId}
          onChange={(e) => pickCsc(e.target.value)}
          disabled={!ready}
        >
          <option value="">{value.areaId ? 'All CSCs in this area' : 'All CSCs'}</option>
          {cscs.map((c) => (
            <option key={c.csc_id} value={c.csc_id}>
              {c.csc_name}
            </option>
          ))}
        </select>
      </label>

      {isPlaceSet(value) && (
        <button
          type="button"
          className="dash-btn-quiet dash-btn-sm pf-clear"
          onClick={() => onChange(EMPTY_PLACE)}
        >
          Show everything
        </button>
      )}
    </div>
  );
};

export default PlaceFilter;
