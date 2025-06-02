targetScope = 'subscription'

param logicAppIdentity string

// role assignment for managed identity
resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
    scope: subscription()
    name: '9980e02c-c2be-4d73-94e8-173b1dc7cf3c' // Virtual Machine Contributor
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id,'9980e02c-c2be-4d73-94e8-173b1dc7cf3c') 
  scope: subscription()
  properties: {
    roleDefinitionId: roleDefinition.id
    principalId: logicAppIdentity
    principalType: 'ServicePrincipal'
  }
}
