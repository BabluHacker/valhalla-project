const request = require('supertest');
const app = require('../src/server');

describe('Health Check Endpoints', () => {
    test('GET /health should return 200', async () => {
        const response = await request(app).get('/health');
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('status', 'healthy');
        expect(response.body).toHaveProperty('timestamp');
        expect(response.body).toHaveProperty('uptime');
    });

    test('GET /ready should return 200', async () => {
        const response = await request(app).get('/ready');
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('status', 'ready');
    });
});

describe('API Endpoints', () => {
    test('GET /api/v1/status should return application status', async () => {
        const response = await request(app).get('/api/v1/status');
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('application', 'Valhalla API');
        expect(response.body).toHaveProperty('version');
        expect(response.body).toHaveProperty('memory');
    });

    test('GET /api/v1/data should return data array', async () => {
        const response = await request(app).get('/api/v1/data');
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('count');
        expect(response.body).toHaveProperty('data');
        expect(Array.isArray(response.body.data)).toBe(true);
    });

    test('GET /api/v1/data?type=Platform should filter by type', async () => {
        const response = await request(app).get('/api/v1/data?type=Platform');
        expect(response.status).toBe(200);
        expect(response.body.data.every(item => item.type === 'Platform')).toBe(true);
    });

    test('GET /api/v1/data/1 should return specific item', async () => {
        const response = await request(app).get('/api/v1/data/1');
        expect(response.status).toBe(200);
        expect(response.body.data).toHaveProperty('id', 1);
    });

    test('GET /api/v1/data/999 should return 404', async () => {
        const response = await request(app).get('/api/v1/data/999');
        expect(response.status).toBe(404);
        expect(response.body).toHaveProperty('error', 'Not Found');
    });
});

describe('Metrics Endpoint', () => {
    test('GET /metrics should return Prometheus metrics', async () => {
        const response = await request(app).get('/metrics');
        expect(response.status).toBe(200);
        expect(response.text).toContain('# HELP');
        expect(response.text).toContain('# TYPE');
    });
});

describe('Error Handling', () => {
    test('GET /nonexistent should return 404', async () => {
        const response = await request(app).get('/nonexistent');
        expect(response.status).toBe(404);
        expect(response.body).toHaveProperty('error', 'Not Found');
    });
});
