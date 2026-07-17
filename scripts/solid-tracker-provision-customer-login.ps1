[CmdletBinding()]
param(
    [string]$RepositoryPath =
        "D:\GitHub\gps-tracker-platform",
    [string]$MobileNumber,
    [string]$FullName,
    [ValidateSet(
        "CUSTOMER_OWNER",
        "CUSTOMER_ADMIN",
        "CUSTOMER_VIEWER"
    )]
    [string]$RoleCode = "CUSTOMER_OWNER"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Convert-ToPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Value
    )

    $pointer =
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $Value
        )

    try {
        return (
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                $pointer
            )
        )
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $pointer
        )
    }
}

if (-not (Test-Path -LiteralPath $RepositoryPath)) {
    throw "Repository path does not exist: $RepositoryPath"
}

Set-Location -LiteralPath $RepositoryPath

if ([string]::IsNullOrWhiteSpace($MobileNumber)) {
    $MobileNumber =
        (Read-Host "Customer mobile number").Trim()
}

if ([string]::IsNullOrWhiteSpace($FullName)) {
    $FullName =
        (Read-Host "Customer full name").Trim()
}

if ([string]::IsNullOrWhiteSpace($MobileNumber)) {
    throw "Customer mobile number is required."
}

if ([string]::IsNullOrWhiteSpace($FullName)) {
    throw "Customer full name is required."
}

$password =
    Read-Host "Customer password" -AsSecureString
$confirmation =
    Read-Host "Confirm Customer password" -AsSecureString

$plainPassword = Convert-ToPlainText -Value $password
$plainConfirmation =
    Convert-ToPlainText -Value $confirmation

try {
    if ($plainPassword -cne $plainConfirmation) {
        throw "Password confirmation does not match."
    }

    $env:SOLID_TRACKER_CUSTOMER_PASSWORD =
        $plainPassword

    & pnpm.cmd `
        --filter "@solid-tracker/backend-api" `
        exec tsx `
        "src/identity/cli/provision-customer-login.ts" `
        -- `
        --mobile $MobileNumber `
        --name $FullName `
        --role $RoleCode

    if ($LASTEXITCODE -ne 0) {
        throw "Customer login provisioning failed."
    }
}
finally {
    Remove-Item `
        Env:SOLID_TRACKER_CUSTOMER_PASSWORD `
        -ErrorAction SilentlyContinue

    $plainPassword = $null
    $plainConfirmation = $null
    $password.Dispose()
    $confirmation.Dispose()
}