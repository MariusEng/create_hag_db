$ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
. .\config\random.ps1
. .\config\sendmail.ps1

$OutputFile = "marius_er_kul.txt"
$RawName = 'marius-er-kul'
SendMail -Header "New database created for $RawName" -Attachement "$ScriptPath\$OutputFile"