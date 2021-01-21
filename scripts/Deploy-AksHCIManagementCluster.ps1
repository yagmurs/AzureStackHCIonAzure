#https://docs.microsoft.com/en-us/azure-stack/aks-hci/setup-powershell

#run following code from one of Azure Stack HCI Cluster node (Logon using Domain Credentials)

#Enable AksHCI
$azSHCICSV = "AksHCIMain"
$azSHCICSVPath = "v:\$azSHCICSV"
Import-Module AksHci
Initialize-AksHciNode

#Deploy Management Cluster
Set-AksHciConfig -imageDir "$azSHCICSVPath\Images" -cloudConfigLocation "$azSHCICSVPath\Config" `
    -workingDir "$azSHCICSVPath\Working" -vnetName 'Default Switch' -controlPlaneVmSize Default `
    -loadBalancerVmSize Default -vnetType ICS

Install-AksHci
