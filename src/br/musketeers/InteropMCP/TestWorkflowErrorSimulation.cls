/// Simulação do erro Ens.ErrProductionMismatchInDeferredResponse
/// 
/// Contexto:
///   Ens.Host.SendDeferredResponse(pDeferredResponseToken, pResponse) faz:
///     Set tMessageHeaderId  = $p(token,"|",1)
///     Set tProductionName   = $p(token,"|",2)
///     Set tCurrentProduction = $g($$$EnsRuntime("Name"))   // ^Ens.Runtime("Name")
///     If (tCurrentProduction = "") || '##class(Ens.Director).IsProductionRunning() {
///         Set tSC = $$$EnsError($$$EnsErrProductionNotRunning) Quit }
///     If (tProductionName '= tCurrentProduction) {
///         Set tSC = $$$EnsError($$$EnsErrProductionMismatchInDeferredResponse) Quit }
/// 
///   O token tem o formato <messageHeaderId>|<productionName> e é gerado por
///   Ens.Host.GetDeferredResponseToken no momento em que a task é criada.
///   Se a produção for trocada/reiniciada com outro nome, o token fica obsoleto
///   e a aprovação via portal (EnsLib.Workflow.Engine.CompleteTask) falha.
/// 
/// Uso:
///   Do ##class(br.musketeers.InteropMCP.TestWorkflowErrorSimulation).RunSimulation()
///   Do ##class(br.musketeers.InteropMCP.TestWorkflowErrorSimulation).ReproduceError(<taskId>)
Class br.musketeers.InteropMCP.TestWorkflowErrorSimulation Extends %RegisteredObject
{

/// Nome de produção usado no ResponseToken para forçar o mismatch.
/// Deliberadamente diferente de ^Ens.Runtime("Name").
Parameter MismatchProductionName = "WRONG.Production.Name";

/// Verifica e ativa o DeepSee/IRIS BI para acesso ao User Portal
ClassMethod EnsureDeepSeeEnabled() As %Status
{
    Set sc = $$$OK
    Try {
        Set origNS = $ZNSPACE
        ZNSPACE "%SYS"
        Set cspPath = "/csp/irisapp/"
        Set enabled = $Get(^SYS("Security","CSP","AllowClass",cspPath,"%DeepSee."))
        If enabled = 1 {
            Do ..WriteLog("OK: DeepSee/IRIS BI já está ativo para "_cspPath)
        } Else {
            Do ..WriteLog("DeepSee/IRIS BI desativado para "_cspPath_" - ativando...")
            Do EnableDeepSee^%SYS.cspServer(cspPath)
            Set enabled = $Get(^SYS("Security","CSP","AllowClass",cspPath,"%DeepSee."))
            If enabled = 1 {
                Do ..WriteLog("OK: DeepSee/IRIS BI ativado para "_cspPath)
            } Else {
                Do ..WriteLog("AVISO: Não foi possível ativar DeepSee/IRIS BI para "_cspPath)
                Set sc = $$$ERROR($$$GeneralError,"Falha ao ativar DeepSee")
            }
        }
        ZNSPACE origNS
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERRO ao verificar/ativar DeepSee: "_ex.DisplayString())
    }
    Quit sc
}

/// Executa a simulação completa: setup + criação de task
/// Relatório é impresso no terminal
ClassMethod RunSimulation() As %Status
{
    Set sc = $$$OK
    
    Try {
        Do ..WriteLog("=== SIMULACAO DO ERRO: Ens.ErrProductionMismatchInDeferredResponse ===")
        Do ..WriteLog("Data: "_$ZDateTime($Horolog, 3))
        Do ..WriteLog("")
        
        // 0. Garantir DeepSee/IRIS BI ativo para o User Portal
        Set sc = ..EnsureDeepSeeEnabled()
        If $$$ISERR(sc) { Return sc }
        
        // 1. Verificar produção (necessária: sem produção o erro seria
        //    EnsErrProductionNotRunning, não o de mismatch)
        Do ..CheckProduction(.sc)
        If $$$ISERR(sc) { Return sc }
        
        // 2. Criar role de workflow "Operators"
        Do ..CreateWorkflowRole(.sc)
        If $$$ISERR(sc) { Return sc }
        
        // 3. Criar usuários de workflow
        Do ..CreateWorkflowUser(.sc)
        If $$$ISERR(sc) { Return sc }
        
        // 4. Associar usuário ao role
        Do ..AddUserToRole(.sc)
        If $$$ISERR(sc) { Return sc }
        
        // 5. Criar task de workflow independente (sem InteropMCP)
        Set taskId = ""
        Do ..CreateWorkflowTask(.sc, .taskId)
        If $$$ISERR(sc) { Return sc }
        
        Do ..WriteLog("")
        Do ..WriteLog("=== SETUP CONCLUÍDO ===")
        Do ..WriteLog("Task ID: "_taskId)
        Do ..WriteLog("")
        Do ..WriteLog("Acesse: http://localhost:52773/csp/irisapp/_DeepSee.UserPortal.Workflow.zen")
        Do ..WriteLog("Login: _SYSTEM / SYS")
        Do ..WriteLog("Aprove a task para reproduzir o erro.")
        Do ..WriteLog("")
        Do ..WriteLog("Erro esperado: Ens.ErrProductionMismatchInDeferredResponse")
        Do ..WriteLog("")
        Do ..WriteLog("Para reproduzir sem usar o portal:")
        Do ..WriteLog("Do ##class(br.musketeers.InteropMCP.TestWorkflowErrorSimulation).ReproduceError(""taskId"")")
        
    } Catch ex {
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// Verificar se há produção em execução.
/// Ens.Director.GetCurrProductionName() não existe nesta versão: usar
/// ^Ens.Runtime("Name") e Ens.Director.IsProductionRunning().
ClassMethod CheckProduction(ByRef sc As %Status)
{
    Try {
        Set prodName = $Get(^Ens.Runtime("Name"),"")
        If prodName = "" {
            Set sc = $$$ERROR($$$GeneralError, "Nenhuma produção em execução (^Ens.Runtime('Name') vazio)")
            Do ..WriteLog("ERRO: nenhuma produção em execução - o portal não consegue aprovar tasks")
            Return sc
        }
        Do ..WriteLog("OK: Produção em execução: "_prodName)
        
        If '##class(Ens.Director).IsProductionRunning() {
            Set sc = $$$ERROR($$$GeneralError, "Produção "_prodName_" não está rodando")
            Do ..WriteLog("ERRO: produção "_prodName_" não está rodando")
            Return sc
        }
        Do ..WriteLog("OK: Ens.Director.IsProductionRunning() = 1")
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERRO: "_ex.DisplayString())
    }
    Quit sc
}

/// Criar role de workflow
ClassMethod CreateWorkflowRole(ByRef sc As %Status)
{
    Try {
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId("Operators")
        If $IsObject(role) {
            Do ..WriteLog("OK: Role 'Operators' já existe")
            Return $$$OK
        }
        
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%New()
        Set role.Name = "Operators"
        Set role.Description = "Role for workflow testing"
        Set role.Capacity = 10
        Set sc = role.%Save()
        If $$$ISERR(sc) {
            Do ..WriteLog("ERRO ao criar role: "_$System.Status.GetErrorText(sc))
            Return sc
        }
        Do ..WriteLog("OK: Role 'Operators' criado")
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERRO: "_ex.DisplayString())
    }
    Quit sc
}

/// Criar usuários de workflow
ClassMethod CreateWorkflowUser(ByRef sc As %Status)
{
    Try {
        Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId("_SYSTEM")
        If '$IsObject(user) {
            Set user = ##class(EnsLib.Workflow.UserDefinition).%New()
            Set user.Name = "_SYSTEM"
            Set user.FullName = "System User"
            Set user.IsActive = 1
            Set sc = user.%Save()
            If $$$ISERR(sc) {
                Do ..WriteLog("ERRO ao criar usuário _SYSTEM: "_$System.Status.GetErrorText(sc))
                Return sc
            }
            Do ..WriteLog("OK: Usuário _SYSTEM criado como UserDefinition")
        } Else {
            Do ..WriteLog("OK: Usuário _SYSTEM já existe como UserDefinition")
        }
        
        // Opcional: criar usuário dedicado
        Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId("workflow_user")
        If '$IsObject(user) {
            Set user = ##class(EnsLib.Workflow.UserDefinition).%New()
            Set user.Name = "workflow_user"
            Set user.FullName = "Workflow Test User"
            Set user.IsActive = 1
            Set sc = user.%Save()
            If $$$ISERR(sc) {
                Do ..WriteLog("AVISO: Não foi possível criar usuário workflow_user: "_$System.Status.GetErrorText(sc))
            } Else {
                Do ..WriteLog("OK: Usuário 'workflow_user' criado")
            }
        } Else {
            Do ..WriteLog("OK: Usuário 'workflow_user' já existe")
        }
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("AVISO ao criar usuário: "_ex.DisplayString())
    }
    Quit $$$OK
}

