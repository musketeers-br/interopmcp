Class br.musketeers.InteropMCP.Demo.Production Extends Ens.Production
{

XData ProductionDefinition [ XMLNamespace = "http://www.intersystems.com/Production" ]
{
<Production Name="br.musketeers.InteropMCP.Demo.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Item Name="PayLookupBS" ClassName="br.musketeers.InteropMCP.Demo.PayLookupBS" PoolSize="5" Enabled="true" />
  <Item Name="CustomerUpdateBS" ClassName="br.musketeers.InteropMCP.Demo.CustomerUpdateBS" PoolSize="5" Enabled="true" />
  <Item Name="RiskCheckBS"        ClassName="br.musketeers.InteropMCP.Demo.RiskCheckBS"        PoolSize="5" Enabled="true" />
  <Item Name="AccountBlockBS"     ClassName="br.musketeers.InteropMCP.Demo.AccountBlockBS"     PoolSize="5" Enabled="true" />
  <Item Name="BatchRunBS"         ClassName="br.musketeers.InteropMCP.Demo.BatchRunBS"         PoolSize="5" Enabled="true" />
  <Item Name="AgentHost" ClassName="br.musketeers.InteropMCP.Demo.AgentHost" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Purpose">Assesses a supplier from its invoice and says whether the order may proceed.</Setting>
    <Setting Target="Adapter" Name="Model">nvidia/nemotron-3.5-lightning-30b-a3b</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
    <Setting Target="Adapter" Name="LeaseSeconds">300</Setting>
    <Setting Target="Adapter" Name="Prompt">You are a risk analyst operating this production. When you are given a supplier invoice, read it and identify the supplier. The CNPJs in the ignoredCnpjs entry of the production configuration below are this company's own: they are never suppliers to assess, so ignore them entirely - do not check them against the restricted list and do not assess them. Before assessing the supplier you MUST check the restricted list, and you decide what to do with what you read: 1. Call ReadFile with the path given in the production configuration below (the restrictedCnpjsFile entry) to read the restricted list. Never rely on your own memory of the list: always read the file. 2. Compare the supplier's CNPJ with the CNPJs in the list you read. 3. If the supplier's CNPJ is on the list, do NOT run the risk assessment: call CreateWorkflowTask with toolName="RiskCheck", pParams={"Cnpj":"&lt;cnpj&gt;"} and pReason="CNPJ is restricted - requires human approval before risk assessment", then report that the request is pending approval. 4. If the supplier's CNPJ is not on the list, call RiskCheck with that CNPJ and assess it. If the list cannot be read, do not assess anything: report that the restricted list is unavailable. If the request names a supplier CNPJ that differs from the one in the document, check both and apply the stricter result.</Setting>
    <Setting Target="Adapter" Name="PolicyDocs">/home/irisowner/dev/src/br/musketeers/InteropMCP/Demo/Policies</Setting>
    <Setting Target="Adapter" Name="ProviderConfig">{"model_provider":"nim","base_url":"https://integrate.api.nvidia.com/v1","api_key":"@{env:NVIDIA_API_KEY}"}</Setting>
    <Setting Target="Adapter" Name="ProductionConfig">{"restrictedCnpjsFile": "restricted_cnpjs.txt", "ignoredCnpjs": ["44.555.666/0001-81"]}</Setting>
  </Item>
  <Item Name="AuditProcess" ClassName="br.musketeers.InteropMCP.Demo.AuditProcess" PoolSize="5" Enabled="true" />
  <Item Name="AuditOperation" ClassName="br.musketeers.InteropMCP.Demo.AuditOperation" PoolSize="5" Enabled="true" />
</Production>
}

}
