import { useEffect, useState } from 'react';
import axiosClient from '../api/axiosClient';

// Pulls the depot -> area -> province roll-up from the dashboard endpoints.
export default function useAssetSummary() {
  const [depotTotals, setDepotTotals] = useState([]);
  const [areaTotals, setAreaTotals] = useState([]);
  const [provinceTotal, setProvinceTotal] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    Promise.all([
      axiosClient.get('/dashboard/depot-totals'),
      axiosClient.get('/dashboard/area-totals'),
      axiosClient.get('/dashboard/province-total'),
    ])
      .then(([depotRes, areaRes, provinceRes]) => {
        setDepotTotals(depotRes.data);
        setAreaTotals(areaRes.data);
        setProvinceTotal(provinceRes.data);
      })
      .catch(setError)
      .finally(() => setLoading(false));
  }, []);

  return { depotTotals, areaTotals, provinceTotal, loading, error };
}
