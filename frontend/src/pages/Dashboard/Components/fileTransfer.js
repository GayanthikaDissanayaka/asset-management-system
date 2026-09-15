import axiosClient from '../../../api/axiosClient';

/**
 * Downloads a file from the API.
 *
 * A plain <a href> would miss the Authorization header the axios client
 * attaches, so the file is fetched as a blob and handed to a temporary
 * object URL instead. The URL is revoked afterwards; without that the
 * blob stays in memory for the life of the tab.
 */
export async function downloadFromApi(path, fallbackName) {
  const response = await axiosClient.get(path, { responseType: 'blob' });

  // Prefer the name the server gave, so the date it stamps is kept.
  const disposition = response.headers?.['content-disposition'] || '';
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition);
  const filename = match ? decodeURIComponent(match[1]) : fallbackName;

  const url = window.URL.createObjectURL(new Blob([response.data]));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);

  return filename;
}

/** Uploads one spreadsheet to the segment importer. */
export async function uploadSpreadsheet(file, { confirm = false } = {}) {
  const body = new FormData();
  body.append('file', file);
  // A transformer workbook is previewed first; confirm applies it.
  if (confirm) body.append('confirm', '1');

  const { data } = await axiosClient.post('/network/import', body, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

  return data;
}
