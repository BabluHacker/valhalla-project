# Valhalla Routing Engine - Deployment Notes

## Overview

This deployment uses the **official Valhalla routing engine** from [GIS-OPS Docker Valhalla](https://github.com/gis-ops/docker-valhalla).

## What is Valhalla?

Valhalla is an open-source routing engine and library for use with OpenStreetMap data. It provides:
- Turn-by-turn routing
- Isochrones (time/distance polygons)
- Map matching
- Optimized route planning
- Multiple travel modes (auto, bicycle, pedestrian)

## Architecture

### Components

1. **Valhalla Container**: Official `ghcr.io/gis-ops/docker-valhalla/valhalla:latest`
2. **Persistent Storage**: 50GB EBS volume for map tiles
3. **Init Container**: Downloads sample map data (Utrecht) on first run
4. **Service**: Exposes port 8002 (Valhalla's default)

### Resource Requirements

**Dev Environment:**
- CPU: 250m request, 1000m limit
- Memory: 512Mi request, 2Gi limit
- Storage: 50Gi PVC

**Production:**
- CPU: 500m request, 2000m limit
- Memory: 1Gi request, 4Gi limit
- Storage: 100Gi+ (depends on map coverage)

## Map Data

### Current Setup (Sample Data)

The init container downloads **Utrecht, Netherlands** sample data (~10MB):
- Small dataset for testing
- Quick download and setup
- Good for demonstrating functionality

### Using Custom Map Data

To use different regions:

1. **Download PBF files** from [Geofabrik](https://download.geofabrik.de/)
   ```bash
   # Example: Download Luxembourg
   wget https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf
   ```

2. **Build tiles** (can be done locally or in a job):
   ```bash
   docker run -v $PWD:/data ghcr.io/gis-ops/docker-valhalla/valhalla:latest \
     valhalla_build_config --mjolnir-tile-dir /data/valhalla_tiles \
     --mjolnir-tile-extract /data/valhalla_tiles.tar \
     --mjolnir-timezone /data/valhalla_tiles/timezones.sqlite \
     --mjolnir-admin /data/valhalla_tiles/admins.sqlite > valhalla.json
   
   docker run -v $PWD:/data ghcr.io/gis-ops/docker-valhalla/valhalla:latest \
     valhalla_build_tiles -c valhalla.json luxembourg-latest.osm.pbf
   ```

3. **Upload to S3** and download in init container:
   ```yaml
   initContainers:
   - name: download-tiles
     command:
     - sh
     - -c
     - |
       aws s3 cp s3://your-bucket/valhalla_tiles.tar /data/
       cd /data && tar xf valhalla_tiles.tar
   ```

## API Endpoints

### Health Check
```bash
curl http://<ALB_URL>/status
```

### Routing
```bash
curl http://<ALB_URL>/route \
  --data '{
    "locations": [
      {"lat": 52.0907, "lon": 5.1214},
      {"lat": 52.0938, "lon": 5.1182}
    ],
    "costing": "auto",
    "directions_options": {"units": "kilometers"}
  }' \
  -H "Content-Type: application/json"
```

### Isochrone
```bash
curl http://<ALB_URL>/isochrone \
  --data '{
    "locations": [{"lat": 52.0907, "lon": 5.1214}],
    "costing": "auto",
    "contours": [{"time": 10}, {"time": 20}]
  }' \
  -H "Content-Type: application/json"
```

### Map Matching
```bash
curl http://<ALB_URL>/trace_route \
  --data '{
    "shape": [
      {"lat": 52.0907, "lon": 5.1214},
      {"lat": 52.0938, "lon": 5.1182}
    ],
    "costing": "auto",
    "shape_match": "map_snap"
  }' \
  -H "Content-Type: application/json"
```

## Deployment Changes

### What Changed

1. **Removed custom Node.js app**: No longer building custom application
2. **Added PVC**: Persistent storage for map tiles
3. **Init container**: Downloads map data on first deployment
4. **Updated resources**: Higher CPU/memory for routing calculations
5. **Changed ports**: 8002 instead of 3000
6. **Health checks**: `/status` instead of `/health`

### Deployment Script Updates

The deployment script no longer needs to:
- Build Docker image (using official image)
- Push to ECR (pulling from GitHub Container Registry)

## Storage Considerations

### Production Map Data Sizes

| Region | Compressed | Tiles Size |
|--------|-----------|------------|
| Small city (Utrecht) | ~10 MB | ~50 MB |
| Country (Netherlands) | ~500 MB | ~2 GB |
| Europe | ~25 GB | ~100 GB |
| Planet | ~60 GB | ~300 GB |

### Storage Recommendations

- **Dev/Testing**: 50GB (current)
- **Regional**: 100-200GB
- **Continental**: 500GB+
- **Global**: 1TB+

## Performance Tuning

### Scaling Considerations

1. **Horizontal scaling**: Works well for concurrent requests
2. **CPU-intensive**: Route calculations need CPU
3. **Memory**: Tiles loaded into memory for performance
4. **Storage I/O**: SSD recommended (gp3 used)

### HPA Configuration

Current HPA targets:
- CPU: 70%
- Memory: 80%
- Min replicas: 2 (dev), 6 (prod)
- Max replicas: 10 (dev), 30 (prod)

## Monitoring

### Metrics to Watch

1. **Response time**: Should be < 500ms for most routes
2. **Error rate**: Failed route calculations
3. **Memory usage**: Tile data in memory
4. **Storage**: PVC usage
5. **Request rate**: Routes per second

### Prometheus Metrics

Valhalla exposes metrics on port 8002:
```bash
curl http://<pod-ip>:8002/metrics
```

## Troubleshooting

### Pods Not Ready

```bash
# Check pod logs
kubectl logs -n valhalla valhalla-api-xxx -c download-tiles
kubectl logs -n valhalla valhalla-api-xxx -c valhalla

# Check PVC
kubectl get pvc -n valhalla
kubectl describe pvc valhalla-data -n valhalla
```

### Map Data Issues

```bash
# Exec into pod
kubectl exec -it -n valhalla valhalla-api-xxx -- sh

# Check tiles
ls -lh /custom_files/
```

### Routing Errors

Common issues:
- Coordinates outside map coverage
- Invalid costing mode
- Malformed JSON request

## Cost Optimization

### Dev Environment

- Use small map datasets (Utrecht)
- 2 replicas minimum
- Lower resource limits
- 50GB storage

### Production

- Use regional data only (not planet)
- Cache frequently requested routes
- Use spot instances for non-critical loads
- Monitor and right-size resources

## References

- [Valhalla Documentation](https://valhalla.readthedocs.io/)
- [Docker Valhalla](https://github.com/gis-ops/docker-valhalla)
- [API Reference](https://valhalla.github.io/valhalla/api/)
- [Geofabrik Downloads](https://download.geofabrik.de/)
