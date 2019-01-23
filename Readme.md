# Description
zabbix-kubernetes is "plugin" used for Kubernetes monitoring. Easy to deploy and configure. Addition of all metrics for pods, deployments, services, etc are done automatically. Script designed to make addition of new metrics easy w/o interaction with scripting or console.
# Installation
1. Install required Perl modules with cpan
    * LWP::UserAgent
    * JSON
1. Copy scripts to zabbix external scripts path
1. Import Zabbix template
1. Configure zabbix macros in template with correct path to kubernetes config file (which can be used by kubectl)
1. Check other macros related to triger thresholds
1. Create Zabbix API user and assign appropriate permissions. User must have "Admin Role" and has access to host groups with monitored hosts
1. Check "CONFIG" section in both scripts and set appropriate values for variables

# Creating new items
Plugin has its own syntax for key. You dont need to change anything in scripts or creating cronjobs, etc. All you need to do is to create item with appropriate key. Items has the following syntax:
trap.k8s.\<kind\>[\<namespace\>,\<name\>,\<jsonpath\>]
* trap.k8s. - prefix used to filter items via Zabbix API, for 99.9% needs just write it as is.
* \<kind\> - can be pods,deployments,services,nodes
* \<namespace\> - namespace or none for deployments
* \<name\> - name from metadata (any kind)
* \<jsonpath\> - path inside of kubectl JSON output. For arrays additional expression must be set. E.g. for getting status of nodes in "conditoins": 
<br>trap.k8s.nodes[default,minikube,status.conditions(type=DiskPressure).status]

# Zabbix Marcos used:
* {$NAMESPACE} - per namespace separation (one zabbix host = one namespace)
* {$K8SCONFIG} - path to kubernetes config (should be readable by zabbix server)
* {$CONTAINER_RESTART_THRESH} - threshold for container restart count
