#https://docs.microsoft.com/en-us/azure-stack/aks-hci/setup-powershell

#the following function downloads, extract and place required PowerShell Modules in PowerShell modules folder
Prepare-AzureVMforAksHciDeployment

$targetDrive = "V:"
$AksHciTargetFolder = "AksHCIMain"
$AksHciTargetPath = "$targetDrive\$AksHciTargetFolder"
$sourcePath =  "$targetDrive\source" 

#pre-requisites 
# Install Az module to access Azure
Install-Module az

# Download and Install az cli
Start-BitsTransfer https://aka.ms/installazurecliwindows $sourcePath\azcli.msi
msiexec.exe /i $sourcePath\azcli.msi /qb

# Add and update Az Cli k8sconfiguration and connectedk8s extensions
# https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/connect-cluster
az extension add --name connectedk8s
az extension add --name k8sconfiguration
az extension update --name connectedk8s
az extension update --name k8sconfiguration

#Enable AksHCI
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

break

#list Aks Hci cmdlets
Get-Command -Noun akshci*

#List k8s clusters
Get-AksHciCluster

#Retreive AksHCI logs for Target Cluster deployment
Get-AksHciCredential -clusterName $targetClusterName

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
Install-AksHciArcOnboarding -clusterName $targetClusterName -resourcegroup $rg.ResourceGroupName -location $rg.location -subscriptionId $context.Subscription.Id -clientid $sp.ApplicationId -clientsecret $credObject.GetNetworkCredential().Password -tenantid $context.Tenant.Id

# get state of the onboarding process
kubectl get pods -n azure-arc-onboarding

# list error information
kubectl describe pod -n azure-arc-onboarding azure-arc-onboarding-<Name of the pod>
kubectl logs -n azure-arc-onboarding azure-arc-onboarding-<Name of the pod>

# deploy demo application from Azure Arc Enabled Kubernetes from Azure portal
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

# deploy demo application from Azure Arc Enabled Kubernetes using Az Cli
# https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/use-gitops-connected-cluster
az login
az k8sconfiguration create --name cluster-config --cluster-name $targetClusterName --resource-group $rg.ResourceGroupName --operator-instance-name cluster-config --operator-namespace cluster-config --repository-url https://github.com/Azure/arc-k8s-demo --scope cluster --cluster-type connectedClusters

# list all service config
kubectl.exe get services

# list specific service config for azure vote application
kubectl.exe get services azure-vote-front

# Scale up/down node count
Set-AksHciClusterNodeCount -clusterName $targetClusterName -linuxNodeCount 2 -windowsNodeCount 0

# scale up azure vote application pod count


# uninstall / remove from Azure Arc
Uninstall-AksHciArcOnboarding -clusterName $targetClusterName

#Retreive AksHCI logs for Target Cluster deployment
Get-AksHciLogs

#List k8s clusters
Get-AksHciCluster

#Remove Target cluster
Remove-AksHciCluster -clusterName $targetClusterName
