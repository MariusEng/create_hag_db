function RandomString
{
    param(
        [Parameter(Mandatory=$true, Position=0, ParameterSetName = "Length")]
        [int]$Length
    )
    $CharArray = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!?#_-.%&@").ToCharArray()
    $RandomString = ""
    $Position = 1
    while($Position -le $Length)
    {
        $char = $null
        while(!$char)
        {
            $ran = ((Get-Random -Minimum 1 -Maximum 512000) % (Get-Random) / 1090)
            $char = $CharArray[$ran]
            #Write-Host "$ran - $char"
        }
        $RandomString = $RandomString+$char
        $Position++
    }
    return $RandomString
}