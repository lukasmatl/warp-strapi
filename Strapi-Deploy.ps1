# group config
$rgName = "rg-strapi-dev"
$location = "westus"

# app config
$appPlanName = "asp-strapi-dev"
$webAppName = "webapp-strapicms-dev"
$runtime = "node|20-lts"
$port = '8080'

# storage config
$saName = "ststrapicmsdev"
$container = "strapi-uploads"

# db config
$serverName = "sql-cms-dev"
$startIpAddress = "0.0.0.0" # Start IP Address
$endIpAddress = "255.255.255.255"   # End IP Address
$ruleName = "AllowAllAzureIps"
$username = "strapiSqlAdmin"
$password = "ChangeMe123!"
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
$databaseSsl= 'true'
$databaseClient = 'postgres'
$databaseName = 'sqldb-cms-dev'

# Create Resource Group
New-AzResourceGroup -Name $rgName -Location $location

# Create Storage Account
$storageAccount = New-AzStorageAccount `
    -ResourceGroupName $rgName `
    -Name $saName `
    -Location $location `
    -SkuName "Standard_LRS" `
    -Kind "StorageV2" `
    -AccessTier "Hot" `
    -EnableHttpsTrafficOnly $true `
    -MinimumTlsVersion "TLS1_2" `
    -AllowBlobPublicAccess $true `
    -AllowSharedKeyAccess $true

# Retrieve Storage Account Key
$saKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $saName)[0].Value

# Create Storage Container
$context = $storageAccount.Context
New-AzStorageContainer -Name $container -Context $context -Permission Blob

# Create a PostgreSQL Flexible Server
$dbSku = @{
    name = 'Standard_B1ms'
    tier = 'Burstable'
} 
New-AzPostgreSqlFlexibleServer `
    -ResourceGroupName $rgName `
    -ServerName $serverName `
    -Location $location `
    -Sku $dbSku.name `
    -SkuTier $dbSku.tier `
    -AdministratorUserName $username `
    -AdministratorLoginPassword $securePassword `
    -Version 15

# Create a database in the server
New-AzPostgreSqlFlexibleServerDatabase `
    -ResourceGroupName $rgName `
    -ServerName $serverName `
    -DatabaseName $databaseName

# Create a firewall rule
Update-AzPostgreSqlFlexibleServerFirewallRule `
    -ResourceGroupName $rgName `
    -ServerName $serverName `
    -Name $ruleName `
    -StartIpAddress $startIpAddress `
    -EndIpAddress $endIpAddress


# Create App Service Plan
$aspSku = @{
    tier = 'Basic'
    numberofWorkers = 2
}   
New-AzAppServicePlan `
    -ResourceGroupName $rgName `
    -Name $appPlanName `
    -Location $location `
    -Tier $aspSku.tier `
    -NumberofWorkers $aspSku.numberofWorkers `
    -Linux

# # Web App creation
$app = New-AzWebApp -ResourceGroupName $rgName -Name $webAppName -AppServicePlan $appPlanName 
$app.SiteConfig.LinuxFxVersion = $runtime
Set-AzWebApp -WebApp $app

$currentAppSettings = @{}
$webApp = Get-AzWebApp -ResourceGroupName $rgName -Name $webAppName
foreach ($setting in $webApp.SiteConfig.AppSettings) {
    $currentAppSettings[$setting.Name] = $setting.Value
}

# Define new app settings most of the config was copied from the .env file
$newAppSettings = @{
    STORAGE_ACCOUNT = $saName
    STORAGE_ACCOUNT_KEY = $saKey
    STORAGE_ACCOUNT_CONTAINER = $container
    
    PORT = $port
    APP_KEYS = 'YYCRDkTDBsXaYFzFbsGirg==,er6+ZTOsvuG72HOmk+pBtQ==,SuzjYcWXvOAA7k4XJ+aQng==,AwngOXgDEKH0vVl5gjKO5w=='
    API_TOKEN_SALT = 'je5tVyoo283i54D8LANSdnCok1QjjR7gJOlzQljZi/A='
    ADMIN_JWT_SECRET = 'ELLC0nP27PeDqTyP6EPdSA=='
    TRANSFER_TOKEN_SALT = 'QhsdnDO6mcCiLU1c2rrn+A=='
    JWT_SECRET = 'E7P0h8cxH65cFteGoWUXjQ=='

    DATABASE_HOST = "$serverName.postgres.database.azure.com"
    DATABASE_USERNAME = $username
    DATABASE_PASSWORD = $password
    DATABASE_CLIENT = $databaseClient
    DATABASE_NAME = $databaseName
    DATABASE_SSL = $databaseSsl
}

# Merge current app settings with new values
foreach ($key in $newAppSettings.Keys) {
    $currentAppSettings[$key] = $newAppSettings[$key]
}

# Apply the updated settings
Set-AzWebApp `
    -ResourceGroupName $rgName `
    -Name $webAppName `
    -AppSettings $currentAppSettings