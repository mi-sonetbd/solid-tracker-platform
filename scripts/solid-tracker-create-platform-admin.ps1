[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform",
    [string]$MobileNumber,
    [string]$FullName
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $RepositoryPath

if ([string]::IsNullOrWhiteSpace($MobileNumber)) {
    $MobileNumber = Read-Host "Administrator mobile number"
}

if ([string]::IsNullOrWhiteSpace($FullName)) {
    $FullName = Read-Host "Administrator full name"
}

$password = Read-Host "Administrator password" -AsSecureString
$confirmation = Read-Host "Confirm administrator password" -AsSecureString

$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
    $password
)

$confirmationPointer =
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $confirmation
    )

try {
    $plainPassword =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $passwordPointer
        )

    $plainConfirmation =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $confirmationPointer
        )

    if ($plainPassword -cne $plainConfirmation) {
        throw "Password confirmation does not match."
    }

    $env:SOLID_TRACKER_BOOTSTRAP_PASSWORD = $plainPassword

    & pnpm.cmd `
        --filter "@solid-tracker/backend-api" `
        identity:create-admin `
        -- `
        --mobile $MobileNumber `
        --name $FullName

    if ($LASTEXITCODE -ne 0) {
        throw "Platform administrator creation failed."
    }
}
finally {
    Remove-Item Env:SOLID_TRACKER_BOOTSTRAP_PASSWORD `
        -ErrorAction SilentlyContinue

    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $passwordPointer
        )
    }

    if ($confirmationPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $confirmationPointer
        )
    }

    $plainPassword = $null
    $plainConfirmation = $null
}