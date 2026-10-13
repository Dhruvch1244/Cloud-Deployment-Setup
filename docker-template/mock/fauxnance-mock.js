// Mock of the Fauxnance market-data API for testing WITHOUT a real key or quota.
// Same paths and response shapes as the real API (GET /v1/quotes/{symbol},
// /v1/quotes?symbols=, /v1/candles/{symbol}, /v1/symbols/{symbol}, /v1/usage,
// /v1/health). Any API key is accepted. Prices are made up but stable per symbol,
// with a small drift so "live" screens move. No dependencies: plain Node.
//
// Use it:  add `mock-market` to COMPOSE_PROFILES and point the app at
//          http://market-mock:8089/v1   (e.g. FAUXNANCE_BASE_URL in .env section 3)
// Env:     MOCK_MARKET_STATE = open | closed | pre | post   (default open)
const http = require('http');
const PORT = process.env.PORT || 8089;
const STATE = process.env.MOCK_MARKET_STATE || 'open';
const DISCLAIMER = 'MOCK DATA from docker-template/mock - not real market data.';
const BASE = { AAPL: 187.32, MSFT: 415.2, SPY: 552.1, GOOGL: 171.4, AMZN: 186.9, NVDA: 148.2, TSLA: 245.1, META: 512.3,
  JPM: 204.6, AMD: 162.8, 'INFY.NS': 1542.5, 'TCS.NS': 3890.0, 'RELIANCE.NS': 2876.9, 'HDFCBANK.NS': 1651.2,
  'ICICIBANK.NS': 1184.4, 'SBIN.NS': 812.3, 'WIPRO.NS': 462.7, 'ITC.NS': 428.9, 'TATASTEEL.NS': 151.6, 'TATASTEEL.BO': 151.5,
  'FX:EURUSD': 1.0842, 'FX:USDINR': 83.42, 'FX:GBPUSD': 1.2710, 'X:BTCUSD': 64250.0 };
