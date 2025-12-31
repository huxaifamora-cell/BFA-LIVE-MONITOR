const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 8080; // Render provides PORT automatically
const SIGNAL_TIMEOUT_MS = 120000; // 2 minutes (can be adjusted)

// In-memory storage for active signals (no database!)
const activeSignals = new Map();

// Create HTTP server for serving files
const server = http.createServer((req, res) => {
    let filePath = '.' + req.url;
    if (filePath === './') filePath = './index.html';

    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = {
        '.html': 'text/html',
        '.js': 'text/javascript',
        '.css': 'text/css',
        '.json': 'application/json',
    };

    const contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) {
            if (error.code == 'ENOENT') {
                res.writeHead(404);
                res.end('404 Not Found');
            } else {
                res.writeHead(500);
                res.end('Server Error: ' + error.code);
            }
        } else {
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(content, 'utf-8');
        }
    });
});

// Create WebSocket server
const wss = new WebSocket.Server({ server });

// Broadcast to all connected clients
function broadcast(data) {
    const message = JSON.stringify(data);
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(message);
        }
    });
}

// Clean expired signals and notify clients
function cleanExpiredSignals() {
    const now = Date.now();
    let hasChanges = false;

    for (const [key, signal] of activeSignals.entries()) {
        if (now - signal.lastUpdate > SIGNAL_TIMEOUT_MS) {
            activeSignals.delete(key);
            hasChanges = true;
            console.log(`🗑️  Removed expired signal: ${key}`);
        }
    }

    if (hasChanges) {
        broadcastCurrentSignals();
    }
}

// Broadcast current active signals
function broadcastCurrentSignals() {
    const signals = Array.from(activeSignals.values()).map(s => ({
        symbol: s.symbol,
        timeframe: s.timeframe,
        type: s.type,
        H4: s.h4_trend,
        D1: s.d1_trend,
        validSince: s.validSince,
        min_lot: s.min_lot,
        min_margin: s.min_margin
    }));

    broadcast({
        type: 'signals_update',
        indicators: signals,
        count: signals.length,
        timestamp: new Date().toISOString()
    });
}

// Handle WebSocket connections
wss.on('connection', (ws, req) => {
    const clientIP = req.socket.remoteAddress;
    console.log(`✅ Client connected: ${clientIP}`);

    // Send current signals immediately to new client
    ws.send(JSON.stringify({
        type: 'signals_update',
        indicators: Array.from(activeSignals.values()).map(s => ({
            symbol: s.symbol,
            timeframe: s.timeframe,
            type: s.type,
            H4: s.h4_trend,
            D1: s.d1_trend,
            validSince: s.validSince,
            min_lot: s.min_lot,
            min_margin: s.min_margin
        })),
        count: activeSignals.size,
        timestamp: new Date().toISOString()
    }));

    // Handle messages from clients
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);

            // Handle signal from EA
            if (data.type === 'signal') {
                const key = `${data.symbol}|${data.timeframe}`;
                const now = Date.now();
                
                const existing = activeSignals.get(key);
                
                if (!existing) {
                    // New signal
                    activeSignals.set(key, {
                        symbol: data.symbol,
                        timeframe: data.timeframe,
                        type: data.trade_type,
                        h4_trend: data.h4_trend || '-',
                        d1_trend: data.d1_trend || '-',
                        min_lot: data.min_lot || 0,
                        min_margin: data.min_margin || 0,
                        validSince: new Date().toISOString(),
                        lastUpdate: now
                    });
                    console.log(`🚨 NEW SIGNAL: ${data.symbol} ${data.timeframe} ${data.trade_type}`);
                } else {
                    // Update existing signal
                    existing.type = data.trade_type;
                    existing.h4_trend = data.h4_trend || '-';
                    existing.d1_trend = data.d1_trend || '-';
                    existing.min_lot = data.min_lot || 0;
                    existing.min_margin = data.min_margin || 0;
                    existing.lastUpdate = now;
                    console.log(`🔄 UPDATED: ${data.symbol} ${data.timeframe}`);
                }

                // Broadcast immediately to all clients
                broadcastCurrentSignals();
            }

            // Handle signal removal from EA (when conditions no longer met)
            if (data.type === 'remove_signal') {
                const key = `${data.symbol}|${data.timeframe}`;
                if (activeSignals.delete(key)) {
                    console.log(`❌ REMOVED: ${data.symbol} ${data.timeframe}`);
                    broadcastCurrentSignals();
                }
            }

        } catch (err) {
            console.error('Error parsing message:', err);
        }
    });

    ws.on('close', () => {
        console.log(`❌ Client disconnected: ${clientIP}`);
    });

    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
    });
});

// Clean expired signals every 5 seconds
setInterval(cleanExpiredSignals, 5000);

// Start server (bind to 0.0.0.0 for Render)
server.listen(PORT, '0.0.0.0', () => {
    console.log(`
╔════════════════════════════════════════════╗
║   🚀 BFA LIVE MONITOR SERVER RUNNING       ║
╚════════════════════════════════════════════╝

📡 WebSocket Server: ws://localhost:${PORT}
🌐 HTTP Server: http://localhost:${PORT}
⏱️  Signal Timeout: ${SIGNAL_TIMEOUT_MS / 1000} seconds
💾 Storage: In-Memory (No Database)
🔄 Auto-cleanup: Every 5 seconds

Waiting for connections...
    `);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down server...');
    wss.clients.forEach(client => {
        client.close();
    });
    server.close(() => {
        console.log('✅ Server closed');
        process.exit(0);
    });
});
