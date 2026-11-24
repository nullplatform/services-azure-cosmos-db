{
  "name": "Azure Cosmos DB",
  "slug": "azure-cosmos-db",
  "type": "dependency",
  "dimensions": {},
  "scopes": {},
  "assignable_to": "any",
  "use_default_actions": true,
  "available_actions": [],
  "available_links": ["connect"],
  "selectors": {
    "category": "Database",
    "imported": false,
    "provider": "Azure",
    "sub_category": "NoSQL Database"
  },
  "attributes": {
    "schema": {
      "type": "object",
      "$schema": "http://json-schema.org/draft-07/schema#",
      "required": [
        "containers"
      ],
      "properties": {
        "containers": {
          "type": "array",
          "title": "Containers",
          "description": "List of containers in this database",
          "minItems": 1,
          "editableOn": [
            "create",
            "update"
          ],
          "items": {
            "type": "object",
            "required": [
              "containerName",
              "partitionKey"
            ],
            "properties": {
              "containerName": {
                "type": "string",
                "order": 1,
                "title": "Container Name",
                "description": "Name of the container to store documents",
                "editableOn": [
                  "create"
                ]
              },
              "partitionKey": {
                "type": "string",
                "order": 2,
                "title": "Partition Key",
                "description": "Partition key path (e.g., /customerId, /tenantId)",
                "editableOn": [
                  "create"
                ]
              }
            }
          }
        }
      }
    },
    "values": {}
  }
}