configuration hciconfig
{
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyAndAutoCorrect'
            ConfigurationModeFrequencyMins = 1440
        }

        WindowsFeatureSet "AzsHci Required Roles"
        {
            Ensure = 'Present'
            Name = @("NetworkATC", "Hyper-V" ,"FS-Data-Deduplication", "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "RSAT", "RSAT-Feature-Tools", "RSAT-DataCenterBridging-LLDP-Tools", "RSAT-Clustering", "RSAT-Clustering-PowerShell", "RSAT-Role-Tools", "RSAT-AD-Tools", "RSAT-AD-PowerShell", "RSAT-Hyper-V-Tools", "Hyper-V-PowerShell")
        }
    }
}