const hash = (s) => { let h = 2166136261; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return (h >>> 0); };
const round = (n, s) => { const d = /^FX:/.test(s) ? 4 : 2; return Number(n.toFixed(d)); };
const basePrice = (s) => BASE[s] ?? (20 + (hash(s) % 290000) / 100);
const currency = (s) => (/\.(NS|BO)$/.test(s) ? 'INR' : /^FX:[A-Z]{3}([A-Z]{3})$/.test(s) ? s.slice(-3) : 'USD');
const exchange = (s) => (/\.NS$/.test(s) ? 'NSE' : /\.BO$/.test(s) ? 'BSE' : /^FX:/.test(s) ? 'FX' : /^X:/.test(s) ? 'CRYPTO' : 'NASDAQ');
const type = (s) => (/^FX:/.test(s) ? 'fx' : /^X:/.test(s) ? 'crypto' : s === 'SPY' ? 'etf' : 'equity');
function quote(s) {
  const prev = basePrice(s);
  const drift = Math.sin(Date.now() / 60000 + (hash(s) % 628) / 100) * 0.004; // +-0.4 %
  const price = round(prev * (1 + drift), s);
  const spread = Math.max(price * 0.0005, /^FX:/.test(s) ? 0.0001 : 0.01);
  return { symbol: s, price, currency: currency(s), change: round(price - prev, s),
    changePercent: Number((((price - prev) / prev) * 100).toFixed(2)), previousClose: round(prev, s),
    asOf: new Date().toISOString(), marketState: STATE,
    // not in the real API, harmless extras some clients read:
    bid: round(price - spread, s), ask: round(price + spread, s) };
}
function candles(s, from, to) {
  const out = []; const end = to ? new Date(to) : new Date(); let d = from ? new Date(from) : new Date(end.getTime() - 30 * 864e5);
  if (isNaN(d) || isNaN(end)) return out;
  let p = basePrice(s) * 0.95; let n = 0;
  for (; d <= end && n < 2000; d = new Date(d.getTime() + 864e5)) {
    const wd = d.getUTCDay(); if (wd === 0 || wd === 6) continue;
    const day = d.toISOString().slice(0, 10); const r = ((hash(s + day) % 2001) - 1000) / 1000; // -1..1
    const open = p; const close = p * (1 + r * 0.015); const high = Math.max(open, close) * 1.004; const low = Math.min(open, close) * 0.996;
    out.push({ date: day, open: round(open, s), high: round(high, s), low: round(low, s), close: round(close, s),
      adjclose: round(close, s), volume: 1000000 + (hash(day + s) % 9000000), synthetic: false });
    p = close; n++;
  }
  return out;
}
const meta = () => ({ asOf: new Date().toISOString(), disclaimer: DISCLAIMER });
// Returns [statusCode, body] for a request URL.
function route(url) {
  const u = new URL(url, 'http://x'); const path = decodeURIComponent(u.pathname).replace(/\/+$/, '');
  const tail = path.replace(/^.*?\/(?=(quotes|candles|symbols|usage|health)(\/|$))/, '/');
  let m;
  if (/^\/health$/.test(tail) || path === '' || path === '/v1') return [200, { data: { status: 'ok', markets: ['US', 'IN'].map((x) => ({ market: x, latestEod: new Date().toISOString().slice(0, 10), stale: false })) }, meta: meta() }];
  if (/^\/usage$/.test(tail)) return [200, { data: { keyLabel: 'mock', cohort: 'mock', dailyQuota: 1000000, usedToday: 0, resetsAt: new Date(Date.now() + 864e5).toISOString() }, meta: meta() }];
  if ((m = tail.match(/^\/quotes\/([^/]+)(\/latest)?$/))) return [200, { data: quote(m[1].toUpperCase()), meta: meta() }];
  if (/^\/quotes$/.test(tail)) {
    const syms = (u.searchParams.get('symbols') || '').split(',').map((x) => x.trim().toUpperCase()).filter(Boolean);
    if (!syms.length) return [400, { error: { code: 'VALIDATION_ERROR', message: 'symbols is required', details: {} } }];
    return [200, { data: { quotes: syms.map((s) => ({ symbol: s, source: 'mock', stale: false, quote: quote(s) })) }, meta: meta() }];
  }
  if ((m = tail.match(/^\/candles\/([^/]+)$/))) { const s = m[1].toUpperCase();
    return [200, { data: { symbol: s, interval: u.searchParams.get('interval') || '1d', currency: currency(s), candles: candles(s, u.searchParams.get('from'), u.searchParams.get('to')) }, meta: meta() }]; }
  if ((m = tail.match(/^\/symbols\/([^/]+)$/))) { const s = m[1].toUpperCase();
    return [200, { data: { symbol: s, name: s + ' (mock)', type: type(s), exchange: exchange(s), currency: currency(s), active: true, coverage: { eodFrom: '2020-01-01', eodTo: new Date().toISOString().slice(0, 10) } }, meta: meta() }]; }
  if (/^\/symbols$/.test(tail)) return [200, { data: { symbols: Object.keys(BASE).map((s) => ({ symbol: s, name: s + ' (mock)', type: type(s), exchange: exchange(s), currency: currency(s), active: true })) }, meta: meta() }];
  return [404, { error: { code: 'NOT_FOUND', message: 'mock has no route for ' + path, details: {} } }];
}
const server = http.createServer((req, res) => {
  const [code, body] = route(req.url);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }); res.end(JSON.stringify(body));
});
// Java's HttpClient asks to upgrade plain HTTP to HTTP/2 (h2c). Node would close such a
// connection; answer it as an ordinary HTTP/1.1 request instead.
server.on('upgrade', (req, socket) => {
  const [code, body] = route(req.url); const text = JSON.stringify(body);
  socket.end('HTTP/1.1 ' + code + ' ' + (code === 200 ? 'OK' : 'Error') + '\r\nContent-Type: application/json\r\nContent-Length: ' + Buffer.byteLength(text) + '\r\nConnection: close\r\n\r\n' + text);
});
server.listen(PORT, () => console.log('fauxnance mock listening on ' + PORT + ' (market ' + STATE + ')'));
