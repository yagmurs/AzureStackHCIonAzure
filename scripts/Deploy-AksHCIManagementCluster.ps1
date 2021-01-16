#https://docs.microsoft.com/en-us/azure-stack/aks-hci/setup-powershell

#run following code from any Azure Stack HCI host

#Enable AksHCI
$azSHCICSV = "AksHCIMain"
$azSHCICSVPath = "c:\ClusterStorage\$azSHCICSV"
Import-Module AksHci
Initialize-AksHciNode

#Deploy Management Cluster
Set-AksHciConfig -imageDir "$azSHCICSVPath\Images" -cloudConfigLocation "$azSHCICSVPath\Config" `
    -vnetName ConvergedSwitch -controlPlaneVmSize Default -loadBalancerVmSize Default
Install-AksHci

#Retreive AksHCI logs for Management Cluster deployment
