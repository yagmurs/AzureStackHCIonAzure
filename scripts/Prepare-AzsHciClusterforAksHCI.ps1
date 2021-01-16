#variables
$targetDrive = "V:"
$sourcePath =  "$targetDrive\source"
$aksSource = "$sourcePath\aksHciSource"
$AzureStackHCIHosts = Get-VM hpv*
$AzureStackHCIClusterName = 'Hci01'
$azSHCICSV = "AksHCIMain"
$azSHCICSVPath = "c:\ClusterStorage\$azSHCICSV"

#create source folder for AKS bits
New-Item -Path $aksSource -ItemType Directory -Force

#Download AKS on Azure Stack HCI tools
Start-BitsTransfer -Source https://aka.ms/aks-hci-download -Destination "$aksSource\aks-hci-tools.zip"

#unblock download file
Unblock-File -Path "$aksSource\aks-hci-tools.zip"

#Unzip download file
Expand-Archive -Path "$aksSource\aks-hci-tools.zip" -DestinationPath "$aksSource\aks-hci-tools" -Force

#Unzip Powershell modules
Expand-Archive -Path "$aksSource\aks-hci-tools\AksHci.Powershell.zip" -DestinationPath "$aksSource\aks-hci-tools\Powershell\Modules" -Force

#Update NuGet Package provider on AzsHci Host
Invoke-Command -ComputerName $AzureStackHCIHosts.Name -ScriptBlock {
    Install-PackageProvider -Name NuGet -Force 
    Install-Module -Name PowershellGet -Force -Confirm:$false -SkipPublisherCheck
}

#Copy AksHCI modules to Azure Stack HCI hosts
$AzureStackHCIHosts.Name | ForEach-Object {Copy-Item "$aksSource\aks-hci-tools\Powershell\Modules" "\\$_\c$\Program Files\WindowsPowershell\" -Recurse -Force}

#create Cluster Shared Volume for AksHCI and Enable Deduplication
#New-Volume -CimSession "$($AzureStackHCIHosts[0].Name)" -FriendlyName $azSHCICSV -FileSystem CSVFS_ReFS -StoragePoolFriendlyName S2D* -Size 1.3TB
New-Volume -CimSession $AzureStackHCIClusterName -FriendlyName $azSHCICSV -FileSystem CSVFS_ReFS -StoragePoolFriendlyName cluster* -Size 1.3TB
Enable-DedupVolume -CimSession $AzureStackHCIClusterName -Volume $azSHCICSVPath
Enable-DedupVolume -CimSession $AzureStackHCIClusterName -Volume $azSHCICSVPath -UsageType HyperV -DataAccess


