const WS_URL = 'ws://localhost:8080'; // Change to your server URL
const tableBody = document.querySelector("#signal-body");
const activeSignalsEl = document.getElementById("active-signals");

let ws = null;
let reconnectInterval = null;
let cache = new Map();

// Format elapsed time
function formatElapsed(iso) {
  if (!iso) return "-";
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return diff + 's';
  const mins = Math.floor(diff / 60);
  if (mins < 60) return mins + 'm ' + (diff % 60) + 's';
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return hrs + 'h ' + (mins % 60) + 'm';
  const days = Math.floor(hrs / 24);
  return days + 'd ' + (hrs % 24) + 'h';
}

// Generate unique key for signal
function keyOf(s) {
  return `${s.symbol}|${s.timeframe}`;
}

// Compute trade type
function computeTradeType(sig) {
  if (sig.type && sig.type !== '-' && sig.type.trim() !== '') 
    return sig.type.toUpperCase();
  return sig.symbol.toLowerCase().includes("crash") ? "BUY" : "SELL";
}

// Generate row HTML
function rowHtml(sig) {
  const tradeType = computeTradeType(sig);
  const cls = tradeType === "BUY" ? "buy" : "sell";
  
  const h4Fmt = sig.H4?.toLowerCase().includes("up") 
    ? `<span class="trend-up">${sig.H4}</span>` 
    : sig.H4?.toLowerCase().includes("down") 
    ? `<span class="trend-down">${sig.H4}</span>` 
    : (sig.H4 ?? "-");
    
  const d1Fmt = sig.D1?.toLowerCase().includes("up") 
    ? `<span class="trend-up">${sig.D1}</span>` 
    : sig.D1?.toLowerCase().includes("down") 
    ? `<span class="trend-down">${sig.D1}</span>` 
    : (sig.D1 ?? "-");

  return `
    <tr class="${cls}" data-key="${keyOf(sig)}">
      <td>${sig.symbol}</td>
      <td>${tradeType}</td>
      <td>${sig.timeframe}</td>
      <td data-time="${sig.validSince}">${formatElapsed(sig.validSince)}</td>
      <td>${h4Fmt}</td>
      <td>${d1Fmt}</td>
    </tr>
  `;
}

// Update table with new signals
function updateTable(signals) {
  if (!Array.isArray(signals) || signals.length === 0) {
    tableBody.innerHTML = '<tr><td colspan="6" class="no-signal">No valid signals yet</td></tr>';
    activeSignalsEl.textContent = `0 Valid Signals: (H1: 0 | M30: 0)`;
    cache.clear();
    return;
  }

  // Sort alphabetically
  signals.sort((a, b) => a.symbol.localeCompare(b.symbol));

  const h1Count = signals.filter(s => s.timeframe === 'H1').length;
  const m30Count = signals.filter(s => s.timeframe === 'M30').length;
  activeSignalsEl.textContent = `${h1Count + m30Count} Valid Signals: (H1: ${h1Count} | M30: ${m30Count})`;

  const newKeys = new Set(signals.map(s => keyOf(s)));

  // Remove invalidated signals
  tableBody.querySelectorAll('tr[data-key]').forEach(r => {
    const k = r.getAttribute('data-key');
    if (!newKeys.has(k)) {
      r.remove();
      cache.delete(k);
    }
  });

  // Build rows
  const frag = document.createDocumentFragment();
  signals.forEach(sig => {
    const k = keyOf(sig);
    const sigJSON = JSON.stringify(sig);
    const cached = cache.get(k);

    if (cached && cached.json === sigJSON) {
      const existing = tableBody.querySelector(`tr[data-key="${k}"]`);
      if (existing) {
        frag.appendChild(existing);
        return;
      }
    }

    const tmp = document.createElement('tbody');
    tmp.innerHTML = rowHtml(sig);
    frag.appendChild(tmp.querySelector('tr'));
    cache.set(k, { json: sigJSON });
  });

  tableBody.innerHTML = '';
  tableBody.appendChild(frag);
}

// Show connection status
function updateConnectionStatus(connected) {
  const header = document.querySelector('.header');
  let statusEl = document.getElementById('connection-status');
  
  if (!statusEl) {
    statusEl = document.createElement('div');
    statusEl.id = 'connection-status';
    statusEl.style.cssText = 'margin-top: 10px; padding: 8px 16px; border-radius: 6px; font-size: 0.9rem; display: inline-block;';
    header.appendChild(statusEl);
  }

  if (connected) {
    statusEl.textContent = '🟢 Connected (Live)';
    statusEl.style.background = 'rgba(0, 255, 136, 0.2)';
    statusEl.style.color = '#00ff88';
  } else {
    statusEl.textContent = '🔴 Disconnected (Reconnecting...)';
    statusEl.style.background = 'rgba(255, 51, 102, 0.2)';
    statusEl.style.color = '#ff3366';
  }
}

// Connect to WebSocket server
function connect() {
  if (ws && (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN)) {
    return; // Already connected or connecting
  }

  console.log('🔌 Connecting to WebSocket server...');
  ws = new WebSocket(WS_URL);

  ws.onopen = () => {
    console.log('✅ WebSocket connected!');
    updateConnectionStatus(true);
    
    // Clear reconnect interval if exists
    if (reconnectInterval) {
      clearInterval(reconnectInterval);
      reconnectInterval = null;
    }
  };

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      
      if (data.type === 'signals_update') {
        console.log(`📊 Received ${data.count} signals`);
        updateTable(data.indicators || []);
      }
    } catch (err) {
      console.error('Error parsing WebSocket message:', err);
    }
  };

  ws.onerror = (error) => {
    console.error('❌ WebSocket error:', error);
  };

  ws.onclose = () => {
    console.log('🔌 WebSocket disconnected');
    updateConnectionStatus(false);
    
    // Auto-reconnect every 3 seconds
    if (!reconnectInterval) {
      reconnectInterval = setInterval(() => {
        console.log('🔄 Attempting to reconnect...');
        connect();
      }, 3000);
    }
  };
}

// Update elapsed time every second
setInterval(() => {
  document.querySelectorAll('td[data-time]').forEach(td => {
    td.textContent = formatElapsed(td.dataset.time);
  });
}, 1000);

// Initialize connection
connect();

// Expose for debugging
window.wsDebug = {
  reconnect: connect,
  getActiveSignals: () => Array.from(cache.keys()),
  getWebSocket: () => ws
};