# Profit Monitor Dashboard

Real-time trading account monitoring system for MetaTrader 4 and MetaTrader 5.

## Features

- **Real-time Monitoring**: Receive account data every 5 minutes from MT4/MT5 EAs
- **Multi-Account Support**: Monitor multiple trading accounts from different brokers
- **Live Dashboard**: Beautiful web interface with Tailwind CSS
- **Profit/Loss Tracking**: Calculate P&L based on configurable initial capital
- **In-Memory Storage**: Fast data access without database dependency
- **Docker Ready**: Easy deployment with Docker and Docker Compose

## Quick Start

### 1. Run the Web Application

#### Development Mode
```bash
# Install dependencies
yarn install

# Start development server
yarn dev

# Open browser to http://localhost:5173
```

#### Production Mode with Docker
```bash
# Build and run with Docker Compose
docker-compose up -d

# Access at http://localhost:3000
```

### 2. Setup MetaTrader EAs

#### For MT4:
1. Copy `ProfitMonitor-MT4.mq4` to your MT4 `MQL4/Experts/` folder
2. Compile the EA in MetaEditor
3. Add your server URL to allowed URLs:
   - Tools → Options → Expert Advisors
   - Check "Allow WebRequest for listed URL"
   - Add: `http://your-server:3000/api/webhook`

#### For MT5:
1. Copy `ProfitMonitor-MT5.mq5` to your MT5 `MQL5/Experts/` folder
2. Compile the EA in MetaEditor
3. Add your server URL to allowed URLs:
   - Tools → Options → Expert Advisors
   - Check "Allow WebRequest for listed URL"
   - Add: `http://your-server:3000/api/webhook`

#### EA Parameters:
- **API_URL**: Your server webhook endpoint (default: `http://localhost:3000/api/webhook`)
- **SendInterval**: Data send interval in seconds (default: 300 = 5 minutes)
- **EnableLogging**: Enable console logging (default: true)

### 3. Attach EAs to Charts

1. Drag the EA to any chart in MT4/MT5
2. Configure the API_URL parameter to point to your server
3. Enable "Allow live trading" and "Allow DLL imports"
4. Click OK to start monitoring

## API Endpoints

### Webhook (Receive Data from EAs)
```
POST /api/webhook
Content-Type: application/json

{
  "account_number": "12345678",
  "account_name": "Demo Account",
  "broker_name": "XM Global",
  "balance": 65000.50,
  "equity": 64800.25,
  "timestamp": "2024-01-15T10:30:00+07:00"
}
```

### Get Dashboard Data
```
GET /api/data

Response:
{
  "stats": {
    "total_balance": 130000.75,
    "profit_loss": 70000.75,
    "initial_capital": 60000,
    "account_count": 2
  },
  "summaries": [...],
  "allData": [...]
}
```

### Settings Management
```
GET /api/settings
POST /api/settings
{
  "initial_capital": 60000
}
```

## Dashboard Features

### Summary Cards
- **Total Balance**: Sum of all account balances
- **Profit/Loss**: Total balance minus initial capital
- **Initial Capital**: Configurable starting amount
- **Active Accounts**: Number of monitored accounts

### Account Summary by Broker
- Groups accounts by broker name
- Shows latest balance and equity for each account
- Displays last update timestamp (GMT+7)

### Raw Data Table
- Shows last 100 data records
- Real-time updates every 30 seconds
- Sortable by timestamp (newest first)

### Settings Panel
- Configure initial capital amount
- Automatically recalculates profit/loss

## Deployment Options

### Option 1: Simple Docker
```bash
# Build image
docker build -t profit-monitor .

# Run container
docker run -p 3000:3000 profit-monitor
```

### Option 2: Docker Compose (Recommended)
```bash
# Development
docker-compose up -d

# Production with Nginx
docker-compose --profile production up -d
```

### Option 3: Cloud Deployment

#### Vercel
```bash
yarn build
npx vercel deploy
```

##### Switching Vercel Account/Team

CLI (from the `profit-monitor` directory):

```bash
# Remove stale local project link
rm -rf .vercel

# Switch to desired team/account (optional)
npx vercel switch

# Re-authenticate if needed
npx vercel logout && npx vercel login

# Link to the new scope/team
npx vercel link

# Deploy
npx vercel deploy --prod
```

Git Integration (Dashboard):
- Set Project → Settings → Git → Root Directory to `profit-monitor`.
- Framework Preset: SvelteKit.
- (Optional) Install Command: `yarn install`; Build Command: `yarn build`.

Notes:
- In a monorepo, you can run from repo root with: `vercel --cwd profit-monitor`.
- If you see "Could not retrieve Project Settings", remove `.vercel` and run `vercel link` again.

#### Railway/Render
1. Connect your GitHub repository
2. Set build command: `yarn build`
3. Set start command: `node build`

## Configuration

### Environment Variables
```bash
NODE_ENV=production
PORT=3000
HOST=0.0.0.0
```

### Nginx Configuration (Production)
The included `nginx.conf` provides:
- Reverse proxy to SvelteKit app
- SSL termination (uncomment SSL section)
- Gzip compression
- Security headers

### SSL Setup (Production)
1. Obtain SSL certificates
2. Place them in `./ssl/` directory
3. Uncomment SSL server block in `nginx.conf`
4. Update server_name with your domain

## Troubleshooting

### EA Connection Issues
1. **Check URL whitelist**: Ensure your server URL is in MT4/MT5 allowed URLs
2. **Firewall**: Make sure port 3000 is accessible
3. **HTTPS**: For production, use HTTPS endpoints
4. **Logs**: Check EA logs in MT4/MT5 Expert tab

### Dashboard Not Updating
1. **Check API**: Visit `/api/data` to see if data is received
2. **Browser Console**: Check for JavaScript errors
3. **Network**: Ensure no proxy/firewall blocking requests

### Docker Issues
```bash
# Check logs
docker-compose logs profit-monitor

# Rebuild image
docker-compose build --no-cache

# Reset everything
docker-compose down -v
docker-compose up -d
```

## Development

### Project Structure
```
profit-monitor/
├── src/
│   ├── lib/
│   │   ├── types.ts          # TypeScript interfaces
│   │   └── storage.ts        # In-memory data storage
│   └── routes/
│       ├── +page.svelte      # Dashboard UI
│       └── api/              # API endpoints
├── ProfitMonitor-MT4.mq4     # MT4 Expert Advisor
├── ProfitMonitor-MT5.mq5     # MT5 Expert Advisor
├── Dockerfile                # Container configuration
└── docker-compose.yml       # Multi-container setup
```

### Adding Features
1. **New API endpoints**: Add to `src/routes/api/`
2. **UI components**: Create in `src/lib/components/`
3. **Data types**: Update `src/lib/types.ts`
4. **Storage logic**: Modify `src/lib/storage.ts`

### Testing
```bash
# Run development server
yarn dev

# Test API endpoints
curl -X POST http://localhost:5173/api/webhook \
  -H "Content-Type: application/json" \
  -d '{"account_number":"123","account_name":"Test","broker_name":"Test Broker","balance":1000,"equity":1000}'
```

## License

Copyright 2024, Profit Monitor. All rights reserved.