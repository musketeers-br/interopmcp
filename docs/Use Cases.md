# 📚 Matriz de Casos de Uso: IRIS MCP Gateway

---

### 1. 🏢 Copiloto de Atendimento & Operações de Backoffice (ERP / Faturamento)

* **O Ativo Legado no IRIS:** Uma Produção madura que conecta sistemas legados de cobrança, cadastro de clientes, faturamento de pedidos e emissão de notas fiscais via barramento de mensagens.
* **O Cenário de Uso do MCP:** Atendentes de suporte e operadores de backoffice utilizam um chat interno corporativo alimentado por um assistente de IA para resolver pendências de clientes em tempo real.
* **Como o MCP age na prática:**
* **Solicitação:** O cliente entra em contato informando que realizou um pagamento via PIX que ainda não consta como compensado e solicita a alteração do endereço de entrega.
* **Interação:** O operador digita no chat: *"Verifique o pagamento do pedido #88201 do cliente João Silva e atualize o endereço de entrega para a Rua X"*.
* **Execução via IRIS:** O assistente de IA, conectado ao **IRIS MCP Server**, identifica e invoca os Business Services expostos:
1. `BuscarPagamentoBS`: Executa a verificação transacional do recebimento.
2. `AtualizarCadastroBS`: Valida e atualiza o endereço nos sistemas de entrega e faturamento.


* **Resultado:** A integração é executada em segundos com total segurança transacional, e o operador obtém a confirmação direta sem precisar alternar entre múltiplos sistemas legados.



---

### 2. 🏭 Indústria 4.0 & Manutenção Preditiva: Diagnóstico de Chão de Fábrica (IoT / SCADA)

* **O Ativo Legado no IRIS:** Uma Produção robusta de alta performance que recebe telemetria contínua (MQTT/IoT) de máquinas industriais, realiza leitura de PLCs, processa regras de alerta de parada e gera ordens de serviço no ERP (SAP/TOTVS).
* **O Cenário de Uso do MCP:** Supervisores de produção e engenheiros de manutenção utilizam dispositivos móveis (tablets/smartphones) enquanto inspecionam as linhas de montagem.
* **Como o MCP age na prática:**
* **Solicitação:** O supervisor pergunta por voz ao assistente no tablet: *"O que está acontecendo com a Prensa Hidráulica 04 na Linha B?"*.
* **Execução via IRIS:** O agente de IA aciona a ferramenta MCP equivalente ao Business Service `GetMachineTelemetryAndAlertsBS`.
* **Processamento:** O IRIS varre a fila de eventos de telemetria, identifica os desvios de pressão registrados nos últimos minutos e localiza a Ordem de Serviço gerada no ERP.
* **Resultado:** O assistente responde em linguagem natural: *"A Prensa 04 registrou 3 picos de pressão anormais nos últimos 20 minutos. A Ordem de Serviço #8892 foi aberta automaticamente no SAP. Deseja reatribuir a prioridade da equipe técnica?"*.



---

### 3. 🚚 Logística & Last-Mile: Rastreamento e Gestão de Exceções de Entrega (EDI / TMS)

* **O Ativo Legado no IRIS:** Uma Produção de integração logistica que consolida informações de frotas próprias e APIs de múltiplas transportadoras parceiras via arquivos EDI (X12, EDIFACT) e XMLs de conhecimento de transporte.
* **O Cenário de Uso do MCP:** Operadores da central de atendimento logístico tratam chamados de clientes sobre cargas atrasadas ou retidas.
* **Como o MCP age na prática:**
* **Solicitação:** O operador insere no painel de suporte: *"O cliente do pedido #44901 relata que a encomenda não chegou no prazo. Qual o status real na transportadora?"*.
* **Execução via IRIS:** O agente invoca o Business Service `TrackShipmentStatusBS`.
* **Processamento:** O IRIS executa as chamadas síncronas/assíncronas já homologadas com os webservices e APIs das transportadoras envolvidas na rota.
* **Resultado:** A IA sintetiza a resposta: *"O pacote está retido no posto fiscal estadual desde ontem às 14h devido a uma divergência de alíquota na nota fiscal. O Business Service do IRIS abriu o alerta interno #992 para resolução do time fiscal"*.



---

### 4. ⚖️ Governança, Compliance & Legal: Due Diligence de Fornecedores (APIs Regulatórias)

* **O Ativo Legado no IRIS:** Uma Produção que orquestra consultas em órgãos governamentais (Receita Federal, Juntas Comerciais, Certidões Negativas) e birôs de crédito para homologação e auditoria de parceiros comerciais.
* **O Cenário de Uso do MCP:** Analistas do departamento jurídico ou de compliance precisam elaborar pareceres de aprovação de novos fornecedores estratégicos.
* **Como o MCP age na prática:**
* **Solicitação:** O analista comanda o assistente corporativo: *"Elabore a due diligence completa e verifique restrições para o CNPJ 00.000.000/0001-00"*.
* **Execução via IRIS:** O agente de IA utiliza o **IRIS MCP Server** para acionar a sequência de Business Services responsáveis pela comunicação com as bases governamentais e de crédito.
* **Processamento:** O IRIS efetua o encadeamento das requisições, faz a validação cruzada dos schemas de resposta e entrega o conjunto de dados normalizado.
* **Resultado:** O agente gera um relatório estruturado destacando pendências tributárias ou regulatórias com base no dossiê retornado pelo IRIS.



---

### 5. 🤖 Agentes Autônomos & Relatórios Corporativos (LangGraph / Frameworks de IA Externalizados)

* **O Ativo Legado no IRIS:** O conjunto completo de Produções de Interoperabilidade que conecta os diferentes silos de dados da empresa (Sistemas de RH, WMS, ERP e CRM).
* **O Cenário de Uso do MCP:** A empresa implementa fluxos automatizados de agentes de IA autônomos (desenvolvidos em Python, LangChain ou LangGraph) para geração de inteligência de negócios e relatórios executivos sob demanda.
* **Como o MCP age na prática:**
* **Solicitação:** A diretoria dispara uma rotina automática para um agente autônomo: *"Consolide o total de ordens de serviço pendentes na fábrica e cruze com os insumos parados no estoque WMS"*.
* **Execução via IRIS:** O agente autônomo não precisa conectar diretamente nos bancos legados nem reescrever rotinas de extração em Python. Ele utiliza o **IRIS MCP Server** como seu catálogo universal de APIs.
* **Processamento:** O agente invoca coordenadamente os Business Services `GetPendingWorkOrdersBS` e `GetWMSStockSummaryBS`.
* **Resultado:** O IRIS entrega os dados processados e validados pelas regras de negócio internas, permitindo que o agente monte a análise estratégica solicitada.
