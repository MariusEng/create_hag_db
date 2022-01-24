Function SendMail 
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Header,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Attachement
    )


    $ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path

    if(!(Test-Path -Path "$ScriptPath\config\config.json"))
    {
        Write-Host "Yikes! Config file not found!"
        Write-Host "Make sure config.json exists!"
        Exit
    }
    $MailConfig = Get-Content -Path "$ScriptPath\config\config.json" | ConvertFrom-Json
    
    $SmptServer = $MailConfig.SMTPServer
    $Recipients = $MailConfig.EmailRecipients
    $From = $MailConfig.EmailSender
    $Body = Get-Content $Attachement
    try 
    {
        Add-Type -Path "C:\\Program Files\\PackageManagement\\NuGet\\Packages\\MailKit.2.9.0\\lib\\netstandard2.0\\MailKit.dll"
        Add-Type -Path "C:\\Program Files\\PackageManagement\\NuGet\\Packages\\MimeKit.2.9.2\\lib\\netstandard2.0\\MimeKit.dll"
    }
    catch
    {

        Write-Host "Unable to load MailKit, make sure package is installed" -ForegroundColor Red
        #Write-Host "Install-Package -Name Portable.BouncyCastle -Force -RequiredVersion 1.8.5 -SkipDependencies" -ForegroundColor Blue
        Write-Host "Make sure you have installed the .Net Core SDK: https://dotnet.microsoft.com/download/dotnet-core" -ForegroundColor Blue
        Write-Host "Install-Package MailKit -Force -SkipDependencies" -ForegroundColor Blue
        Write-Host "Install-Package MimeKit -Force -SkipDependencies" -ForegroundColor Blue
       
        Write-Host $_.Exception.Mesage -ForegroundColor Red
        Exit
    }
   
    $SMTP     = New-Object MailKit.Net.Smtp.SmtpClient
    $Message  = New-Object MimeKit.MimeMessage
    $TextPart = [MimeKit.TextPart]::new("plain")
    $TextPart.Text = "See attachment"
    
    
    foreach($Recipient in $Recipients)
    {
        $Message.To.Add($Recipient)
    }

    $Message.From.Add($From)
    $TextPart.Attachement.Add($Attachement)

    $Message.Subject = $Header
    $Message.Body    = $TextPart
    
    $SMTP.Connect($SmptServer, $False)
    $SMTP.Send($Message)
    $SMTP.Disconnect($true)
    $SMTP.Dispose()
    #https://www.powershellgallery.com/packages/PSGSuite/2.13.2/Content/Private%5CNew-MimeMessage.ps1
    #
}