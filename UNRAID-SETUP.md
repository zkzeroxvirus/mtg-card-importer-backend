# Unraid Setup Guide

## Quick Start

### 1. Create the App Directory

SSH into your Unraid server:

```bash
mkdir -p /mnt/user/appdata/mtg-card-importer
cd /mnt/user/appdata/mtg-card-importer
```

### 2. Copy Files

Transfer these files to `/mnt/user/appdata/mtg-card-importer/`:
- `docker-compose.yml`
- `Dockerfile`
- `package.json`
- `server.js`
- `lib/` (entire folder)
- `.env.example` → rename to `.env`

### 3. Configure Environment

Edit `.env`:
```bash
nano /mnt/user/appdata/mtg-card-importer/.env
```

Set:
```
USE_BULK_DATA=true
BULK_DATA_PATH=/app/data
PORT=3000
```

### 4. Build and Run

```bash
cd /mnt/user/appdata/mtg-card-importer
docker-compose up -d
```

### 5. Check Status

```bash
# View logs
docker logs mtg-card-importer

# Check health
curl http://localhost:3000
```

You should see:
```json
{
  "status": "ok",
  "bulkData": {
    "enabled": true,
    "loaded": true,
    "cardCount": 30000+
  }
}
```

## Storage Requirements

- **Docker Image:** ~150 MB
- **Bulk Data (compressed download):** ~161 MB
- **Bulk Data (in memory):** ~500 MB RAM
- **Bulk Data (on disk):** ~400 MB

**Total Requirements:**
- Disk: ~700 MB
- RAM: ~600 MB

## Network Access

### Local Network (LAN)

Your backend will be accessible at:
```
http://YOUR-UNRAID-IP:3000
```

Update your TTS Lua scripts:
```lua
backendURL='http://192.168.1.100:3000'  -- Change to your Unraid IP
```

### External Access (Internet)

#### Option A: Cloudflare Tunnel (Recommended)

Add to `docker-compose.yml`:

```yaml
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: mtg-cloudflare-tunnel
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=YOUR_TOKEN_HERE
    restart: unless-stopped
    networks:
      - mtg-network
```

Setup:
1. Go to https://dash.cloudflare.com
2. Zero Trust → Access → Tunnels → Create a tunnel
3. Configure public hostname pointing to `http://mtg-backend:3000`
4. Copy the token
5. Restart containers

Your public URL: `https://mtg-cards.your-domain.workers.dev`

#### Option B: Nginx Proxy Manager

If you already have NPM running:
1. Add proxy host
2. Point to `http://YOUR-UNRAID-IP:3000`
3. Enable SSL with Let's Encrypt

## Maintenance

### View Logs
```bash
docker logs -f mtg-card-importer
```

### Update Bulk Data Manually
```bash
curl -X POST http://localhost:3000/bulk/reload
```

### Check Bulk Data Stats
```bash
curl http://localhost:3000/bulk/stats
```

### Restart Container
```bash
docker-compose restart
```

### Update Application
```bash
cd /mnt/user/appdata/mtg-card-importer
git pull  # If using git
docker-compose down
docker-compose build
docker-compose up -d
```

## Troubleshooting

### Bulk Data Not Loading

Check logs:
```bash
docker logs mtg-card-importer | grep BulkData
```

Common issues:
- Not enough RAM (need 600MB free)
- Download failed (check internet)
- Disk full (need 700MB free)

### Container Won't Start

```bash
# Check if port 3000 is in use
netstat -tulpn | grep 3000

# View container errors
docker logs mtg-card-importer
```

### Slow Performance

- Ensure bulk data is loaded: `curl http://localhost:3000/bulk/stats`
- Check RAM usage: `free -h`
- Check if using API fallback (slower): Check logs for "using API"

## Performance

### With Bulk Data (Unraid):
- Random card query: **< 1ms**
- 100 cards: **< 100ms**
- No rate limiting
- Works offline

### API Mode (Render):
- Random card query: **50-100ms**
- 100 cards: **5-10 seconds**
- Rate limited (20 req/s)
- Requires internet

## Auto-Updates

Bulk data automatically updates every 24 hours. No manual intervention needed!

## Backup

The bulk data is downloaded automatically. To backup just in case:

```bash
cp /mnt/user/appdata/mtg-card-importer/data/oracle-cards.json /mnt/user/backups/
```

## Uninstall

```bash
cd /mnt/user/appdata/mtg-card-importer
docker-compose down
cd ..
rm -rf mtg-card-importer
```
