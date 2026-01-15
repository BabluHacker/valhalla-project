const express = require('express');
const router = express.Router();

// Sample in-memory data
const sampleData = [
    { id: 1, name: 'Valhalla', type: 'Platform', status: 'active' },
    { id: 2, name: 'Odin', type: 'Service', status: 'active' },
    { id: 3, name: 'Thor', type: 'Service', status: 'active' },
    { id: 4, name: 'Loki', type: 'Service', status: 'maintenance' }
];

// GET /api/v1/status - Application status
router.get('/status', (req, res) => {
    res.json({
        application: 'Valhalla API',
        version: '1.0.0',
        environment: process.env.NODE_ENV || 'development',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        memory: {
            used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
            total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
            unit: 'MB'
        }
    });
});

// GET /api/v1/data - Sample data endpoint
router.get('/data', (req, res) => {
    const { type, status } = req.query;

    let filteredData = sampleData;

    if (type) {
        filteredData = filteredData.filter(item =>
            item.type.toLowerCase() === type.toLowerCase()
        );
    }

    if (status) {
        filteredData = filteredData.filter(item =>
            item.status.toLowerCase() === status.toLowerCase()
        );
    }

    res.json({
        count: filteredData.length,
        data: filteredData,
        timestamp: new Date().toISOString()
    });
});

// GET /api/v1/data/:id - Get specific item
router.get('/data/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const item = sampleData.find(d => d.id === id);

    if (item) {
        res.json({
            data: item,
            timestamp: new Date().toISOString()
        });
    } else {
        res.status(404).json({
            error: 'Not Found',
            message: `Item with id ${id} not found`,
            timestamp: new Date().toISOString()
        });
    }
});

module.exports = router;
