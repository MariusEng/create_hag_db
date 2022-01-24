Clear-Host

$ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
. .\config\random.ps1
. .\config\sendmail.ps1

if(!(Test-Path -Path "$ScriptPath\config\config.json"))
{
    Write-Host "Yikes! Config file not found!"
    Write-Host "Make sure config.json exists!"
    return
}
$Config = Get-Content -Path "$ScriptPath\config\config.json" | ConvertFrom-Json

if(!(Test-Path -Path "$ScriptPath\database.json"))
{
    Write-Host "Yikes! Database file not found!"
    Write-Host "Make sure database.json exists!"
    return
}
$DatabaseConfig = Get-Content -Path "$ScriptPath\database.json" | ConvertFrom-Json

try 
{
    Import-Module SqlServer
    [Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | out-null    
}
catch
{
    Write-Host "Unable to load Assembly!" -ForegroundColor Red
    Write-Host "Make sure the SqlServer Powershell module has been installed and loaded. (https://docs.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sql-server-ver15)" -ForegroundColor Red
    Exit
}

$RawName = $DatabaseConfig.DatabaseName
$DatabaseName = ($DatabaseConfig.DatabaseName).Replace("-","_").Replace(" ","")
$PasswordLength = $Config.PasswordLength
$EnvironmentNumber = $DatabaseConfig.EnvironmentNumber
$Environments = $DatabaseConfig.Environments
$Servers = $Config.Servers
$OutputFile = "$DatabaseName.txt"
Add-Content -Path $OutputFile -Value "Project name: $RawName"
Add-Content -Path $OutputFile -Value "vault_id : "+$RawName+"_db_password"

if($EnvironmentNumber -ge 5)
{
    Write-Host "Go create databases in Azure!"
    try 
    {
        $AzureToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
    }
    catch 
    {
        Write-Host "Make sure you are authenticated to Azure!"
        Write-Host "Connect-AzAccount"
        Write-Host "Set-AzContext AzureSubscriptionName"
        return
    }
}

foreach( $env in $Environments)
{
    Write-Host "Environment: $env"
    $DbName = ($DatabaseName+"_"+$env).ToLower()
    Add-Content -Path $OutputFile -Value "Database name: $DbName"
    $LoginName = ("svc_"+$DatabaseName+"_"+$env).ToLower()
    Add-Content -Path $OutputFile -Value "Login: $LoginName"    
    $Password = RandomString -Length $PasswordLength
    Add-Content -Path $OutputFile -Value "Password: $Password" 
    # $Sid = $null
    Write-Host "$DbName - $LoginName"


    foreach ($srv in $Servers | Where-Object {$_.Environment -eq $env -and $_.No -eq $EnvironmentNumber})
    {
        if($EnvironmentNumber -ge 4)
        {
                # Write-Host $azureToken
                $Server = $srv.Servers
                Write-Host $Server
                $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
                $AzureSql = Connect-DbaInstance -SqlInstance $Server -AccessToken $AzureToken -Database master
                New-DbaLogin -SqlInstance $AzureSql -Login $LoginName -SecurePassword $SecurePassword
                New-DbaDatabase -SqlInstance $AzureSql -Name $DbName -Owner $LoginName
                Add-Content -Path $OutputFile -Value "SQL Server: $Server" 
        }
        else
        {
            $Hag = ($Config.Servers | Where-Object {$_.Environment -eq $env -and $_.No -eq $EnvironmentNumber}).Hag
            if(!$Hag)
            {
                Write-Host "Unable to load Availibility name!"
                Exit
            }
            $Server = $srv.Servers[0]
            $MirrorServer = $srv.Servers[1]
            Write-Host "Servers: $Server, $MirrorServer"
            Write-Host "Availibility group name: $Hag"
            Add-Content -Path $OutputFile -Value "SQL Server: $Hag" 
            # Exit
            #Create logins
            Write-Host "Create login on servers"
            try 
            {
                $PriSvr = New-Object("Microsoft.SqlServer.Management.Smo.Server") $Server            
            }
            catch 
            {
                Write-Host "Unable to connect to primary server" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                Exit
            }
            try 
            {
                $MirSvr = New-Object("Microsoft.SqlServer.Management.Smo.Server") $MirrorServer
            }
            catch 
            {
                Write-Host "Unable to connect to secondary server" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                Exit
            }
            # Check if the login exists on the Principle server and Drop if it does
            if ($PriSvr.Logins.Contains($LoginName))
            {
                Write-Host "$LoginName exists!" -ForegroundColor Red
                Exit
            }    
            $NewLogin = New-Object ('Microsoft.SqlServer.Management.Smo.Login') $PriSvr, $LoginName
            # Specify that this is a SQL Login
            $NewLogin.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin;
            #Disable Password policy.
            $NewLogin.PasswordPolicyEnforced = $False;
            #Disable password expiration.
            $NewLogin.PasswordExpirationEnabled = $False;
            # Create the login on the Principle Server
            $NewLogin.Create($Password);
            # Refresh the login collection to get the login back with SID
            $PriSvr.Logins.Refresh();
            # Get a Login object for the Principle Server Login we just created
            $PriLogin = $PriSvr.Logins[$LoginName]
            # Create a new login for the Mirror Server
            $NewLogin = New-Object ('Microsoft.SqlServer.Management.Smo.Login') $MirSvr, $LoginName
            # Specify that this is a SQL Login
            $NewLogin.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin;
            #Disable Password policy.
            $NewLogin.PasswordPolicyEnforced = $False;
            #Disable password expiration.
            $NewLogin.PasswordExpirationEnabled = $False;
            # Assign the SID to this login from the Principle Server Login
            $NewLogin.set_Sid($PriLogin.get_Sid());
            # Create the Login on the Mirror Server
            $NewLogin.Create($Password);

            #Redefining $Server, as we have to connect to the active server to create the database, this is done by connecting to the Always on listener.
            $Server = $Hag
            #Create the database!
            Write-Host "Create database on primary (active) server ($Server)"
            $ConnectionString = "Server=$Server;Initial Catalog=master;Persist Security Info=True;MultipleActiveResultSets=False;Trusted_Connection=True;"
            $Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
            $Connection.Open()
            $Command = New-Object System.Data.SqlClient.SqlCommand
            $Command.Connection = $Connection

            Write-Host "Create database"
            $CreateDatabaseQuery = "CREATE DATABASE [$DbName];"
            $Command.CommandText = $CreateDatabaseQuery
            $Command.ExecuteNonQuery()

            Write-Host "Set permissions to service account"
            $PermissionQuery = "USE [$DbName]; CREATE USER [$LoginName] FOR LOGIN [$LoginName];ALTER ROLE [db_owner] ADD MEMBER [$LoginName];"
            $Command.CommandText = $PermissionQuery
            $Command.ExecuteNonQuery()

            Write-Host "Get backup directory"
            $BackupDir = $null
            $BackupDirQuery = "DECLARE @BackupDir VARCHAR(256); EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer',N'BackupDirectory', @BackupDir OUTPUT, 'no_output'; SELECT @BackupDir+'\'"
            $Command.CommandText = $BackupDirQuery
            $Reader = $Command.ExecuteReader()
            while($Reader.Read())
            {
                $BackupDir = $Reader.GetValue($1)
            }
            $Reader.Close()

            Write-Host "Backing up database: $DBName to $BackupDir on $Server"
            $BackupQuery = "BACKUP DATABASE [$DBName] TO  DISK = N'$BackupDir$DBName.bak' WITH NOFORMAT, NOINIT,  NAME = N'$DBName-Full Database Backup', SKIP, NOREWIND, NOUNLOAD, COMPRESSION"
            $Command.CommandText = $BackupQuery
            $Command.ExecuteNonQuery()

            Write-Host "Adding database to Availability group"
            # $MirrorServerName = $MirrorServer.Substring(0,$MirrorServer.IndexOf(","))
            # $HagQuery1 = "USE master; ALTER AVAILABILITY GROUP [$Hag] MODIFY REPLICA ON N'$MirrorServerName' WITH (SEEDING_MODE = AUTOMATIC)"
            # $Command.CommandText = $HagQuery1
            # $Command.ExecuteNonQuery()

            $HagQuery2 = "USE Master; ALTER AVAILABILITY GROUP [$Hag] ADD DATABASE [$DBName];"
            $Command.CommandText = $HagQuery2
            $Command.ExecuteNonQuery()

            #Get name of mirror server name
            $MirrorQuery = "SELECT member_name FROM sys.dm_hadr_cluster_members WHERE member_name != SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AND member_type = 0"
            $Command.CommandText = $MirrorQuery
            $Reader = $Command.ExecuteReader()
            while($Reader.Read())
            {
                $MirrorServerName = $Reader.GetValue($1)
            }
            $Reader.Close()
            if($srv.Servers[0] -match $MirrorServerName)
            {
                $MirrorServer = $Server
            }
            $Connection.Close()

            $ConnectionStringMirror = "Server=$MirrorServer;Initial Catalog=master;Persist Security Info=True;MultipleActiveResultSets=False;Trusted_Connection=True;"
            $ConnectionMirror = New-Object System.Data.SqlClient.SqlConnection($ConnectionStringMirror)
            $ConnectionMirror.Open()
            $CommandMirror = New-Object System.Data.SqlClient.SqlCommand
            $CommandMirror.Connection = $ConnectionMirror
            $HagQueryMirror = "USE Master; ALTER AVAILABILITY GROUP [$Hag] GRANT CREATE ANY DATABASE;"
            $CommandMirror.CommandText = $HagQueryMirror
            $CommandMirror.ExecuteNonQuery()

            $ConnectionMirror.Close()
        }
    }
    Add-Content -Path $OutputFile -Value "----------------------" 
}
#Write-Host "Sending details to recipients."
#SendMail -Header "New database created for $RawName" -Attachement "$ScriptPath\$OutputFile"