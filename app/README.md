# Valhalla API

A production-ready Node.js REST API for the Valhalla platform.

## Features

- Health check and readiness probes
- Structured logging with Winston
- Request/response logging
- Error handling middleware
- Graceful shutdown
- Prometheus metrics endpoint

## Endpoints

- `GET /health` - Health check probe
- `GET /ready` - Readiness probe
- `GET /api/v1/status` - Application status and version
- `GET /api/v1/data` - Sample data endpoint
- `GET /metrics` - Prometheus metrics

## Local Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Run tests
npm test

# Run linting
npm run lint

# Build for production
npm run build

# Start production server
npm start
```

## Docker

```bash
# Build image
docker build -t valhalla-api:latest .

# Run container
docker run -p 3000:3000 \
  -e NODE_ENV=production \
  -e PORT=3000 \
  valhalla-api:latest
```

## Environment Variables

- `NODE_ENV` - Environment (development/production)
- `PORT` - Server port (default: 3000)
- `LOG_LEVEL` - Logging level (default: info)

## Testing

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run in watch mode
npm run test:watch
```
