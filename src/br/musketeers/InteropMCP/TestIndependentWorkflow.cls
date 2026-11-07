/// Teste de workflow independente do InteropMCP
/// Valida se Ens.ErrProductionMismatchInDeferredResponse ocorre
/// quando uma task de workflow é criada sem passar pelo WorkflowBridge
Class br.musketeers.InteropMCP.TestIndependentWorkflow Extends %RegisteredObject
{

/// Executa o teste completo: cria task independente e registra resultados
ClassMethod RunTest() As %Status
{
    Set sc = $$$OK
    Set logFile = "/tmp/workflow_test.log"
    
    Try {
        Do ..WriteLog("=== INICIO TESTE WORKFLOW INDEPENDENTE ===", logFile)
        
        // 1. Verificar se role "Operators" existe
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId("Operators")
        If '$IsObject(role) {
            Do ..WriteLog("ERRO: Role 'Operators' nao encontrado", logFile)
            Return $$$ERROR($$$GeneralError, "Role Operators nao encontrado")
        }
        Do ..WriteLog("OK: Role 'Operators' encontrado", logFile)
        
        // 2. Criar TaskRequest independente
        Set request = ##class(EnsLib.Workflow.TaskRequest).%New()
        Set request.%Subject = "Independent Test: " _ $ZDateTime($Horolog, 3)
        Set request.%Message = "Task created without InteropMCP for validation of ErrProductionMismatchInDeferredResponse"
        Set request.%Priority = 1
        Set request.%Actions = "Approve,Reject"
        
        // 3. Distribuir a task
        Set token = ""
        Set sc = ##class(EnsLib.Workflow.Engine).%DistributeTask("Operators", request, .token)
        If $$$ISERR(sc) {
            Do ..WriteLog("ERRO %DistributeTask: "_$System.Status.GetErrorText(sc), logFile)
            Return sc
        }
        Do ..WriteLog("OK: Task distribuida. Token: "_token, logFile)
        
        // 4. Obter o ResponseToken do TaskResponse criado
        // Precisa buscar o TaskResponse recem criado
        Set taskId = ""
        Set since = $ZDateTime($Horolog-1,3)
        &sql(SELECT MAX(%ID) INTO :taskId FROM TaskResponse WHERE TaskStatus_Source = 'Operators' AND TaskStatus_TimeCreated >= :since)
        If taskId = "" {
            Do ..WriteLog("AVISO: Nao encontrou TaskResponse recem criado", logFile)
        } Else {
            Set response = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
            If '$IsObject(response) {
                Do ..WriteLog("AVISO: Nao conseguiu abrir TaskResponse ID="_taskId, logFile)
            } Else {
                Do ..WriteLog("TaskResponse ID: "_response.%Id(), logFile)
                Do ..WriteLog("ResponseToken: "_response.%TaskStatus.ResponseToken, logFile)
                Do ..WriteLog("TaskStatus.Response: "_$Get(response.%TaskStatus.Response), logFile)
            }
        }
        
        // 5. Verificar nome da produção no contexto atual
        Set prodName = $Get(^Ens.Runtime("Name"))
        Do ..WriteLog("Producao corrente: "_prodName, logFile)
        
        Do ..WriteLog("=== FIM TESTE WORKFLOW INDEPENDENTE ===", logFile)
        
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("EXCECAO: "_ex.DisplayString(), logFile)
    }
    Return sc
}

/// Escreve mensagem em arquivo de log
ClassMethod WriteLog(pMessage As %String, pLogFile As %String)
{
    Set tSC = $$$OK
    Try {
        Set file = ##class(%Stream.FileCharacter).%New()
        Do file.LinkToFile(pLogFile, "a")
        Do file.Write(pMessage _ $char(13, 10))
        Do file.%Close()
    } Catch ex {
        // ignore file errors
    }
}

/// Lista tasks pendentes no workflow
ClassMethod ListPendingTasks() As %Status
{
    Set sc = $$$OK
    Try {
        Write "=== Tasks Pendentes ===", !
        
        Set rs = ##class(%ResultSet).%New("%Library.ResultSet")
        Set sc = rs.Prepare("SELECT %ID, TaskStatus_RoleName, TaskStatus_IsComplete, %Subject FROM TaskResponse WHERE TaskStatus_IsComplete = 0 ORDER BY %ID DESC")
        If $$$ISERR(sc) {
            Write "Erro na consulta: "_$System.Status.GetErrorText(sc), !
            Return sc
        }
        Set sc = rs.Execute()
        
        While rs.Next() {
            Write "ID: "_rs.Get("%ID")_", Role: "_rs.Get("TaskStatus_RoleName")_
                  ", Complete: "_rs.Get("TaskStatus_IsComplete")_
                  ", Subject: "_rs.Get("%Subject"), !
        }
        
    } Catch ex {
        Set sc = ex.AsStatus()
        Write "Erro: "_ex.DisplayString(), !
    }
    Return sc
}

/// Limpa tasks de teste antigas (opcional)
ClassMethod CleanupTestTasks() As %Status
{
    Set sc = $$$OK
    Try {
        Write "Limpando tasks de teste...", !
        &sql(DELETE FROM TaskResponse WHERE %Subject LIKE 'Teste Independente:%')
        Write "Rows deleted: "_SQLCODE, !
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Return sc
}

}