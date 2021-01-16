Click the button below to deploy from the portal:

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Ftest%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Ftest%2Fazuredeploy.json)

# Azure Stack HCI on Azure VM project

Creates new Azure VM and install prerequisites to run Proof of Concept for Azure Stack HCI.

## Version Compatibility

## Description

This ARM template and DSC extension prepares Azure VM as Hyper-v host (also Domain Controller) to run 2 or more Nested Azure Stack HCI host with nested virtualization enabled and Deploy 1 nested VM for Windows Admin Center named WAC. DSC extension download all the bits required.

## Step by Step Guidance

### High level deployment process and features

Deploy the ARM template (above buttons) by providing all the parameters required. Most of the parameters have default values and sufficient for demostrate Azure Stack HCI features and deployment procedures.
Windows Admin Center is also configured with DSC using Choco which means will be updated once released in Choco repository. All installed extensions are getting updated daily in the background.

Note that all VMs deployed within the Azure VM use **same password** that has been specified in the ARM template.

* All Local accounts are named as **Administrator**.
* The **Domain Administrator** username is the **Username specified in the ARM template**.

#### Nested VMs configurations

Once the deployment completed. There will be HPV01 and HPV02 and so on (based on azsHCIHostCount on the ARM template parameter) and WAC will be installed within the Azure VM.

* HPV01 will be configured with Ip address 192.168.0.101 with default gateway 192.168.0.1 and DNS 192.168.0.1
* HPV02 will be configured with Ip address 192.168.0.102 with default gateway 192.168.0.1 and DNS 192.168.0.1
* WAC will be configured with Ip address 192.168.0.100 with default gateway 192.168.0.1 and DNS 192.168.0.1

#### Deploying Azure Stack using Windows Admin Center

Before connecting to Windows Admin Center, run the following PowerShell code on Azure VM to trigger DSC configuration on WAC to make sure that all Windows Admin Center extensions updated.

Note: The following code will trigger Chromium based Edge and connect to WAC then start running updater.

```powershell

#Run from Azure VM (DC)
#Triggers DSC configuration on Windows Admin Center
Start-DscConfiguration -UseExisting -Wait -Verbose -ComputerName Wac

```

Highly recommended to run following Powershell code to overcome possible kerberos related configuration issues. Following code creates new OU, pre-stage computer accounts and delegate all computers in the OU to Windows Admin Center computer and also allow set Full control access to Cluster CNO on the new OU.

```powershell

#variables
$wac = "wac"
$AzureStackHCIHosts = @("hpv01", "hpv02")
$AzureStackHCIClusterName = "hci01"
$servers = $AzureStackHCIHosts + $AzureStackHCIClusterName
$ouName = "Cluster01"

#New organizational Unit for cluster
$dn = New-ADOrganizationalUnit -Name $ouName -PassThru

#Get Wac Computer Object
$wacObject = Get-AdComputer -Identity $wac

#Creates Azure Stack HCI hosts and Cluster CNO
$servers | ForEach-Object {New-ADComputer -Name $_ -Path $dn -PrincipalsAllowedToDelegateToAccount $wacObject -Enabled $false}

#read OU DACL
$acl = Get-Acl -Path "AD:\$dn"

# Set properties to allow Cluster CNO to Full Control on the new OU
$identity = (Get-ADComputer -Identity $AzureStackHCIClusterName)
$principal = New-Object System.Security.Principal.SecurityIdentifier ($identity).SID
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($principal, [System.DirectoryServices.ActiveDirectoryRights]::GenericAll, [System.Security.AccessControl.AccessControlType]::Allow, [DirectoryServices.ActiveDirectorySecurityInheritance]::All)

#modify DACL
$acl.AddAccessRule($ace)

#Re-apply the modified DACL to the OU
Set-ACL -ACLObject $acl -Path "AD:\$dn"

```

Open Edge browser installed on Azure Vm and connect to https://wac and invoke Azure Stack HCI wizard. And follow the steps. 192.168.0.11 can be used as cluster static Ip address during Azure Stack HCI cluster creation.

Once you have deployed your Azure Stack HCI cluster, You can use 192.168.100.0/24 to let them use DHCP server configured on Azure VM. So all VMs would be able to connect to Internet.

**Do not use 192.168.0.0/24 , 192.168.100.0/24 , 192.168.251.0/24, 192.168.252.0/24, 192.168.253.0/24 , 192.168.254.0/24 networks as address space for Vnet since those network are getting utilized in the Nested environment.**

### Deploying ARM template using Powershell