/// Associar usuário ao role.
/// EnsLib.Workflow.RoleMembership expõe Role e User como referências de objeto
/// (propriedades RoleName/UserName não existem).
ClassMethod AddUserToRole(ByRef sc As %Status)
{
    Try {
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId("Operators")
        If '$IsObject(role) {
            Set sc = $$$ERROR($$$GeneralError, "Role Operators não encontrado")
            Return sc
        }
        
        Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId("_SYSTEM")
        If '$IsObject(user) {
            Set sc = $$$ERROR($$$GeneralError, "UserDefinition _SYSTEM não encontrado")
            Return sc
        }
        
        // Verificar se já existe membership usando global direta
        If $Data(^EnsLib.W.RoleMembershipD("Operators","_SYSTEM")) {
            Do ..WriteLog("OK: _SYSTEM já está associado ao role Operators")
            Return $$$OK
        }
        
        Set tMember = ##class(EnsLib.Workflow.RoleMembership).%New()
        Set tMember.Role = role
        Set tMember.User = user
        Set tMember.Title = "Operador"
        Set tMember.Ranking = 1
        Set sc = tMember.%Save()
        If $$$ISERR(sc) {
            Do ..WriteLog("ERRO ao associar usuário ao role: "_$System.Status.GetErrorText(sc))
            Return sc
        }
        Do ..WriteLog("OK: _SYSTEM associado ao role Operators")
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERRO: "_ex.DisplayString())
    }
    Quit sc
}

