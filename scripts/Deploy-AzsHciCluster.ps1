Import-Module AzureStackHCIInstallerHelper

Start-AzureStackHciSetup

break

#cleanup VMs 
Start-AzureStackHciSetup -CleanupVMs 1 -