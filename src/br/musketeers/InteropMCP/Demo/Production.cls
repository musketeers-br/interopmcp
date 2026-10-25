Class br.musketeers.InteropMCP.Demo.Production Extends Ens.Production
{

XData ProductionDefinition [ XMLNamespace = "http://www.intersystems.com/Production" ]
{
<Production Name="br.musketeers.InteropMCP.Demo.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Item Name="PayLookupBS" ClassName="br.musketeers.InteropMCP.Demo.PayLookupBS" PoolSize="1" Enabled="true" />
  <Item Name="CustomerUpdateBS" ClassName="br.musketeers.InteropMCP.Demo.CustomerUpdateBS" PoolSize="1" Enabled="true" />
  <Item Name="RiskCheckBS" ClassName="br.musketeers.InteropMCP.Demo.RiskCheckBS" PoolSize="1" Enabled="true" />
  <Item Name="BatchRunBS" ClassName="br.musketeers.InteropMCP.Demo.BatchRunBS" PoolSize="1" Enabled="true" />
  <Item Name="AuditProcess" ClassName="br.musketeers.InteropMCP.Demo.AuditProcess" PoolSize="1" Enabled="true" />
  <Item Name="AuditOperation" ClassName="br.musketeers.InteropMCP.Demo.AuditOperation" PoolSize="1" Enabled="true" />
</Production>
}

}
