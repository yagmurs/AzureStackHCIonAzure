configuration WindowsAdminCenter
{
    Import-DscResource -ModuleName cChoco
    node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyAndAutoCorrect'
            ConfigurationModeFrequencyMins = 1440
        }

        cChocoInstaller InstallChoco
        {
            InstallDir = "c:\choco"
        }

        cChocoFeature allowGlobalConfirmation 
        {

            FeatureName = "allowGlobalConfirmation"
            Ensure      = 'Present'
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cChocoFeature useRememberedArgumentsForUpgrades 
        {

            FeatureName = "useRememberedArgumentsForUpgrades"
            Ensure      = 'Present'
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cChocoPackageInstaller "Install Windows Admin Center on 443"
        {
            Name        = 'windows-admin-center'
            Ensure      = 'Present'
            AutoUpgrade = $true
            DependsOn   = '[cChocoInstaller]installChoco'
            Params      = "'/Port:443'"
        }
        
        <#
            Inspired script resource from George Markau blog post
            https://www.markou.me/2019/09/how-to-automatically-update-windows-admin-center-extensions/
            Twitter: @george_markou
            https://twitter.com/george_markou
         #> 
        script "Windows Admin Center updater"
        {
            GetScript = {
                # Add the module to the current session
                $module = "$env:ProgramFiles\Windows Admin Center\PowerShell\Modules\ExtensionTools"
                Import-Module -Name $module -Verbose
                
                # Specify the WAC gateway
                $WAC = "https://$env:COMPUTERNAME"
                
                # List the WAC extensions
                $extensions = Get-Extension $WAC | Where-Object {$_.isLatestVersion -like 'False'}
                
                $result = if ($extensions.count -gt 0) {$false} else {$true}

                return @{
                    Wac = $WAC
                    extensions = $extensions
                    result = $result
                }
            }
            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            SetScript = {
                $module = "$env:ProgramFiles\Windows Admin Center\PowerShell\Modules\ExtensionTools"
                Import-Module -Name $module -Verbose

                # Specify the WAC gateway
                $WAC = "https://$env:COMPUTERNAME"
                
                # List the WAC extensions
                $extensions = Get-Extension $WAC | Where-Object {$_.isLatestVersion -like 'False'}

                $date = get-date -f yyyy-MM-dd

                $logFile = Join-Path -Path "C:\Users\Public" -ChildPath $('WACUpdateLog-' + $date + '.log')

                New-Item -Path $logFile -ItemType File -Force
                
                ForEach($extension in $extensions)
                {    
                    Update-Extension $wac -ExtensionId $extension.Id -Verbose | Out-File -Append -FilePath $logFile -Force
                }

                # Delete log files older than 30 days
                Get-ChildItem -Path "C:\Users\Public\WACUpdateLog*" -Recurse -Include @("*.log") | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-30)} | Remove-Item
            }
            DependsOn = "[cChocoPackageInstaller]Install Windows Admin Center on 443"
        }
    }
}


$date = get-date -f yyyy-MM-dd
$logFile = Join-Path -Path "C:\temp" -ChildPath $('WindowsAdminCenter-Transcipt-' + $date + '.log')
$DscConfigLocation = "c:\temp\WindowsAdminCenter"

Start-Transcript -Path $logFile

Remove-DscConfigurationDocument -Stage Current, Previous, Pending -Force

WindowsAdminCenter -OutputPath $DscConfigLocation 

Set-DscLocalConfigurationManager -Path $DscConfigLocation -Verbose
Start-DscConfiguration -Path $DscConfigLocation -Wait -Verbose

$i = 0
do
{
    Write-Verbose "Sleeping for 5 seconds to Check LCM State set to 'Idle'" -Verbose
    Start-Sleep -Seconds 5
    $i++
    if ($i -gt 12)
    {
        Write-Verbose "Gave up sleeping!! Current configuration will be applied forcefully" -Verbose
        Start-DscConfiguration -UseExisting -Wait -Verbose -Force
        Stop-Transcript
        Logoff
    }
}
until ((Get-DscLocalConfigurationManager |Select-Object -ExpandProperty lcmstate) -eq "Idle")

Start-DscConfiguration -UseExisting -Wait -Verbose

Stop-Transcript

Logoff
