Import-Module AzureStackHCIInstallerHelper

#run interactive
Start-AzureStackHciSetup

break

#cleanup VMs and rerun setup unattended
Start-AzureStackHciSetup -CleanupVMs 1 `
    -RolesConfigurationProfile 0 `
    -NetworkConfigurationProfile 0 `
    -DisksConfigurationProfile 0 `
    -ClusterConfigurationProfile 0 `
    -AksHciConfigurationProfile 0
