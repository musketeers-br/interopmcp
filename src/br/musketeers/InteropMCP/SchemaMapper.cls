/// IRIS MCP Gateway - schema mapper.
/// Derives the input parameter schema of an MCP tool from the property
/// metadata of the Business Service request class, so agents receive a
/// machine-readable parameter definition generated from the message structure
/// instead of hand-written schemas.
/// Type mapping (ObjectScript property type to schema token):
/// - %String, %Date, %TimeStamp and any unmapped type map to "string"
/// - %Integer maps to "integer", %Numeric maps to "number"
/// - %Boolean maps to "boolean"
/// - list/array collections map to "array"
/// A property is marked required when its Required flag is set.
Class br.musketeers.InteropMCP.SchemaMapper Extends %RegisteredObject
{

/// Opens the compiled class definition of pRequestClass and returns a
/// dynamic object with two members:
/// - properties: array of entries with name, type (schema token) and
///   required (boolean), one per locally defined property
/// - required: array of required property names
/// Fails gracefully (pSC carries the error, result stays empty) when the
/// class is not compiled.
ClassMethod MapProperties(pRequestClass As %String, Output pSC As %Status) As %DynamicObject
{
    Set pSC = $$$OK
    Set result = ##class(%DynamicObject).%New()
    Set props = ##class(%DynamicArray).%New()
    Set req = ##class(%DynamicArray).%New()
    Do result.%Set("properties", props)
    Do result.%Set("required", req)
    Set cd = ##class(%Dictionary.ClassDefinition).%OpenId(pRequestClass)
    If '$IsObject(cd) {
        Set pSC = $$$ERROR($$$GeneralError, "Class not compiled: "_pRequestClass)
    } Else {
        For i = 1:1:cd.Properties.Count() {
            Set pd = cd.Properties.GetAt(i)
            Set type = ..ToJsonSchemaType(pd.Type, pd.Collection)
            Set required = (pd.Required = 1)
            Set entry = ##class(%DynamicObject).%New()
            Do entry.%Set("name", pd.Name)
            Do entry.%Set("type", type)
            Do entry.%Set("required", required)
            Do props.%Push(entry)
            If required Do req.%Push(pd.Name)
        }
    }
    Quit result
}

/// Translates one ObjectScript property type (plus collection style) into the
/// schema token used by generated tool signatures. Unmapped types degrade to
/// "string" so agents still receive a usable parameter definition.
ClassMethod ToJsonSchemaType(pType As %String, pCollection As %String) As %String
{
    If (pCollection = "list") ! (pCollection = "array") Quit "array"
    If pType = "%String" Quit "string"
    If pType = "%Integer" Quit "integer"
    If pType = "%Numeric" Quit "number"
    If pType = "%Boolean" Quit "boolean"
    If (pType = "%Date") ! (pType = "%TimeStamp") Quit "string"
    Quit "string"
}

}
