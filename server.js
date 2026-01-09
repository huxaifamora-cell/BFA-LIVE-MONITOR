const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 8080;

// In-memory storage for active signals
const activeSignals = new Map();

// Connection tracking for EA instances
const eaConnections = new Map(); // eaId -> { lastHeartbeat, activeSignals: Set }

// Configuration
const HEARTBEAT_TIMEOUT = 90000; // 90 seconds (3x heartbeat interval)
const CLEANUP_INTERVAL = 30000; // Check every 30 seconds

// Create HTTP server
const server = http.createServer((req, res) => {
    // Handle POST requests from MT5 EA
    if (req.method === 'POST' && req.url === '/') {
        let body = '';
        
        req.on('data', chunk => {
            body += chunk.toString();
        });
        
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                console.log('📥 Received from EA:', data.type, data.symbol || '', data.timeframe || '');
                
                // Extract EA identifier (use IP or create unique ID)
                const eaId = req.socket.remoteAddress || 'default';
                
                // Handle heartbeat from EA
                if (data.type === 'heartbeat') {
                    const now = Date.now();
                    
                    if (!eaConnections.has(eaId)) {
                        eaConnections.set(eaId, {
                            lastHeartbeat: now,
                            activeSignals: new Set(),
                            connectedAt: new Date().toISOString()
                        });
                        console.log(`✅ NEW EA CONNECTED: ${eaId}`);
                    } else {
                        eaConnections.get(eaId).lastHeartbeat = now;
                        console.log(`💓 Heartbeat from ${eaId} (${data.active_signals || 0} signals)`);
                    }
                    
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        status: 'alive', 
                        signals: activeSignals.size,
                        timestamp: now
                    }));
                    return;
                }
                
                // Handle signal from EA
                if (data.type === 'signal') {
                    const key = `${data.symbol}|${data.timeframe}`;
                    const now = Date.now();
                    
                    // Ensure EA connection is tracked
                    if (!eaConnections.has(eaId)) {
                        eaConnections.set(eaId, {
                            lastHeartbeat: now,
                            activeSignals: new Set(),
                            connectedAt: new Date().toISOString()
                        });
                    }
                    
                    // Update heartbeat
                    eaConnections.get(eaId).lastHeartbeat = now;
                    eaConnections.get(eaId).activeSignals.add(key);
                    
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
                            priority: data.priority || 1,
                            validSince: new Date().toISOString(),
                            lastUpdate: now,
                            eaId: eaId
                        });
                        console.log(`🚨 NEW SIGNAL: ${data.symbol} ${data.timeframe} ${data.trade_type}`);
                    } else {
                        // Update existing signal (keep original validSince)
                        existing.type = data.trade_type;
                        existing.h4_trend = data.h4_trend || '-';
                        existing.d1_trend = data.d1_trend || '-';
                        existing.min_lot = data.min_lot || 0;
                        existing.min_margin = data.min_margin || 0;
                        existing.priority = data.priority || 1;
                        existing.lastUpdate = now;
                        existing.eaId = eaId;
                        console.log(`🔄 UPDATED: ${data.symbol} ${data.timeframe}`);
                    }

                    // Broadcast immediately to all WebSocket clients
                    broadcastCurrentSignals();
                    
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, message: 'Signal received' }));
                    return;
                }

                // Handle signal removal from EA
                if (data.type === 'remove_signal') {
                    const key = `${data.symbol}|${data.timeframe}`;
                    
                    // Update EA connection tracking
                    if (eaConnections.has(eaId)) {
                        eaConnections.get(eaId).activeSignals.delete(key);
                        eaConnections.get(eaId).lastHeartbeat = Date.now();
                    }
                    
                    if (activeSignals.delete(key)) {
                        console.log(`❌ REMOVED: ${data.symbol} ${data.timeframe}`);
                        broadcastCurrentSignals();
                    }
                    
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, message: 'Signal removed' }));
                    return;
                }

                // Unknown request type
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Unknown request type' }));
                
            } catch (err) {
                console.error('❌ Error parsing JSON:', err);
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Invalid JSON' }));
            }
        });
        
        return;
    }
    
    // Serve static files for GET requests
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

// Broadcast current active signals
function broadcastCurrentSignals() {
    const signals = Array.from(activeSignals.values())
        .map(s => ({
            symbol: s.symbol,
            timeframe: s.timeframe,
            type: s.type,
            H4: s.h4_trend,
            D1: s.d1_trend,
            validSince: s.validSince,
            min_lot: s.min_lot,
            min_margin: s.min_margin,
            priority: s.priority || 1
        }))
        .sort((a, b) => {
            // Sort by priority (higher first), then by validSince (older first)
            if (b.priority !== a.priority) return b.priority - a.priority;
            return new Date(a.validSince) - new Date(b.validSince);
        });

    broadcast({
        type: 'signals_update',
        indicators: signals,
        count: signals.length,
        timestamp: new Date().toISOString()
    });
}