/// Criar task de workflow independente (sem InteropMCP).
/// 
/// Receita verificada:
///   1. request.NewResponse(.response) cria o TaskResponse
///      (Engine.%DistributeTask sozinho também cria, mas deixa ResponseToken vazio
///       porque o parâmetro pToken é ByValue)
///   2. response.%TaskStatus.Request = request  (obrigatório)
///   3. response.%TaskStatus.Role = role        (necessário para o portal listar)
///   4. response.%TaskStatus.ResponseToken = <id>|<produção errada>  (gera o mismatch)
///   5. response.%Save()
///   6. Engine.SendTaskToAll(response,.count)    (popula a Worklist do Inbox)
ClassMethod CreateWorkflowTask(ByRef sc As %Status, Output pTaskId As %String)
{
    Try {
        Set pTaskId = ""
        
        Set request = ##class(EnsLib.Workflow.TaskRequest).%New()
        Set request.%Subject = "Test: Production Mismatch Error"
        Set request.%Message = "Independent workflow task for simulation of ErrProductionMismatchInDeferredResponse"
        Set request.%Priority = 1
        Set request.%Actions = "Approve,Reject"
        
        Set response = ""
        Set sc = request.NewResponse(.response)
        If $$$ISERR(sc) {
            Do ..WriteLog("ERRO ao criar response: "_$System.Status.GetErrorText(sc))
            Return sc
        }
        
        Set response.%TaskStatus.Request = request
        
        // Copiar os campos do request para o response (o que %DistributeTask
        // faria). Sem isso a task aparece sem assunto no Inbox do portal.
        Set response.%Priority = request.%Priority
        Set response.%Subject = request.%Subject
        Set response.%Message = request.%Message
        Set response.%Actions = request.%Actions
        
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId("Operators")
        If $IsObject(role) {
            Set response.%TaskStatus.Role = role
        }
        Set response.%TaskStatus.IsComplete = 0
        
        // Token com nome de produção divergente do corrente -> mismatch no
        // Ens.Host.SendDeferredResponse
        Set response.%TaskStatus.ResponseToken = "999999|"_..#MismatchProductionName
        
        Set sc = response.%Save()
        If $$$ISERR(sc) {
            Do ..WriteLog("ERRO ao salvar task: "_$System.Status.GetErrorText(sc))
            Return sc
        }
        
        Set pTaskId = response.%Id()
        Do ..WriteLog("OK: Task criada com ID: "_pTaskId)
        Do ..WriteLog("ResponseToken: "_response.%TaskStatus.ResponseToken)
        
        // Popula a Worklist para os membros do role (é o que o portal lista)
        Set count = 0
        Set distSc = ##class(EnsLib.Workflow.Engine).SendTaskToAll(response, .count)
        If $$$ISERR(distSc) {
            Do ..WriteLog("AVISO ao popular worklist: "_$System.Status.GetErrorText(distSc))
        } Else {
            Do ..WriteLog("OK: Task enviada para "_count_" usuário(s) na Worklist")
        }
        
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERRO: "_ex.DisplayString())
    }
    Quit sc
}

