param(
    [string]$MachineCode,
    [string]$CustomerName,
    [ValidateSet('lifetime', 'single_use', 'subscription')]
    [string]$Type,
    [int]$SubscriptionDays = 30
)

$secret = 'COBREJA_WIN_LIC_2026_FMB_0720'

function Read-IfEmpty {
    param(
        [string]$Value,
        [string]$Prompt
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return (Read-Host $Prompt).Trim()
    }

    return $Value.Trim()
}

function To-Base64Url {
    param([string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $base64 = [System.Convert]::ToBase64String($bytes)
    return $base64.TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-Signature {
    param([string]$PayloadBase64)

    $encoding = [System.Text.Encoding]::UTF8
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($encoding.GetBytes($secret))
    try {
        $hashBytes = $hmac.ComputeHash($encoding.GetBytes($PayloadBase64))
        return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '')
    } finally {
        $hmac.Dispose()
    }
}

$MachineCode = Read-IfEmpty $MachineCode 'Codigo da maquina'
$CustomerName = Read-IfEmpty $CustomerName 'Nome do cliente'
$Type = Read-IfEmpty $Type 'Tipo (lifetime / single_use / subscription)'

if ([string]::IsNullOrWhiteSpace($MachineCode)) {
    throw 'Informe o codigo da maquina.'
}

if ([string]::IsNullOrWhiteSpace($CustomerName)) {
    $CustomerName = 'Cliente'
}

$issuedAt = [DateTime]::UtcNow
$expiresAt = $null

if ($Type -eq 'subscription') {
    if ($SubscriptionDays -le 0) {
        $SubscriptionDays = 30
    }
    $expiresAt = $issuedAt.AddDays($SubscriptionDays).ToString('o')
}

$payload = [ordered]@{
    product      = 'COBREJA_WINDOWS'
    machineCode  = $MachineCode.ToUpperInvariant()
    type         = $Type
    customerName = $CustomerName
    issuedAt     = $issuedAt.ToString('o')
    expiresAt    = $expiresAt
    licenseId    = ([Guid]::NewGuid().ToString('N').Substring(0, 12)).ToUpperInvariant()
}

$payloadJson = $payload | ConvertTo-Json -Compress
$payloadBase64 = To-Base64Url $payloadJson
$signature = New-Signature $payloadBase64
$license = "$payloadBase64.$signature"

Write-Host ''
Write-Host 'Licenca gerada com sucesso:' -ForegroundColor Green
Write-Host ''
Write-Output $license
Write-Host ''
Write-Host "Tipo: $Type"
Write-Host "Cliente: $CustomerName"
Write-Host "Codigo da maquina: $MachineCode"
if ($expiresAt) {
    Write-Host "Expira em: $expiresAt"
}
