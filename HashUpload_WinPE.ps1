<#
Application permissions needed in the app registration:
Microsoft Graph
    Application.Read.All - reding app secret
    Device.ReadWrite.All - delete from Entra - Device.Read.All falls nicht aus Entra gelöscht werden soll
    DeviceManagementManagedDevices.ReadWrite.All - delete from Intune
    DeviceManagementServiceConfig.ReadWrite.All - delete from Autopilot
    GroupMember.ReadWrite.All - add to group

    Credits: https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/
    
#>
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-Module -Name WindowsAutoPilotIntune -SkipPublisherCheck -Scope AllUsers -Force
Install-Module -Name Microsoft.Graph.DeviceManagement -SkipPublisherCheck -Scope AllUsers -Force
Install-Module -Name Microsoft.Graph.Identity.DirectoryManagement -SkipPublisherCheck -Scope AllUsers -Force
Install-Module -Name Microsoft.Graph.Applications -SkipPublisherCheck -Scope AllUsers -Force

$SCCM = New-Object -ComObject Microsoft.SMS.TSEnvironment

$session = New-CimSession
$serial = (Get-CimInstance -CimSession $session -Class Win32_BIOS).SerialNumber
Remove-CimSession $session

$intunedevice = Get-MgDeviceManagementManagedDevice -filter "serialNumber eq '$serial'"
if($intunedevice){Write-Host "Removing from Intune"; Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $intunedevice.Id; Write-Host " "}

$autodevice = Get-AutopilotDevice -serial $serial
if($autodevice)
{
    $autodevice2 = $autodevice
    Write-Host "Removing from Autopilot"; Remove-AutopilotDevice -id $autodevice2.id; Write-Host " "
    while ($null -ne $autodevice2)
    {
        $autodevice2 = $null
        $autodevice2 = Get-AutopilotDevice -serial $serial
        Write-Host "Waiting for device to be deleted from autopilot"
        Start-Sleep 10
    }
    Write-Host " "
    Write-Host "Device $($serial) sucessfully deleted from autopilot"
    Write-Host " "

    #Remove device from Entra
    $entradevice = Get-MgDevice -Filter "DeviceId eq '$($autodevice.azureActiveDirectoryDeviceId)'" -ErrorAction SilentlyContinue
    if($entradevice){Write-Host "Removing from Entra"; Remove-MgDevice -DeviceId $entradevice.id; Write-Host " "}
}


$Label = $SCCM.Value("VAR_GroupTag_$HashTenantName")
If ((Test-Path X:\Windows\System32\wpeutil.exe) -and (Test-Path .\Autopilot\PCPKsp.dll)) { Copy-Item ".\Autopilot\PCPKsp.dll" 'X:\Windows\System32\PCPKsp.dll'; rundll32 X:\Windows\System32\PCPKsp.dll, DllInstall }
#Change Current Diretory so OA3Tool finds the files written in the Config File
#Delete old Files if exits
if (Test-Path .\OA3.xml) { Remove-Item .\OA3.xml }
#Run OA3Tool
Write-Host "Creating Hash"; Write-Host " "
& .\Autopilot\oa3tool.exe /Report /ConfigFile=.\Autopilot\OA3.cfg /NoKeyCheck
#Check if Hash was found
If (Test-Path .\OA3.xml)
{
    #Read Hash from generated XML File
    [xml]$xmlhash = Get-Content -Path ".\OA3.xml"
    $hash = $xmlhash.Key.HardwareHash
    #Delete XML File
    Remove-Item ".\OA3.xml"
}
else { Write-Host 'No Hardware Hash found'; exit 1}
Write-Host "Import Hash"
if ($Label -ne 'None') { $DeviceAdded = Add-AutopilotImportedDevice -serialNumber $serial -hardwareIdentifier $hash -groupTag $Label }
else { $DeviceAdded = Add-AutopilotImportedDevice -serialNumber $serial -hardwareIdentifier $hash }
# Wait until the devices have been imported
$processingCount = 1
while ($processingCount -gt 0) {
    $current = @()
    $processingCount = 0
    $deviceadded | ForEach-Object {
        $device = Get-AutopilotImportedDevice -id $_.id
        if ($device.state.deviceImportStatus -eq 'unknown') {
            $processingCount = $processingCount + 1
        }
        $current += $device
    }
    $deviceCount = $deviceadded.Length
    Write-Host "Waiting for $processingCount of $deviceCount to be imported"
    if ($processingCount -gt 0) {
        Start-Sleep 30
    }
}
$importStart = Get-Date
$importDuration = (Get-Date) - $importStart
$importSeconds = [Math]::Ceiling($importDuration.TotalSeconds)
$successCount = 0
$current | ForEach-Object {
    Write-Host "$($device.serialNumber): $($device.state.deviceImportStatus) $($device.state.deviceErrorCode) $($device.state.deviceErrorName)"
    if ($device.state.deviceImportStatus -eq 'complete') {
        $successCount = $successCount + 1
    }
    if($device.state.deviceErrorCode -eq 808){exit 666}
}
Write-Host "$successCount devices imported successfully. Elapsed time to complete import: $importSeconds seconds"
# Wait until the devices can be found in Intune (should sync automatically)
$syncStart = Get-Date
$processingCount = 1
while ($processingCount -gt 0) {
    $autopilotDevices = @()
    $processingCount = 0
    $current | ForEach-Object {
        if ($device.state.deviceImportStatus -eq 'complete') {
            $device = Get-AutopilotDevice -id $_.state.deviceRegistrationId
            if (-not $device) {
                $processingCount = $processingCount + 1
            }
            $autopilotDevices += $device
        }
    }
    $deviceCount = $autopilotDevices.Length
    Write-Host "Waiting for $processingCount of $deviceCount to be synced"
    if ($processingCount -gt 0) {
        Start-Sleep 30
    }
}
$syncDuration = (Get-Date) - $syncStart
$syncSeconds = [Math]::Ceiling($syncDuration.TotalSeconds)
Write-Host "All devices synced. Elapsed time to complete sync: $syncSeconds seconds"
$assignStart = Get-Date
$processingCount = 1
while ($processingCount -gt 0) {
    $processingCount = 0
    $autopilotDevices | ForEach-Object {
        $device = Get-AutopilotDevice -id $_.id -Expand
        if (-not ($device.deploymentProfileAssignmentStatus.StartsWith('assigned'))) {
            $processingCount = $processingCount + 1
        }
    }
    $deviceCount = $autopilotDevices.Length
    Write-Host "Waiting for $processingCount of $deviceCount to be assigned"
    if ($processingCount -gt 0) {
        Start-Sleep 30
    }
}
$assignDuration = (Get-Date) - $assignStart
$assignSeconds = [Math]::Ceiling($assignDuration.TotalSeconds)
Write-Host "Profiles assigned to all devices. Elapsed time to complete assignment: $assignSeconds seconds"
Disconnect-MgGraph | Out-Null