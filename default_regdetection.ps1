$AppName = "Adobe Acrobat (64-bit)*"
$Reg = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall","HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall" | Get-ItemProperty | Where-Object {$_.DisplayName -ilike "$($AppName)" } | Select-Object -Property DisplayName, DisplayVersion, PSChildName
if($Reg)
{
    if($Reg.GetType().Name -eq "PSCustomObject")
    {
        if([Version](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Reg.PSChildName)","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($Reg.PSChildName)" -Name DisplayVersion -ea SilentlyContinue) -eq [version]"'+$($AppInfo.Version)+'"){Write-Host "Installed";Exit 0}}
        else{foreach($App in $Reg){if([Version](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($App.PSChildName)","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($App.PSChildName)" -Name DisplayVersion -ea SilentlyContinue) -eq [version]"'+$($AppInfo.Version)+'"){Write-Host "Installed";Exit 0}}
    }
}
