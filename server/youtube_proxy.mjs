// Optional, separately deployed service. Never put this key in the mobile app.
// Node 22+, no third-party packages. Deploy behind HTTPS and a rate limiter.
import http from 'node:http';
const key = process.env.YOUTUBE_API_KEY;
const port = Number(process.env.PORT || 8080);
const cache = new Map();
const limits = new Map();
if (!key) throw new Error('Set YOUTUBE_API_KEY on the server.');

http.createServer(async (req, res) => {
  const json = (status, body) => {
    res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    res.end(JSON.stringify(body));
  };
  const url = new URL(req.url, 'http://localhost');
  if (req.method !== 'GET' || url.pathname !== '/youtube/search') return json(404, { error: 'Not found' });
  const q = url.searchParams.get('q')?.trim();
  if (!q || q.length > 150) return json(400, { error: 'Query must be 1–150 characters.' });
  const ip = req.socket.remoteAddress;
  const now = Date.now();
  const limit = limits.get(ip);
  if (limit && now - limit.start < 60_000 && limit.count >= 10) return json(429, { error: 'Please try again later.' });
  limits.set(ip, !limit || now - limit.start >= 60_000 ? { start: now, count: 1 } : { ...limit, count: limit.count + 1 });
  for (const [address, value] of limits) if (now - value.start > 60_000) limits.delete(address);
  const cached = cache.get(q.toLowerCase());
  if (cached && now - cached.at < 300_000) return json(200, cached.data);
  try {
    const api = new URL('https://www.googleapis.com/youtube/v3/search');
    api.search = new URLSearchParams({ key, part: 'snippet', type: 'video', maxResults: '20', q }).toString();
    const response = await fetch(api, { signal: AbortSignal.timeout(12_000) });
    if (!response.ok) return json(response.status === 403 ? 429 : 502, { error: 'YouTube discovery unavailable.' });
    const data = await response.json();
    if (cache.size >= 200) cache.delete(cache.keys().next().value);
    cache.set(q.toLowerCase(), { at: now, data });
    json(200, data);
  } catch { json(502, { error: 'Discovery unavailable.' }); }
}).listen(port, '127.0.0.1', () => console.log(`Discovery proxy listening on port ${port}`));
