/*
.TITLE
    Deallocate VM based on ActivityLog

.SYNOPSIS
    React to VMs which get shutdown by a user to deallocate the VM. 

.DESCRIPTION
    This terraform template creates an environment in your defined resourcegroup and subscription. This environment creates a logic app, alert rule, action group, managed identity, role assignment and an api connection.
    Each user initiated shutdown creates a new entry in the activity log of an Azure resource. 
    This event will trigger an alert if the resource is an VM so the logic app will get triggered by an action group to deallocate the VM if the log details contain the correct information.


.TAGS
    LogicApp, Automation, AlertRule, ActionGroup

.MINROLE
    Contributor

.PERMISSIONS
    tbd

.AUTHOR
    Simon Vedder

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-06-02

.NOTES

.USAGE
  1. Download 
  2. Run with Azure CLI: az deployment group create --name ExampleDeployment --resource-group ExampleGroup --template-file <path-to-bicep
*/

param defaultTags object = {
  Author: 'Simon Vedder'
  Contact: 'info@simonvedder.com'
  Project: 'DeallocateStoppedVM'
  ManagedBy: 'Bicep'
}

// api resources 
resource apiConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azurerm_connection'
  location: resourceGroup().location
  properties: {
    displayName: 'azurerm_connection'
    api: {
      id: '${subscription().id}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azurevm'
    }
  }
  tags: defaultTags
}

// permission 
module roleAssignment 'ra.bicep' = {
    scope: subscription()
    name: 'roleAssignment'
    params:{
        logicAppIdentity: logicApp.identity.principalId
    }
}

// alert & action
@description('Monitor Action Group to trigger Logic App')
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'TriggerLogicAppViaHealthAlert'
  location: 'global'
  properties: {
    groupShortName: 'HealthAlert'
    enabled: true
    webhookReceivers: [
      {
        name: 'TriggerLogicApp'
        serviceUri: logicApp.listCallbackUrl().value
        useCommonAlertSchema: true
      }
    ]
  }
  tags: defaultTags
}

@description('Activity Log Alert for Resource Health - UserInitiated events on VMs')
resource activityLogAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'TriggerLogicAppViaHealthAlert'
  location: resourceGroup().location
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'resourceType'
          equals: 'Microsoft.Compute/virtualMachines'
        }
        {
          field: 'resourceHealthStatus'
          equals: 'UserInitiated'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
  tags: defaultTags
}

// logic app
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'DeallocateStoppedVM'
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  tags: defaultTags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                data: {
                  type: 'object'
                  properties: {
                    context: {
                      type: 'object'
                      properties: {
                        activityLog: {
                          type: 'object'
                          properties: {
                            channels: { type: 'string' }
                            correlationId: { type: 'string' }
                            description: { type: 'string' }
                            eventDataId: { type: 'string' }
                            eventSource: { type: 'string' }
                            eventTimestamp: { type: 'string' }
                            level: { type: 'string' }
                            operationId: { type: 'string' }
                            operationName: { type: 'string' }
                            properties: {
                              type: 'object'
                              properties: {
                                cause: { type: 'string' }
                                currentHealthStatus: { type: 'string' }
                                details: { type: 'string' }
                                previousHealthStatus: { type: 'string' }
                                title: { type: 'string' }
                                type: { type: 'string' }
                              }
                            }
                            status: { type: 'string' }
                            submissionTimestamp: { type: 'string' }
                            subscriptionId: { type: 'string' }
                          }
                        }
                      }
                    }
                    status: { type: 'string' }
                  }
                }
                schemaId: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        Variable_VMName: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'VMName'
                type: 'string'
                value: '@{triggerBody()?[\'data\'][\'essentials\'][\'configurationItems\'][0]}'
              }
            ]
          }
        }
        Variable_LogDetails: {
          type: 'InitializeVariable'
          runAfter: {
            Variable_VMName: [ 'Succeeded' ]
          }
          inputs: {
            variables: [
              {
                name: 'Details'
                type: 'string'
                value: '@{triggerBody()?[\'data\'][\'alertContext\'][\'properties\'][\'details\']}'
              }
            ]
          }
        }
        Variable_ResourceGroup: {
          type: 'InitializeVariable'
          runAfter: {
            Variable_LogDetails: [ 'Succeeded' ]
          }
          inputs: {
            variables: [
              {
                name: 'RGName'
                type: 'string'
                value: '@{triggerBody()?[\'data\'][\'essentials\'][\'targetResourceGroup\']}'
              }
            ]
          }
        }
        Variable_Subscription: {
          type: 'InitializeVariable'
          runAfter: {
            Variable_ResourceGroup: [ 'Succeeded' ]
          }
          inputs: {
            variables: [
              {
                name: 'SubId'
                type: 'string'
                value: '@{split(triggerBody()?[\'data\'][\'essentials\'][\'alertId\'], \'/\')[2]}'
              }
            ]
          }
        }
        Condition: {
          type: 'If'
          runAfter: {
            Variable_Subscription: [ 'Succeeded' ]
          }
          expression: {
            and: [
              {
                contains: [
                  '@variables(\'Details\')'
                  'Virtual Machine is stopping'
                ]
              }
              {
                contains: [
                  '@variables(\'Details\')'
                  'due to a guest activity from within the Virtual Machine'
                ]
              }
            ]
          }
          actions: {
            Deallocate_VM: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azurevm\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/subscriptions/@{encodeURIComponent(variables(\'SubId\'))}/resourcegroups/@{encodeURIComponent(variables(\'RGName\'))}/providers/Microsoft.Compute/virtualMachines/@{encodeURIComponent(variables(\'VMName\'))}/deallocate'
                queries: {
                  'api-version': '2019-12-01'
                }
              }
            }
          }
          else: {
            actions: {}
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azurevm: {
            connectionId: resourceId('Microsoft.Web/connections', apiConnection.name)
            connectionName: apiConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourceGroup().location, 'azurevm')
            connectionProperties: {
                authentication: {
                    type: 'ManagedServiceIdentity'
                }
            }
          }
        }
      }
    }
  }
}
