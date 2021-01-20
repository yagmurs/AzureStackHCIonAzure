#Deploy Target Cluster
New-AksHciCluster -clusterName worker-cls1 -kubernetesVersion v1.18.8 `
    -controlPlaneNodeCount 1 -linuxNodeCount 1 -windowsNodeCount 0 `
    -controlplaneVmSize default -loadBalancerVmSize default -linuxNodeVmSize Standard_D4s_v3 -windowsNodeVmSize default

#Retreive AksHCI logs for Target Cluster deployment