// Cleanup inactive EA connections and their signals
function cleanupInactiveConnections() {
    const now = Date.now();
    let removedSignals = 0;
    let removedConnections = 0;
    
    eaConnections.forEach((connection, eaId) => {
        const timeSinceHeartbeat = now - connection.lastHeartbeat;
        
        if (timeSinceHeartbeat > HEARTBEAT_TIMEOUT) {
            console.log(`⚠️ EA ${eaId} timed out (${Math.round(timeSinceHeartbeat/1000)}s since last heartbeat)`);
            
            // Remove all signals from this EA
            connection.activeSignals.forEach(signalKey => {
                if (activeSignals.has(signalKey)) {
                    const signal = activeSignals.get(signalKey);
                    if (signal.eaId === eaId) {
                        activeSignals.delete(signalKey);
                        removedSignals++;
                        console.log(`  ❌ Auto-removed: ${signalKey}`);
                    }
                }
            });
            
            // Remove EA connection
            eaConnections.delete(eaId);
            removedConnections++;
        }
    });
    
    if (removedSignals > 0 || removedConnections > 0) {
        console.log(`🧹 Cleanup: Removed ${removedSignals} signals from ${removedConnections} inactive EAs`);
        broadcastCurrentSignals();
    }
}

// Start periodic cleanup
setInterval(cleanupInactiveConnections, CLEANUP_INTERVAL);

// Handle WebSocket connections
wss.on('connection', (ws, req) => {
    const clientIP = req.socket.remoteAddress;
    console.log(`✅ Browser client connected: ${clientIP}`);

    // Send current signals immediately to new client
    ws.send(JSON.stringify({
        type: 'signals_update',
        indicators: Array.from(activeSignals.values())
            .map(s => ({
                symbol: s.symbol,
                timeframe: s.timeframe,
                type: s.type,
                H4: s.h4_trend,
                D1: s.d1_trend,
                validSince: s.validSince,
                min_lot: s.min_lot,
                min_margin: s.min_margin,
                priority: s.priority || 1
            }))
            .sort((a, b) => {
                if (b.priority !== a.priority) return b.priority - a.priority;
                return new Date(a.validSince) - new Date(b.validSince);
            }),
        count: activeSignals.size,
        timestamp: new Date().toISOString()
    }));

    // Send connection stats
    ws.send(JSON.stringify({
        type: 'stats',
        activeEAs: eaConnections.size,
        activeSignals: activeSignals.size,
        timestamp: new Date().toISOString()
    }));

    // Handle messages from WebSocket clients
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            console.log('📨 WebSocket message from browser:', data);
            
            if (data.type === 'get_signals') {
                ws.send(JSON.stringify({
                    type: 'signals_update',
                    indicators: Array.from(activeSignals.values())
                        .map(s => ({
                            symbol: s.symbol,
                            timeframe: s.timeframe,
                            type: s.type,
                            H4: s.h4_trend,
                            D1: s.d1_trend,
                            validSince: s.validSince,
                            min_lot: s.min_lot,
                            min_margin: s.min_margin,
                            priority: s.priority || 1
                        }))
                        .sort((a, b) => {
                            if (b.priority !== a.priority) return b.priority - a.priority;
                            return new Date(a.validSince) - new Date(b.validSince);
                        }),
                    count: activeSignals.size,
                    timestamp: new Date().toISOString()
                }));
            }
            
            if (data.type === 'get_stats') {
                ws.send(JSON.stringify({
                    type: 'stats',
                    activeEAs: eaConnections.size,
                    activeSignals: activeSignals.size,
                    eaDetails: Array.from(eaConnections.entries()).map(([id, conn]) => ({
                        id: id,
                        connectedAt: conn.connectedAt,
                        lastHeartbeat: new Date(conn.lastHeartbeat).toISOString(),
                        signalCount: conn.activeSignals.size
                    })),
                    timestamp: new Date().toISOString()
                }));
            }
        } catch (err) {
            console.error('Error parsing WebSocket message:', err);
        }
    });

    ws.on('close', () => {
        console.log(`❌ Browser client disconnected: ${clientIP}`);
    });

    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
    });
});

// Start server
server.listen(PORT, '0.0.0.0', () => {
    console.log(`
╔════════════════════════════════════════════╗
║   🚀 BFA LIVE MONITOR SERVER v2.0          ║
╚════════════════════════════════════════════╝

📡 WebSocket Server: ws://localhost:${PORT}
🌐 HTTP Server: http://localhost:${PORT}
💓 Heartbeat Timeout: ${HEARTBEAT_TIMEOUT/1000}s
🧹 Cleanup Interval: ${CLEANUP_INTERVAL/1000}s
💾 Storage: In-Memory (No Database)

✅ Features:
   • Heartbeat monitoring
   • Automatic cleanup of stale signals
   • Multi-EA support
   • Connection tracking

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

// Log status every 5 minutes
setInterval(() => {
    console.log(`📊 Status: ${eaConnections.size} EAs connected, ${activeSignals.size} active signals`);
}, 300000);
