# Powershell script for creating logins and databases on Availability group servers.

## Usage
1. Configure database.json 
2. run create.ps1 script
3. Distribute/vault credentials (check output in **database name.txt** file.)
3. Profit 

**Script will connect to SQL as your currently logged in user, make sure you have sysadmin on the SQL Cluster before running script!**

## Credentials
Credentials are written to a text file with the name using **DatabaseName** from database.json.

## User config
**Configure settings in database.json**

Example:
    {
      "DatabaseName" : "my_project_db",
      "EnvironmentNumber": 1,
      "Environments" : ["test"]
   }

**EnvironmentNumber**

EnvironmentNumber can be either: 1, 2, 3 or 4
Environment number is the SQL instance/cluster number.
Environment number 5 is Azure.
Only Azure Managed Instance is supported/tested at the moment.

**Environments**

Available environments are: test, qa, stage and prod
Configured as an array, example: ["test","qa","prod"]

## System config
System parameters are set in config.json.
There should be no need to edit this unless new servers are added.

## Known issues
Connecting to Azure SQL sporadically fails.
I belive the issue is due to that the SQL Server modules are loaded before dbatools is loaded.
Solution may be to unload all depended modules when starting the script.
Emailing does not work.

## Dependencies
The script requires the dbatools package when creating databases in Azure.
https://dbatools.io
Non azure operations require the sqlserver powershell module.
https://docs.microsoft.com/en-us/sql/powershell/sql-server-powershell?view=sql-server-ver15