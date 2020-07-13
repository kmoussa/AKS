#!/bin/bash
echo -e ".  . .  .  . .  .  . .  .  . .  .  . .  .  . .  
   .       .    .  .       .   .   .       .     .
     .  .    ;8:8SSS: . .  ;8;8%SS.  .  .    .    
 .       . tt S%88888:%% %; S;8@888:%t   .     .  
   .  .   .%@88888888@88 %@888888888@8     .  .  .
  .    .   %@88888888888:S@88S88888888:  .   .    
    .    . %XS888888X888.S@S88X8888888.    .    . 
  .   . :;:%@888t %.S%%t:%@8@@SS %8XSt;:.     .   
    .:8 8;88@X@;.;.t8X8X%@XtX;.:;%8@8;:8.8;.     .
  .  8;S8%8@@X88:::X..8 888X88%.t;S 8%XX8@8@8 .   
    .@@@XX8888888t;8@XXX888888 :t8%88%S888888:  . 
  . .888X%8X88%8@;;8XSS.888888; %X8%8%XS8@88t     
     8@88@8888S%@..t8X8Xt888X8X t88XtS.888Stt. .  
  .    S@t8t8%t@%@X%X8%%@:88@8%@@SX8%88S8@.  .    
           ttX S88888Xtt S.S.;8@888Xtt.  ..   .   
  .  .  .  %@X88%@888888.%X8@8S888888@ . ...    . 
   .       %@888X@8888X8:SX@88888888@8.   . . .   
      .  . %XS8888888888:S@S88t8888888.    .      
 . .   .   ;S8%@SXX%;8S. tt8888@88 8X.  .    .  . 
    .    .   t;888t;..    ;t88888X::     .  .     
  .   .    . :::..     .  ...::;.     .       .   
    .   .     .   .  .   . .    . .  .   . .   .  
"


echo "================================================================="

echo "Welcome to the installation script of Full AKS..."
echo "Type your resource group Name:"
read resourceGroupName
echo "What is your deployment name?"
read deploymentName
echo "What is the name of your AKS Cluster?"
read ClusterName
echo "Which Azure DC you want to deploy your workloads?"
read location
echo "what is your Vnet address prefix for the whole deployment? i.e 10.0.0.0/8"
read VnetAddressPrefix
echo "what is your AKS Subnet prefix? i.e 10.0.0.0/16"
read aksSubnet
echo "what is your app gateway Subnet prefix? i.e 10.1.0.0/24"
read appGWSubnet
echo "How many AKS worker nodes do you need to provision?"
read workercount
az aks get-versions --location $location --output table
echo "What is the k8s version you want to deploy? i.e 1.15.10"
read k8sversion
echo "What is the AKS service CIDR? i.e 10.2.0.0/16"
read aksservicecidr
echo "What is the AKS DNS IP? i.e 10.2.0.10"
read aksdnsIP

out=$(uname)
if [[ $(echo $out | grep -i azure) == 'azure' ]];then

echo "no need to install jq, this is Azure cloud shell"
else if [[ $(echo $out | grep -i linux) == 'Linux' ]];then

apt-get install jq -y
else

brew install jq
fi
fi
az ad sp create-for-rbac --skip-assignment -o json > auth.json
sleep 90
appId=$(jq -r ".appId" auth.json)
password=$(jq -r ".password" auth.json)
objectId=$(az ad sp show --id $appId --query "objectId" -o tsv)


cat <<EOF > parameters.json
{
  "aksServicePrincipalAppId": { "value": "$appId" },
  "aksServicePrincipalClientSecret": { "value": "$password" },
  "aksServicePrincipalObjectId": { "value": "$objectId" },
  "virtualNetworkAddressPrefix": { "value": "$VnetAddressPrefix" },
  "aksSubnetAddressPrefix": { "value": "$aksSubnet" },
  "applicationGatewaySubnetAddressPrefix": { "value": "$appGWSubnet" },
  "aksAgentCount": { "value": $workercount },
  "kubernetesVersion": { "value": "$k8sversion" },
  "aksServiceCIDR": { "value": "$aksservicecidr" },
  "aksDnsServiceIP": { "value": "$aksdnsIP" },
  "aksEnableRBAC": { "value": true }
}
EOF

# create a resource group
az group create -n $resourceGroupName -l $location

# modify the template as needed
az deployment group create \
        -g $resourceGroupName \
        -n $deploymentName \
        --template-file template.json \
        --parameters parameters.json



az deployment group show -g $resourceGroupName -n $deploymentName --query "properties.outputs" -o json > deployment-outputs.json
# use the deployment-outputs.json created after deployment to get the cluster name and resource group name
aksClusterName=$(jq -r ".aksClusterName.value" deployment-outputs.json)
resourceGroupName=$(jq -r ".resourceGroupName.value" deployment-outputs.json)

az aks get-credentials --resource-group $resourceGroupName --name $aksClusterName

kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.5.5/deploy/infra/deployment-rbac.yaml
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

applicationGatewayName=$(jq -r ".applicationGatewayName.value" deployment-outputs.json)
resourceGroupName=$(jq -r ".resourceGroupName.value" deployment-outputs.json)
subscriptionId=$(jq -r ".subscriptionId.value" deployment-outputs.json)
identityClientId=$(jq -r ".identityClientId.value" deployment-outputs.json)
identityResourceId=$(jq -r ".identityResourceId.value" deployment-outputs.json)

wget https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/sample-helm-config.yaml -O helm-config.yaml
sleep 50