```powershell

```

### How to deploy Azure Stack HCI using Windows Admin Center

![alt](https://github.com/yagmurs/AzureStackHCIonAzure/raw/master/.images/azshciusingwac.gif)

<!--- <img src="./.images/azshciusingwac.gif" width="720" height="576" />

<img src="./.images/azshciusingwac.gif" data-canonical-src="./.images/azshciusingwac.gif" width="1280" height="720" /> --->

### VMs in the nested environment messed up / willing to Reset?

Just run the following PowerShell code on the Azure Host. It will re-create Azure Stack HCI image from scratch. Will take about 3-5 mins to complete this task including WAC deployment.

```powershell

#variables
$AzureStackHCIHosts = Get-VM hpv*
$AzureStackHCIClusterName = 'Hci01'
$wac = Get-VM wac
$domainName = (Get-ADDomain).DnsRoot
$dhcpScopeString = '192.168.0.0'

#remove Azure Stack HCI hosts
$AzureStackHCIHosts | Stop-VM -TurnOff -Passthru | Remove-VM -Force
Remove-Item -Path $AzureStackHCIHosts.ConfigurationLocation -Recurse -Force

#remove Azure Stack HCI hosts DNS records, DHCP leases and Disable Computer Accounts
$AzureStackHCIHosts.Name | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $domainName -Name $_ -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force}
$AzureStackHCIHosts.Name | ForEach-Object {Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $_* | Remove-DhcpServerv4Lease}
$AzureStackHCIHosts.Name | ForEach-Object {Set-ADComputer -Identity $_ -Enabled $false -ErrorAction SilentlyContinue}
Set-ADComputer -Identity $AzureStackHCIClusterName -Enabled $false -ErrorAction SilentlyContinue

#remove Windows Admin Center host
$wac | Stop-VM -TurnOff -Passthru | Remove-VM -Force
Remove-Item -Path $wac.ConfigurationLocation -Recurse -Force

#remove Windows Admin Center host DNS record, DHCP lease
Get-DnsServerResourceRecord -ZoneName $domainName -Name $wac.Name -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force
Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $wac.Name | Remove-DhcpServerv4Lease

#remove Wac DSC Config
Remove-Item -Path "V:\source\Install-WacUsingChoco.ps1" -Force #in case if updated.

Start-DscConfiguration -UseExisting -Wait -Verbose -Force

```

### Is there new Azure Stack HCI image available and want re-install?

Just run the following PowerShell code on the Azure Host. It will re-download bits and prepare Azure Stack HCI image from scratch. Will take about 20 mins to complete this task including WAC deployment.

```powershell

#variables
$AzureStackHCIHosts = Get-VM hpv*
$AzureStackHCIClusterName = 'Hci01'
$domainName = (Get-ADDomain).DnsRoot
$dhcpScopeString = '192.168.0.0'

#remove Azure Stack HCI hosts
$AzureStackHCIHosts | Stop-VM -TurnOff -Passthru | Remove-VM -Force
Remove-Item -Path $AzureStackHCIHosts.ConfigurationLocation -Recurse -Force

#remove Azure Stack HCI hosts DNS records, DHCP leases and Disable Computer Accounts
$AzureStackHCIHosts.Name | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $domainName -Name $_ -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force}
$AzureStackHCIHosts.Name | ForEach-Object {Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $_* | Remove-DhcpServerv4Lease}
$AzureStackHCIHosts.Name | ForEach-Object {Set-ADComputer -Identity $_ -Enabled $false -ErrorAction SilentlyContinue}
Set-ADComputer -Identity $AzureStackHCIClusterName -Enabled $false -ErrorAction SilentlyContinue

Start-DscConfiguration -UseExisting -Wait -Verbose -Force

```

## Support Statement

This solution is not officially support by **Microsoft** and experimental, may not work in the future.

## Issues and features

### Known issues

During the Azure Stack HCI deployment through the Windows Admin Center (Phase 1.5) you might get an error 'hpv\<Suffix> doesn't seem to be internet-connected.' You can disregard the error message. All VMs are connected and will install updates.

### How to file a bug

1. Go to our [issue tracker on GitHub](https://github.com/yagmurs/AzureStackHCIonAzureVM/issues)
1. Search for existing issues using the search field at the top of the page
1. File a new issue including the info listed below

### Requesting a feature

Feel free to file new feature requests as an issue on GitHub, just like a bug.

 > Yagmur Sahin
 >
 > Twitter: [@yagmurs](https://twitter.com/yagmurs)
