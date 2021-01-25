#https://docs.microsoft.com/en-us/azure-stack/aks-hci/setup-powershell

#the following function downloads, extract and place required PowerShell Modules in PowerShell modules folder
Prepare-AzureVMforAksHciDeployment

#Enable AksHCI

$targetDrive = "V:"
$AksHciTargetFolder = "AksHCIMain"
$AksHciTargetPath = "$targetDrive\$AksHciTargetFolder"

Import-Module AksHci
Initialize-AksHciNode

#Deploy Management Cluster
Set-AksHciConfig -imageDir "$AksHciTargetPath\Images" -cloudConfigLocation "$AksHciTargetPath\Config" `
    -workingDir "$AksHciTargetPath\Working" -vnetName 'Default Switch' -controlPlaneVmSize Default `
    -loadBalancerVmSize Default -vnetType ICS

Install-AksHci

#Deploy Target Cluster
$targetClusterName = "target-cls1"

New-AksHciCluster -clusterName $targetClusterName -kubernetesVersion v1.18.8 `
    -controlPlaneNodeCount 1 -linuxNodeCount 1 -windowsNodeCount 0 `
    -controlplaneVmSize default -loadBalancerVmSize default -linuxNodeVmSize Standard_D4s_v3 -windowsNodeVmSize default

#list Aks Hci cmdlets
Get-Command -Noun akshci*

#List k8s clusters
Get-AksHciCluster

#Retreive AksHCI logs for Target Cluster deployment
Get-AksHciCredential -clusterName $targetClusterName

# Install Az module to access Azure
Install-Module az

# list Az module 
Get-Command -Noun az*

# login Azure
Connect-AzAccount -Tenant xxxxxx.onmicrosoft.com

# Get current Azure context
Get-AzContext

# list subscriptions 
Get-AzSubscription

# select subscription
Select-AzSubscription -Subscription xxxxxxx

# Verify using correct subscription
Get-AzContext
$context = Get-AzContext

# Create new resource group to onboard Aks Hci to Azure Arc
$rg = New-AzResourceGroup -Name new-arc-rg -Location westeurope

#https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azadserviceprincipal?view=azps-5.4.0
# Create new Spn on azure
$sp = New-AzADServicePrincipal -Role Contributor -Scope /subscriptions/903b7ed3-e5e7-405d-a40d-70d9fc324087/resourceGroups/new-arc-rg
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($sp.ApplicationId, $sp.Secret)

#https://docs.microsoft.com/en-us/azure-stack/aks-hci/connect-to-arc
# Onboard Aks Hci to Azure Arc
Install-AksHciArcOnboarding -clusterName "target-cls1" -resourcegroup $rg.ResourceGroupName -location $rg.location -subscriptionId $context.Subscription.Id -clientid $sp.ApplicationId -clientsecret $credObject.GetNetworkCredential().Password -tenantid $context.Tenant.Id

# get state of the onboarding process
kubectl get pods -n azure-arc-onboarding

# list error information
kubectl describe pod -n azure-arc-onboarding azure-arc-onboarding-<Name of the pod>
kubectl logs -n azure-arc-onboarding azure-arc-onboarding-<Name of the pod>

#deploy demo application from Azure Arc Enabled Kubernetes from portal
#https://github.com/Azure/arc-k8s-demo


<#
    Go to Azure arc kubernetes cluster select gitops and add, provide following information

    Configuration name: cluster-config
    Operator instance name: cluster-config
    Operator namespace: cluster-config
    Repository URL: https://github.com/Azure/arc-k8s-demo.git
    Operator scope: Cluster
    add
#>

# list all service config
kubectl.exe get services

# list specific service config for azure vote application
kubectl.exe get services azure-vote-front

# Scale up/down node count
Set-AksHciClusterNodeCount -clusterName $targetClusterName -linuxNodeCount 2 -windowsNodeCount 0

# scale up azure vote application pod count


# uninstall / remove from Azure Arc
Uninstall-AksHciArcOnboarding -clusterName "target-cls1"

#Retreive AksHCI logs for Target Cluster deployment
Get-AksHciLogs

#List k8s clusters
Get-AksHciCluster

#Remove Target cluster
Remove-AksHciCluster -clusterName $targetClusterName

