# Azure App Service Deployment (Single FastAPI App)

## Prereqs
- Azure CLI installed and logged in: `az login`
- App Service created (Linux, Python 3.12)
- Resource group and app name available

## Deploy
```bash
export AZURE_RESOURCE_GROUP="your-rg"
export AZURE_APP_NAME="your-app-name"

bash deploy_securewave_single_app.sh
```

## App URL
After deploy, your app is live at:
```
https://securewave-web.azurewebsites.net
```

## Startup command
The script sets the startup command to:
```bash
bash /home/site/wwwroot/startup.sh
```

## Logs
```bash
az webapp log tail --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_APP_NAME"
```

## Notes
- Demo mode uses SQLite if `DATABASE_URL` points to sqlite:///.
- Set `DEMO_MODE=true` and `DEMO_OK=true` for demo UI/Docs.