/// Reproduz o erro programaticamente, sem precisar do portal.
/// Chama o mesmo caminho usado pela aprovação no portal:
///   EnsLib.Workflow.Engine.CompleteTask -> Ens.Host.SendDeferredResponse
/// 
/// Re-cria os itens de Worklist antes, porque Engine.CompleteTask os apaga
/// mesmo quando SendDeferredResponse falha.
ClassMethod ReproduceError(pTaskId As %String) As %Status
{
    Set sc = $$$OK
    Try {
        Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(pTaskId)
        If '$IsObject(task) {
            Set sc = $$$ERROR($$$GeneralError, "Task não encontrada: "_pTaskId)
            Return sc
        }
        
        Do ..WriteLog("Task: "_pTaskId)
        Do ..WriteLog("ResponseToken: "_task.%TaskStatus.ResponseToken)
        Do ..WriteLog("Produção corrente: "_$Get(^Ens.Runtime("Name"),"<vazio>"))
        
        // Recria a Worklist (Engine.CompleteTask apaga os itens)
        Set count = 0
        Set distSc = ##class(EnsLib.Workflow.Engine).SendTaskToAll(task, .count)
        If $$$ISERR(distSc) {
            Do ..WriteLog("AVISO ao popular worklist: "_$System.Status.GetErrorText(distSc))
        }
        
        Set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(task, "Approve")
        
        If $$$ISERR(sc) {
            Do ..WriteLog("")
            Do ..WriteLog("ERRO REPRODUZIDO: "_$System.Status.GetErrorText(sc))
            Do ..WriteLog("ErrorCodes: "_$System.Status.GetErrorCodes(sc))
        } Else {
            Do ..WriteLog("")
            Do ..WriteLog("Nenhum erro - CompleteTask retornou OK")
        }
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERRO: "_ex.DisplayString())
    }
    Quit sc
}

/// Escrever mensagem no terminal
ClassMethod WriteLog(pMessage As %String)
{
    Write pMessage, !
    Return $$$OK
}

}
