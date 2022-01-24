$AzureToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
$AzureServer = "app-database-test-sqlmi.randomguid.database.windows.net"
$AzureSql = Connect-DbaInstance -SqlInstance $AzureServer -AccessToken $azureToken #-Database master
$DBName = "cheese"
New-DbaDatabase -SqlInstance $AzureSql -Name $DbName -Owner $LoginName