sed -i "s|<subscriptionId>|${subscriptionId}|g" helm-config.yaml
sed -i "s|<resourceGroupName>|${resourceGroupName}|g" helm-config.yaml
sed -i "s|<applicationGatewayName>|${applicationGatewayName}|g" helm-config.yaml
sed -i "s|<identityResourceId>|${identityResourceId}|g" helm-config.yaml
sed -i "s|<identityClientId>|${identityClientId}|g" helm-config.yaml
sed -i "s|led: false|led: true|g" helm-config.yaml

helm install ingress-azure \
  -f helm-config.yaml \
  application-gateway-kubernetes-ingress/ingress-azure \
  --version 1.2.0-rc3


  curl https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/aspnetapp.yaml -o aspnetapp.yaml

  kubectl apply -f aspnetapp.yaml

read -p "Do you want to add Azure Firewall to the deployment? " -n 1 -r

if [[  $REPLY =~ ^[Yy]$ ]]
then
    printf "\n"
    echo "What is your firewall name?"
   read FW_NAME
echo "what is your AZ Firewall Subnet prefix? i.e 10.2.0.0/24"
read AzFirewallSubnet
  #Install Firewall
QUERYRESULT=$(az aks list --query "[?name=='$aksClusterName'].{rg:resourceGroup, id:id, loc:location, vnet:agentPoolProfiles[].vnetSubnetId, ver:kubernetesVersion, svpid: servicePrincipalProfile.clientId}" -o json)
KUBE_VNET_NAME=$(echo $QUERYRESULT | jq '.[0] .vnet[0]' | grep -oP '(?<=/virtualNetworks/).*?(?=/)')
KUBE_FW_SUBNET_NAME="AzureFirewallSubnet" # this you cannot change
KUBE_ING_SUBNET_NAME="ingress-subnet" # here enter the name of your ingress subnet
KUBE_AGENT_SUBNET_NAME=$(echo $QUERYRESULT | jq '.[0] .vnet[0]' | grep -oP '(?<=/subnets/).*?(?=")')


az network vnet subnet create -g $resourceGroupName --vnet-name $KUBE_VNET_NAME -n $KUBE_FW_SUBNET_NAME --address-prefix $AzFirewallSubnet

az extension add --name azure-firewall

KUBE_AGENT_SUBNET_ID=$(echo $QUERYRESULT | jq '.[0] .vnet[0]')

FW_ROUTE_NAME="${FW_NAME}_fw_r"
FW_ROUTE_TABLE_NAME="${FW_NAME}_fw_rt"
FW_PUBLIC_IP=$(az network public-ip show -g $KUBE_GROUP -n $FW_IP_NAME --query ipAddress)
echo "what is your desired private IP for the AZ firewall?"
read FW_PRIVATE_IP

az network create -g $resourceGroupName -n $FW_NAME
az network route-table create -g $KUBE_GROUP --name $FW_ROUTE_TABLE_NAME
az network vnet subnet update --resource-group $KUBE_GROUP --route-table $FW_ROUTE_TABLE_NAME --ids $KUBE_AGENT_SUBNET_ID
az network route-table route create --resource-group $KUBE_GROUP --name $FW_ROUTE_NAME --route-table-name $FW_ROUTE_TABLE_NAME --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FW_PRIVATE_IP --subscription $SUBSCRIPTION_ID


az network firewall network-rule create --firewall-name $FW_NAME --collection-name "aksnetwork" --destination-addresses "$HCP_IP"  --destination-ports 443 9000 --name "allow network" --protocols "TCP" --resource-group $KUBE_GROUP --source-addresses "*" --action "Allow" --description "aks network rule" --priority 100

az network firewall application-rule create  --firewall-name $FW_NAME --collection-name "aksbasics" --name "allow network" --protocols http=80 https=443 --source-addresses "*" --resource-group $KUBE_GROUP --action "Allow" --target-fqdns "*.azmk8s.io" "aksrepos.azurecr.io" "*.blob.core.windows.net" "mcr.microsoft.com" "*.cdn.mscr.io" "management.azure.com" "login.microsoftonline.com" "api.snapcraft.io" "*auth.docker.io" "*cloudflare.docker.io" "*cloudflare.docker.com" "*registry-1.docker.io" --priority 100

az network firewall application-rule create  --firewall-name $FW_NAME --collection-name "akstools" --name "allow network" --protocols http=80 https=443 --source-addresses "*" --resource-group $KUBE_GROUP --action "Allow" --target-fqdns "download.opensuse.org" "packages.microsoft.com" "dc.services.visualstudio.com" "*.opinsights.azure.com" "*.monitoring.azure.com" "gov-prod-policy-data.trafficmanager.net" "apt.dockerproject.org" "nvidia.github.io" --priority 101
az network firewall application-rule create  --firewall-name $FW_NAME --collection-name "osupdates" --name "allow network" --protocols http=80 https=443 --source-addresses "*" --resource-group $KUBE_GROUP --action "Allow" --target-fqdns "download.opensuse.org" "*.ubuntu.com" "packages.microsoft.com" "snapcraft.io" "api.snapcraft.io"  --priority 102

#SERVICE_IP=$(kubectl get svc nginx-internal --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
#az network firewall nat-rule create  --firewall-name $FW_NAME --collection-name "inboundlbrules" --name "allow inbound load balancers" --protocols "TCP" --source-addresses "*" --resource-group $KUBE_GROUP --action "Dnat"  --destination-addresses $FW_PUBLIC_IP --destination-ports 80 --translated-address $SERVICE_IP --translated-port "80"  --priority 101

else
    echo "Your deployment is finished successfully..."
fi
