Click the button below to deploy from the portal:

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Fmaster%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Fmaster%2Fazuredeploy.json)


# Azure Stack HCI on Azure VM project

Creates new Azure VM and install prerequisites to run Proof of Concept for Azure Stack HCI.

## Version Compatibility


## Description

This ARM template and DSC extension prepares Azure VM as Hyper-v host (also Domain Controller) to run 2 or more Nested Azure Stack HCI host with nested virtualization enabled and Deploy 1 nested VM for Windows Admin Center named WAC. DSC extension download all the bits required.

## Step by Step Guidance

### High level deployment process and features

Deploy the ARM template by providing all the parameters required. Most of the parameters have default values and sufficient for demostrate Azure Stack HCI features and deployment procedures.
Windows Admin Center is also configured with DSC using Choco which means will be updated once released in Choco repository. All installed extensions are getting updated daily in the background.

### Deploying ARM template using Powershell

```powershell

```

### VMs in the nested environment messed up?

Just run the following PowerShell code on the Azure Host. It will re-create Azure Stack HCI image from scratch. Will take about 3-5 mins to complete this task including WAC deployment.

```powershell
Get-VM hpv*, wac | Stop-VM -TurnOff -Passthru | Remove-VM -Force

Remove-Item -Path "V:\VMs\hpv*", "V:\VMs\wac" -Recurse -Force
Remove-Item -Path "V:\source\Install-WacUsingChoco.ps1" -Force #in case if updated.

Start-DscConfiguration -UseExisting -Wait -Verbose -Force

```

### Is there new Azure Stack HCI image available and want re-install?

Just run the following PowerShell code on the Azure Host. It will re-download bits and prepare Azure Stack HCI image from scratch. Will take about 20 mins to complete this task including WAC deployment.

```powershell

Get-VM hpv*, wac | Stop-VM -TurnOff -Passthru | Remove-VM -Force

Remove-Item -Path "V:\VMs\hpv*", "V:\VMs\wac" -Recurse -Force
Remove-Item -Path "V:\source\Install-WacUsingChoco.ps1", "V:\source\AzSHCI.iso" -Force
Remove-Item -Path "V:\VMs\base\AzSHCI.vhdx" -Force

Start-DscConfiguration -UseExisting -Wait -Verbose -Force

```

## Support Statement

This solution is not officially support by **Microsoft** and experimental, may not work in the future.

## Issues and features

### How to file a bug

1. Go to our [issue tracker on GitHub](https://github.com/yagmurs/AzureStackHCIonAzureVM/issues)
1. Search for existing issues using the search field at the top of the page
1. File a new issue including the info listed below

### Requesting a feature

Feel free to file new feature requests as an issue on GitHub, just like a bug.

 > Yagmur Sahin
 >
 > Twitter: [@yagmurs](https://twitter.com/yagmurs)
