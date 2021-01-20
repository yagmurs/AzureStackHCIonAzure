Import-Module AzureStackHCIInstallerHelper

#run interactive
Start-AksHciPoC

break

#cleanup VMs and rerun setup unattended
#Hint: run above interactive command to understand Configuration profile input parameters.
Start-AksHciPoC -CleanupVMs 1 `
    -RolesConfigurationProfile 0 `
    -NetworkConfigurationProfile 0 `
    -DisksConfigurationProfile 0 `
    -ClusterConfigurationProfile 0 `
    -AksHciConfigurationProfile 0

break

#cleanup VMs and all source files (Force to download Azure Stack HCI Iso file and re-create Base image)
Cleanup-Vms -RemoveAllSourceFiles

#rerun setup unattended
Start-AksHciPoC -RolesConfigurationProfile 0 `
    -NetworkConfigurationProfile 0 `
    -DisksConfigurationProfile 0 `
    -ClusterConfigurationProfile 0 `
    -AksHciConfigurationProfile 0