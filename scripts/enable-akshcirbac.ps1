#https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/azure-rbac

$subscriptionID = "123"

az extension add --name connectedk8s
az login --use-device-code

$CLUSTER_NAME="w-1"
$TENANT_ID="<tenant id>"
$SERVER_APP_ID=$(az ad app create --display-name "${CLUSTER_NAME}Server" --identifier-uris "api://${TENANT_ID}/ClientAnyUniqueSuffix" --query appId -o tsv)
$SERVER_APP_ID

az ad app update --id "${SERVER_APP_ID}" --set groupMembershipClaims=All

az ad sp create --id "${SERVER_APP_ID}"
$SERVER_APP_SECRET=$(az ad sp credential reset --name "${SERVER_APP_ID}" --credential-description "ArcSecret" --query password -o tsv)

az ad app permission add --id "${SERVER_APP_ID}" --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
az ad app permission grant --id "${SERVER_APP_ID}" --api 00000003-0000-0000-c000-000000000000

$CLIENT_APP_ID=$(az ad app create --display-name "${CLUSTER_NAME}Client" --native-app --reply-urls "api://${TENANT_ID}/ServerAnyUniqueSuffix" --query appId -o tsv)
$CLIENT_APP_ID

az ad sp create --id "${CLIENT_APP_ID}"

$oauthpermissionID = az ad app show --id "${SERVER_APP_ID}" --query "oauth2Permissions[0].id" -o tsv

az ad app permission add --id "${CLIENT_APP_ID}" --api "${SERVER_APP_ID}" --api-permissions $oauthpermissionID`=Scope
az ad app permission grant --id "${CLIENT_APP_ID}" --api "${SERVER_APP_ID}"

@"
{
    "Name": "Read authorization",
    "IsCustom": true,
    "Description": "Read authorization",
    "Actions": ["Microsoft.Authorization/*/read"],
    "NotActions": [],
    "DataActions": [],
    "NotDataActions": [],
    "AssignableScopes": [
      "/subscriptions/$subscriptionID"
    ]
}
"@ | Out-File -Encoding utf8 -FilePath .\accesscheck.yaml

$ROLE_ID=$(az role definition create --role-definition ./accessCheck.json --query id -o tsv)

az role assignment create --role "${ROLE_ID}" --assignee "${SERVER_APP_ID}" --scope /subscriptions/4df06176-1e12-4112-b568-0fe6d209bbe2

az config set extension.use_dynamic_install=yes_without_prompt

az connectedk8s enable-features -n w-1 -g sil-we1 --features azure-rbac --app-id "${SERVER_APP_ID}" --app-secret "${SERVER_APP_SECRET}"

$authBase64 = kubectl get secret azure-arc-guard-manifests -n kube-system -o yaml
$authBase64 | out-file -FilePath azure-arc-guard-manifests.yaml -Encoding utf8
notepad.exe .\azure-arc-guard-manifests.yaml # remove namespace section

<#
 Switch to Management Cluster at this point
#>

$env:KUBECONFIG = (Get-AksHciConfig).kva.kubeconfig
kubectl apply -f azure-arc-guard-manifests.yaml

kubectl get kcp 
kubectl edit kcp w-1-control-plane # edit config accordingly and amend mentioned changes

$env:KUBECONFIG = ""

$ARM_ID = az resource list -g sil-we1 -n w-1 --query "[0].id" -o tsv

az role assignment create --role "Azure Arc Enabled Kubernetes Cluster User Role" --assignee "6c2cae58-f2c7-4abb-aee0-eb7808ace117" --scope $ARM_ID
az role assignment create --role "Azure Arc Kubernetes Viewer" --assignee "6c2cae58-f2c7-4abb-aee0-eb7808ace117" --scope $ARM_ID/namespaces/azure-arc



$authnBase64 = kubectl get secret azure-arc-guard-manifests -n kube-system -o=jsonpath='{.data.guard-authn-webhook\.yaml}'
$authzBase64 = kubectl get secret azure-arc-guard-manifests -n kube-system -o=jsonpath='{.data.guard-authz-webhook\.yaml}'

[Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($authnBase64)) | out-file -FilePath guard-authn-webhook.yaml -Encoding utf8

[Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($authzBase64)) | out-file -FilePath guard-authz-webhook.yaml -Encoding utf8

scp.exe -i (Get-AksHciConfig).moc.sshPrivateKey .\guard-authn-webhook.yaml clouduser@192.168.1.1:/home/clouduser
scp.exe -i (Get-AksHciConfig).moc.sshPrivateKey .\guard-authz-webhook.yaml clouduser@192.168.1.1:/home/clouduser

scp.exe -i (Get-AksHciConfig).moc.sshPrivateKey clouduser@192.168.1.1

kubectl get secret azure-arc-guard-manifests -n kube-system -o yaml | Out-File -FilePath azure-arc-guard-manifests.yaml -Encoding utf8
kubectl apply -f .\azure-arc-guard-manifests.yaml

$env:kubeconfig= (Get-AksHciConfig).kva.kubeconfig

kubectl get kcp w-1-control-plane


kubectl config set-credentials pamirerdem_microsoft.com#EXT#@ygmrs.onmicrosoft.com `
--auth-provider=azure `
--auth-provider-arg=environment=AzurePublicCloud `
--auth-provider-arg=client-id=$CLIENT_APP_ID `
--auth-provider-arg=tenant-id=$TENANT_ID `
--auth-provider-arg=apiserver-id=$SERVER_APP_ID